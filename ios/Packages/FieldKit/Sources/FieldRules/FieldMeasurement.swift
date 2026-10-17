import CaptureContract
import Foundation

/// Builds a contract `FieldControls.Measurement` from what the operator typed.
public enum FieldMeasurement {
  /// Parses `text` in `unit` (see `LengthParser`) and returns the measurement with the value in
  /// millimetres, the unit and the text exactly as entered. Throws `LengthParseError`.
  public static func make(
    text: String,
    unit: EnteredUnit,
    method: MeasurementMethod = .tape,
    recordedAt: UTCTimestamp
  ) throws -> FieldControls.Measurement {
    let parsed = try LengthParser.parse(text, unit: unit)
    return FieldControls.Measurement(
      valueMm: parsed.valueMm,
      enteredUnit: parsed.unit,
      enteredText: parsed.enteredText,
      method: method,
      recordedAt: recordedAt)
  }
}
