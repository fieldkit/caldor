import 'dart:math';
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:fk_data_protocol/fk-data.pb.dart' as proto;
import 'package:protobuf/protobuf.dart';

enum CurveType {
  linear,
  exponential,
}

extension Conversion on CurveType {
  proto.CurveType into() {
    switch (this) {
      case CurveType.linear:
        return proto.CurveType.CURVE_LINEAR;
      case CurveType.exponential:
        return proto.CurveType.CURVE_EXPONENTIAL;
    }
  }
}

class SensorReading {
  final double uncalibrated;
  final double value;

  SensorReading({required this.uncalibrated, required this.value});

  String toDisplayString() {
    return "Reading($value, $uncalibrated)";
  }
}

class CalibrationPoint {
  final Standard standard;
  final SensorReading reading;

  CalibrationPoint({required this.standard, required this.reading});

  @override
  String toString() {
    return "CP($standard, ${reading.toDisplayString()})";
  }
}

abstract class Standard {
  bool get acceptable;

  double? get value;
}

class FixedStandard extends Standard {
  final double _value;

  FixedStandard(this._value);

  @override
  String toString() => "FixedStandard($_value)";

  @override
  bool get acceptable => true;

  @override
  double get value => _value;
}

class DefaultStandard extends Standard {
  final double _value;

  DefaultStandard(this._value);

  @override
  String toString() => "DefaultStandard($_value)";

  @override
  bool get acceptable => true;

  @override
  double get value => _value;
}

class UnknownStandard extends Standard {
  @override
  String toString() => "Unknown()";

  @override
  bool get acceptable => false;

  @override
  double? get value => null;
}

class UserStandard extends Standard {
  final double _value;

  UserStandard(this._value);

  @override
  String toString() => "UserStandard($_value)";

  @override
  bool get acceptable => true;

  @override
  double get value => _value;
}

// Calculates the coefficients for an exponential calibration curve.
List<double> exponentialCurve(List<CalibrationPoint> points) {
  ParametrizedUnaryFunction<double> fn =
      ParametrizedUnaryFunction.list(DataType.float, 3, (params) {
    return (double t) {
      return params[0] + params[1] * exp(t * params[2]);
    };
  });

  // Pete 4/6/2022
  final lm = LevenbergMarquardt(fn,
      initialValues: [1000.0, 1500000.0, -7.0].toVector(),
      gradientDifference: 10e-2,
      maxIterations: 100,
      errorTolerance: 10e-3,
      damping: 1.5);

  final xs = points.map((p) => p.reading.uncalibrated).toVector();
  final ys = points.map((p) => p.standard.value!).toVector();

  final v = lm.fit(xs: xs, ys: ys);

  return v.parameters;
}

// Calculates the coefficients for a linear calibration curve.
List<double> linearCurve(List<CalibrationPoint> points) {
  final n = points.length;
  final x = points.map((p) => p.reading.uncalibrated).toList();
  final y = points.map((p) => p.standard.value!).toList();

  final indices = List<int>.generate(n, (i) => i);
  final xMean = x.average();
  final yMean = y.average();
  final numerParts = indices.map((i) => (x[i] - xMean) * (y[i] - yMean));
  final denomParts = indices.map((i) => pow((x[i] - xMean), 2));
  final numer = numerParts.sum();
  final denom = denomParts.sum();

  final m = numer / denom;
  final b = yMean - m * xMean;

  return [b, m];
}

double _applyLinearValue(
    double value, List<proto.CalibrationPoint> calibration) {
  if (calibration.length < 2) {
    // Handle error: not enough calibration data
    return 0.0;
  }

  double a = calibration[0].uncalibrated[0];
  double b = calibration[1].uncalibrated[0];

  return a + b * value; // Apply linear calibration
}

double _applyExponentialValue(
    double value, List<proto.CalibrationPoint> calibration) {
  if (calibration.length < 3) {
    // Handle error: not enough calibration data
    return 0.0;
  }

  double a = calibration[0].uncalibrated[0];
  double b = calibration[1].uncalibrated[0];
  double c = calibration[2].uncalibrated[0];

  return a * exp(b * value) + c; // Apply exponential calibration
}

double calibrateValue(proto.CurveType curveType, double value,
    List<proto.CalibrationPoint> calibration) {
  switch (curveType) {
    case proto.CurveType.CURVE_LINEAR:
      return _applyLinearValue(value, calibration);
    case proto.CurveType.CURVE_EXPONENTIAL:
      return _applyExponentialValue(value, calibration);
    default:
      throw Exception("Unknown curve type: $curveType");
  }
}

class CalibrationTemplate {
  final CurveType curveType;
  final List<Standard> standards;

  CalibrationTemplate({required this.curveType, required this.standards});

  static CalibrationTemplate waterPh() => CalibrationTemplate(
      curveType: CurveType.linear,
      standards: [DefaultStandard(4), DefaultStandard(7), DefaultStandard(10)]);

  static CalibrationTemplate waterDissolvedOxygen() => CalibrationTemplate(
      curveType: CurveType.linear,
      standards: [UnknownStandard(), UnknownStandard(), UnknownStandard()]);

  static CalibrationTemplate waterEc() => CalibrationTemplate(
      curveType: CurveType.exponential,
      standards: [UnknownStandard(), UnknownStandard(), UnknownStandard()]);

  static CalibrationTemplate waterTemp() => CalibrationTemplate(
      curveType: CurveType.linear,
      standards: [UnknownStandard(), UnknownStandard(), UnknownStandard()]);

  static CalibrationTemplate showCase() => CalibrationTemplate(
      curveType: CurveType.linear,
      standards: [UnknownStandard(), FixedStandard(10)]);

  static CalibrationTemplate? forModuleKey(String key) {
    switch (key) {
      case "modules.water.temp":
        return waterTemp();
      case "modules.water.ph":
        return waterPh();
      case "modules.water.do":
        return waterDissolvedOxygen();
      case "modules.water.ec":
        return waterEc();
    }
    return null;
  }
}

enum CalibrationKind {
  // TODO: @jlewallen, what should be here?
  none,
}

// Represents the current state of a sensor calibration.
class CurrentCalibration {
  final CurveType curveType;
  final CalibrationKind kind;
  final List<CalibrationPoint> _points = List.empty(growable: true);

  CurrentCalibration(
      {required this.curveType, this.kind = CalibrationKind.none});

  @override
  String toString() => _points.toString();

  // Adds a new calibration point.
  void addPoint(CalibrationPoint point) {
    _points.add(point);
  }

  // Converts current calibration data to protobuf format.
  proto.ModuleConfiguration toDataProtocol() {
    final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cps = _points
        .map((p) => proto.CalibrationPoint(
            references: [p.standard.value!],
            uncalibrated: [p.reading.uncalibrated],
            factory: [p.reading.value]))
        .toList();
    final coefficients = calculateCoefficients();
    final calibration = proto.Calibration(
        time: time,
        kind: kind.index,
        type: curveType.into(),
        points: cps,
        coefficients: proto.CalibrationCoefficients(values: coefficients));
    return proto.ModuleConfiguration(calibrations: [calibration]);
  }

  // Calculates and returns the coefficients for the current calibration curve.
  List<double> calculateCoefficients() {
    if (_points.isEmpty) {
      throw Exception("No calibration points available");
    }

    if (_points.length == 1) {
      throw Exception("Not enough calibration points available");
    }
    switch (curveType) {
      case CurveType.linear:
        return linearCurve(_points);
      case CurveType.exponential:
        return exponentialCurve(_points);
    }
  }

  // Serializes the current calibration configuration to bytes.
  Uint8List toBytes() {
    final proto.ModuleConfiguration config = toDataProtocol();
    final buffer = config.writeToBuffer();
    final delimitted = CodedBufferWriter();
    delimitted.writeInt32NoTag(buffer.lengthInBytes);
    delimitted.writeRawBytes(buffer);
    return delimitted.toBuffer();
  }
}

CurrentCalibration createCalibration(
    String moduleKey, List<CalibrationPoint> points) {
  // Retrieve the calibration template for the given module type
  CalibrationTemplate? template = CalibrationTemplate.forModuleKey(moduleKey);

  if (template == null) {
    throw Exception("Unknown module key: $moduleKey");
  }

  if (template.standards.length > points.length) {
    throw Exception(
        "Not enough calibration points provided. Expected ${template.standards.length}, got ${points.length}");
  }

  // Create a CurrentCalibration instance based on the curve type
  CurrentCalibration currentCalibration =
      CurrentCalibration(curveType: template.curveType);

  // Add the provided points to the CurrentCalibration
  for (var point in points) {
    currentCalibration.addPoint(point);
  }

  return currentCalibration;
}
