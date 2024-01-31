# Caldor: The in-Situ Calibration System

## Short Description
Caldor is an innovative in-situ calibration system designed for field instrumentation, allowing for convenient and accurate calibration using traceable standards. This system, developed by the FieldKit Project team at Conservify, integrates Human-Computer Interaction (HCI) principles to minimize errors and enhance data integrity in environmental sensing.

## Features
- **In-Field Calibration:** Enables calibration in remote locations without needing lab facilities.
- **Educational Resources:** Provides comprehensive guidelines on calibration procedures.
- **User-Friendly Interface:** Simplifies the calibration process when paired with the intuitive app.
- **Versatility:** Compatible with various sensors like temperature, pH, conductivity, etc.
- **Data Integrity:** Ensures high-quality data with traceable calibration standards.

## Getting Started
- **Prerequisites:** 
    - `Linux`
    - `Chrome`
    - `bash`
    - `git`
    - `curl`
    - `Flutter`
    - `Dart`

- **Installation:** 
    - `sudo apt-get update -y && sudo apt-get install`
    
- **Initial Configuration:** `dart pub get` or `flutter pub get`

## Usage
To run: `dart run`
To test: `dart test` or `flutter test`

To use the library you've provided for calculating and handling sensor calibrations, follow this step-by-step guide:

### Step 1: Determine the Sensor Type

First, identify the type of sensor you need to calibrate. This could be, for example, `modules.water.ph`, `modules.water.do`, `modules.water.ec`, or `modules.water.temp`.

### Step 2: Select the Appropriate Calibration Template

Use the `CalibrationTemplate.forModuleKey` method to retrieve a `CalibrationTemplate` that corresponds to your sensor type. 

Example:
```dart
String sensorType = "modules.water.ph"; // Replace with your sensor type
CalibrationTemplate template = CalibrationTemplate.forModuleKey(sensorType);
```

### Step 3: Collect Calibration Points

Gather a set of `CalibrationPoint` objects. Each point should include a `Standard` (which could be a `FixedStandard`, `UnknownStandard`, or `UserStandard`) and a corresponding `SensorReading` (which includes both uncalibrated and calibrated values, if available).

Example:
```dart
List<CalibrationPoint> points = [
  CalibrationPoint(
    standard: FixedStandard(4), // Replace with actual standard value
    reading: SensorReading(uncalibrated: 1.0, value: 4.0), // Replace with actual readings
  ),
  // Add more CalibrationPoint objects as required
];
```

### Step 4: Calculate the Calibration Curve

Depending on the `CurveType` in your `CalibrationTemplate` (either linear or exponential), use the respective function (`linearCurve` or `exponentialCurve`) to calculate the calibration curve coefficients.

Example:
```dart
List<double> coefficients;
if (template.curveType == CurveType.linear) {
  coefficients = linearCurve(points);
} else if (template.curveType == CurveType.exponential) {
  coefficients = exponentialCurve(points);
} else {
  throw Exception("Unknown curve type: ${template.curveType}");
}
```

### Step 5: Utilize the Calculated Coefficients

The `coefficients` list obtained from the previous step can now be used as needed in your application. This could be for sensor data correction, display, or further processing.

### Step 6: Serialize Calibration Data (Optional)

If you need to serialize the calibration data (e.g., for storage or transmission), you can use the `toBytes` method from `CurrentCalibration`. Ensure to add all the calibration points to `CurrentCalibration` before serialization.

Example:
```dart
CurrentCalibration currentCalibration = CurrentCalibration(curveType: template.curveType);
for (var point in points) {
  currentCalibration.addPoint(point);
}
Uint8List serializedData = currentCalibration.toBytes();
```

### Step 7: Deserialize Calibration Data (Optional)

To deserialize, you would typically use the `proto.ModuleConfiguration` to parse the bytes back into a meaningful structure. This process will depend on how you handle protobuf data in your application.


## Additional Information
For more information on the Caldor package, including how to contribute, report issues, or get support, visit our [GitHub repository](https://github.com/fieldkit/caldor).