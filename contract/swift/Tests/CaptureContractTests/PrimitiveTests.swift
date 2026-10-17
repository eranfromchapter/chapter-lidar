import CaptureContract
import Foundation
import XCTest

/// Wire formats shared by every schema: UTC timestamps with whole seconds and lowercase UUIDs.
final class PrimitiveTests: XCTestCase {
  private struct Box<T: Codable & Equatable>: Codable, Equatable {
    var value: T
  }

  private func encode<T: Codable & Equatable>(_ value: T) throws -> String {
    String(decoding: try CaptureContractJSON.makeEncoder().encode(Box(value: value)), as: UTF8.self)
  }

  private func decode<T: Codable & Equatable>(_ type: T.Type, _ json: String) throws -> T {
    try CaptureContractJSON.makeDecoder().decode(Box<T>.self, from: Data(json.utf8)).value
  }

  // MARK: UTCTimestamp

  func testTimestampEncodesUTCWholeSecondsWithZ() throws {
    let timestamp = UTCTimestamp(Date(timeIntervalSince1970: 1_792_245_731.875))
    XCTAssertEqual(try encode(timestamp), #"{"value":"2026-10-17T14:02:11Z"}"#)
    XCTAssertEqual(timestamp.date.timeIntervalSince1970, 1_792_245_731)
  }

  func testTimestampDecodesAndReencodesUnchanged() throws {
    let timestamp = try decode(UTCTimestamp.self, #"{"value":"2026-10-17T14:02:11Z"}"#)
    XCTAssertEqual(timestamp.date.timeIntervalSince1970, 1_792_245_731)
    XCTAssertEqual(timestamp.rawValue, "2026-10-17T14:02:11Z")
    XCTAssertEqual(try encode(timestamp), #"{"value":"2026-10-17T14:02:11Z"}"#)
  }

  func testTimestampRejectsOtherFormats() {
    for text in [
      "2026-10-17T14:02:11.250Z",
      "2026-10-17T14:02:11+00:00",
      "2026-10-17T10:02:11-04:00",
      "2026-10-17 14:02:11Z",
      "2026-10-17T14:02Z",
      "2026-10-17",
      "2026-13-17T14:02:11Z",
      "",
    ] {
      XCTAssertNil(UTCTimestamp(rawValue: text), text)
      XCTAssertThrowsError(try decode(UTCTimestamp.self, #"{"value":"\#(text)"}"#), text)
    }
  }

  // MARK: LowercaseUUID

  func testUUIDEncodesLowercase() throws {
    let uuid = UUID(uuidString: "7C4E1B9A-2D3F-4A68-9B5C-E0F1A2B3C4D5")!
    XCTAssertEqual(
      try encode(LowercaseUUID(uuid)), #"{"value":"7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5"}"#)
    XCTAssertEqual(LowercaseUUID(uuid).uuid, uuid)
  }

  func testUUIDDecodesLowercaseOnly() throws {
    let decoded = try decode(
      LowercaseUUID.self, #"{"value":"7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5"}"#)
    XCTAssertEqual(decoded.rawValue, "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")
    XCTAssertNil(LowercaseUUID(rawValue: "7C4E1B9A-2D3F-4A68-9B5C-E0F1A2B3C4D5"))
    XCTAssertNil(LowercaseUUID(rawValue: "not-a-uuid"))
    XCTAssertThrowsError(
      try decode(LowercaseUUID.self, #"{"value":"7C4E1B9A-2D3F-4A68-9B5C-E0F1A2B3C4D5"}"#))
  }

  func testNewUUIDIsLowercase() {
    let uuid = LowercaseUUID()
    XCTAssertEqual(uuid.rawValue, uuid.rawValue.lowercased())
  }

  // MARK: Fixed-size vectors

  func testVec3AndQuaternionRequireExactLength() throws {
    XCTAssertEqual(try decode(Vec3.self, #"{"value":[1,2.5,-3]}"#), Vec3(x: 1, y: 2.5, z: -3))
    XCTAssertThrowsError(try decode(Vec3.self, #"{"value":[1,2]}"#))
    XCTAssertThrowsError(try decode(Vec3.self, #"{"value":[1,2,3,4]}"#))
    XCTAssertEqual(
      try decode(Quaternion.self, #"{"value":[0,0,0,1]}"#), Quaternion.identity)
    XCTAssertThrowsError(try decode(Quaternion.self, #"{"value":[0,0,1]}"#))
  }

  // MARK: Omitted optionals

  func testNilOptionalsAreOmittedNotNull() throws {
    let note = CaptureRecord.RoomNote(name: "Primary closet")
    XCTAssertEqual(
      String(decoding: try CaptureContractJSON.makeEncoder().encode(note), as: UTF8.self),
      #"{"name":"Primary closet"}"#)
  }
}
