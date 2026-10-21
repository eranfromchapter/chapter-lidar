import CaptureContract
import Foundation
import StationClient

/// Response bodies shaped exactly like contract/openapi/station.yaml. Ids are lowercase, times
/// are whole-second UTC, optional fields are omitted.
enum Fixtures {
  static let packageId = UUID(uuidString: "6f1c2b8e-3d4a-4f5b-9c6d-7e8f9a0b1c2d")!
  static let visitId = UUID(uuidString: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")!
  static let captureId = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
  static let packageIdText = "6f1c2b8e-3d4a-4f5b-9c6d-7e8f9a0b1c2d"
  static let visitIdText = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d"
  static let sha = String(repeating: "a", count: 64)

  static let health = #"{"status":"ok","version":"1.4.0"}"#

  static let project =
    #"{"dealId":"4821","projectName":"Kitchen and bath","address":{"formatted":"345 7th Ave, New York, NY 10001"}}"#

  static let projects =
    #"{"projects":[\#(project),{"dealId":"4822","address":{"formatted":"252 NW 29th St, Miami, FL 33127"}}]}"#

  static let uploadSession = """
    {"packageId":"\(packageIdText)","visitId":"\(visitIdText)","dealId":"4821","revision":1,\
    "status":"uploading","files":[{"path":"Source Register/\(visitIdText)/capture-record.json",\
    "status":"pending","upload":{"url":"https://blob.test/originals/capture-record.json",\
    "method":"PUT","headers":{"x-ms-blob-type":"BlockBlob"},"expiresAt":"2026-10-17T14:32:11Z"}},\
    {"path":"Field Measurements/field-controls.json","status":"verified"}]}
    """

  static let fileCheckNotUploaded = """
    {"path":"Field Measurements/field-controls.json","status":"not_uploaded",\
    "expectedSha256":"\(sha)","expectedBytes":512,"checkedAt":"2026-10-17T14:05:00Z"}
    """

  static let fileCheckVerified = """
    {"path":"Field Measurements/field-controls.json","status":"verified",\
    "expectedSha256":"\(sha)","actualSha256":"\(sha)","expectedBytes":512,"actualBytes":512,\
    "checkedAt":"2026-10-17T14:05:00Z"}
    """

  static let packageSummaries = """
    {"packages":[{"packageId":"\(packageIdText)","visitId":"\(visitIdText)","dealId":"4821",\
    "revision":1,"status":"verdict_ready","createdAt":"2026-10-17T14:00:00Z",\
    "sealedAt":"2026-10-17T13:55:00Z","verdict":{"verdictId":"22222222-3333-4444-8555-666666666666",\
    "outcome":"limited","evaluatedAt":"2026-10-17T14:10:00Z"}}]}
    """

  static let package = """
    {"packageId":"\(packageIdText)","visitId":"\(visitIdText)","dealId":"4821","revision":1,\
    "status":"checks_queued","createdAt":"2026-10-17T14:00:00Z","sealedAt":"2026-10-17T13:55:00Z",\
    "files":[{"path":"Field Measurements/field-controls.json","role":"field_controls",\
    "sha256":"\(sha)","bytes":512,"status":"verified","checkedAt":"2026-10-17T14:05:00Z"}]}
    """

  static let downloadLink = """
    {"path":"Field Measurements/field-controls.json","sha256":"\(sha)","bytes":512,\
    "url":"https://blob.test/originals/field-controls.json","expiresAt":"2026-10-17T14:15:00Z"}
    """

  static let decision = """
    {"decisionId":"33333333-4444-4555-8666-777777777777","packageId":"\(packageIdText)",\
    "element":"Floor 1 kitchen north wall","decision":"Wall length taken from tape distance A",\
    "sources":[{"path":"Field Measurements/field-controls.json","controlId":"dist-a"}],\
    "decidedBy":{"name":"BIM Operator","userId":"0000aaaa-bbbb-cccc-dddd-eeeeffff0000"},\
    "decidedAt":"2026-10-17T15:00:00Z"}
    """

  static let decisions = #"{"decisions":[\#(decision)]}"#

  /// A 1.1.0 package (`Package`): checks, publication, links and the next-revision notice, and a
  /// file carried over from revision 1.
  static let packageV1_1 = """
    {"packageId":"\(packageIdText)","visitId":"\(visitIdText)","dealId":"4821","revision":2,\
    "supersedesPackageId":"44444444-5555-4666-8777-888888888888",\
    "status":"verdict_ready","createdAt":"2026-10-17T14:00:00Z","sealedAt":"2026-10-17T13:55:00Z",\
    "updatedAt":"2026-10-17T14:12:00Z","captures":[],\
    "totals":{"files":1,"bytes":512,"filesVerified":1,"bytesVerified":512},\
    "files":[{"path":"Field Measurements/field-controls.json","role":"field_controls",\
    "sha256":"\(sha)","bytes":512,"status":"verified","checkedAt":"2026-10-17T14:05:00Z",\
    "generator":"chapter-capture-ios/FieldKit","generatorVersion":"2.0.0",\
    "carriedOverFrom":"44444444-5555-4666-8777-888888888888"}],\
    "checks":{"status":"completed","startedAt":"2026-10-17T14:06:00Z",\
    "finishedAt":"2026-10-17T14:09:00Z","rules":13},\
    "publication":{"status":"published","publishedAt":"2026-10-17T14:11:00Z",\
    "hubFolder":"Capture/\(visitIdText)/r2"},\
    "links":{"review":"https://review.test/packages/\(packageIdText)",\
    "hub":"https://hub.test/deals/4821"},\
    "verdict":{"verdictId":"22222222-3333-4444-8555-666666666666","outcome":"limited",\
    "evaluatedAt":"2026-10-17T14:10:00Z"},\
    "nextRevision":\(nextRevisionNotice)}
    """

  /// A 1.1.0 session answer: `createdAt`, and a file carried over from revision 1.
  static let uploadSessionV1_1 = """
    {"packageId":"\(packageIdText)","visitId":"\(visitIdText)","dealId":"4821","revision":2,\
    "status":"uploading","createdAt":"2026-10-17T14:00:00Z","files":[\
    {"path":"Field Measurements/field-controls.json","status":"verified",\
    "carriedOverFrom":"44444444-5555-4666-8777-888888888888"}]}
    """

  static let nextRevisionNotice = """
    {"revision":2,"updatedAt":"2026-10-18T09:30:00Z","updatedBy":"Dana Ruiz","changes":[\
    {"kind":"added","subject":"capture","title":"Primary closet",\
    "detail":"Scanned · one room · 5 files",\
    "answersNextAction":"Scan or measure Primary closet on the next visit if it is in scope."},\
    {"kind":"added","subject":"field_control","title":"Room 4 ceiling height",\
    "detail":"Field control · 2,490 mm · 8' 2\\"","method":"tape"}]}
    """

  static let nextRevisionNoticeInput = NextRevisionNoticeInput(
    revision: 2, updatedAt: UTCTimestamp(secondsSince1970: 1_792_315_800),
    changes: [
      NextRevisionChange(
        kind: .added, subject: .capture, title: "Primary closet",
        detail: "Scanned · one room · 5 files",
        answersNextAction: "Scan or measure Primary closet on the next visit if it is in scope."),
      NextRevisionChange(
        kind: .added, subject: .fieldControl, title: "Room 4 ceiling height",
        detail: "Field control · 2,490 mm · 8' 2\"", method: .tape),
    ])

  /// contract/examples/verdict/valid/limited.json.
  static func verdict() throws -> String {
    String(
      decoding: try RepoFiles.data("contract/examples/verdict/valid/limited.json"), as: UTF8.self)
  }

  /// contract/examples/manifest/valid/two-captures.json, byte for byte.
  static func manifestBytes() throws -> Data {
    try RepoFiles.data("contract/examples/manifest/valid/two-captures.json")
  }
}
