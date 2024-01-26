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

class CalibrationTemplate {
  final CurveType curveType;
  final List<Standard> standards;

  CalibrationTemplate({required this.curveType, required this.standards});

  // Factory methods to create predefined calibration templates for different sensor types.
  static CalibrationTemplate waterPh() => CalibrationTemplate(
      curveType: CurveType.linear,
      standards: [FixedStandard(4), FixedStandard(7), FixedStandard(10)]);

  static CalibrationTemplate waterDissolvedOxygen() =>
      CalibrationTemplate(curveType: CurveType.linear, standards: [
        UnknownStandard(),
        UnknownStandard(),
        UnknownStandard()
      ]); // TODO @jlewallen, what should we put for these standards?

  static CalibrationTemplate waterEc() =>
      CalibrationTemplate(curveType: CurveType.exponential, standards: [
        UnknownStandard(),
        UnknownStandard(),
        UnknownStandard()
      ]); // TODO @jlewallen, what should we put for these standards?

  static CalibrationTemplate waterTemp() =>
      CalibrationTemplate(curveType: CurveType.exponential, standards: [
        UnknownStandard(),
        UnknownStandard(),
        UnknownStandard()
      ]); // TODO @jlewallen, what should we put for these standards?

  static CalibrationTemplate showCase() =>
      CalibrationTemplate(curveType: CurveType.linear, standards: [
        UnknownStandard(),
        FixedStandard(10)
      ]); // TODO @jlewallen, what should we put for these standards?

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
    if (curveType == CurveType.exponential) {
      return exponentialCurve(_points);
    } else if (curveType == CurveType.linear) {
      return linearCurve(_points);
    } else {
      throw Exception("Unknown curve type: $curveType");
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
