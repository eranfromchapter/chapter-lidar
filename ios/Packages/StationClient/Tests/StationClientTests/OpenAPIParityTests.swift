import Foundation
import StationClient
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Checks the client against contract/openapi/station.yaml, read from the repository:
/// - every operation (operationId, method, path) in the document is in `StationOperation`, and
///   nothing else is;
/// - security (`security: []` = no token) and success statuses match;
/// - calling every client method sends only requests that match a document operation, and covers
///   every document operation.
final class OpenAPIParityTests: XCTestCase {
  struct DocumentOperation: Hashable, CustomStringConvertible {
    var operationId: String
    var method: String
    var path: String
    var isPublic: Bool
    var successStatuses: Set<Int>

    var description: String { "\(operationId) \(method) \(path)" }
    var signature: String { "\(operationId) \(method) \(path)" }
  }

  struct Document {
    var serverURL: String?
    var operations: [DocumentOperation]
  }

  static let httpMethods: Set<String> = [
    "get", "put", "post", "delete", "patch", "head", "options", "trace",
  ]

  /// Minimal reader for the layout of station.yaml: top-level keys at indent 0, paths at indent 2,
  /// methods at 4, operation keys at 6, response codes at 8.
  static func parse(_ text: String) -> Document {
    var serverURL: String?
    var operations: [DocumentOperation] = []
    var section = ""
    var currentPath: String?
    var current: DocumentOperation?
    var inResponses = false

    func finish() {
      if let operation = current { operations.append(operation) }
      current = nil
      inResponses = false
    }

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
      let indent = line.prefix { $0 == " " }.count

      if indent == 0 {
        finish()
        section = trimmed
        continue
      }
      if section == "servers:" && trimmed.hasPrefix("- url:") && serverURL == nil {
        serverURL = trimmed.dropFirst("- url:".count).trimmingCharacters(in: .whitespaces)
        continue
      }
      guard section == "paths:" else { continue }

      switch indent {
      case 2 where trimmed.hasSuffix(":"):
        finish()
        currentPath = String(trimmed.dropLast())
      case 4:
        finish()
        let key = trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : trimmed
        if httpMethods.contains(key), let path = currentPath {
          current = DocumentOperation(
            operationId: "", method: key.uppercased(), path: path, isPublic: false,
            successStatuses: [])
        }
      case 6 where current != nil:
        inResponses = trimmed == "responses:"
        if trimmed.hasPrefix("operationId:") {
          current?.operationId = trimmed.dropFirst("operationId:".count)
            .trimmingCharacters(in: .whitespaces)
        }
        if trimmed.replacingOccurrences(of: " ", with: "") == "security:[]" {
          current?.isPublic = true
        }
      case 8 where current != nil && inResponses:
        let code = trimmed.replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: "'", with: "")
        if code.hasSuffix(":"), let status = Int(code.dropLast()), (200...299).contains(status) {
          current?.successStatuses.insert(status)
        }
      default:
        break
      }
    }
    finish()
    return Document(serverURL: serverURL, operations: operations)
  }

  /// Operations of station.yaml (1.1.0) that the phone client does not call: the review
  /// screen's lists, archive and report link. The parity checks below cover every other
  /// operation.
  static let notInClient: Set<String> = [
    "getSpatialReportLink",
    "requestPackageArchive",
    "getPackageArchive",
    "listReviewProjects",
    "listReviewPackages",
    "listAllModelingDecisions",
  ]

  func loadDocument() throws -> Document {
    let text = String(
      decoding: try RepoFiles.data("contract/openapi/station.yaml"), as: UTF8.self)
    var document = Self.parse(text)
    XCTAssertFalse(document.operations.isEmpty, "no operations read from station.yaml")
    for operation in document.operations {
      XCTAssertFalse(operation.operationId.isEmpty, "\(operation) has no operationId")
    }
    XCTAssertEqual(
      Self.notInClient.subtracting(document.operations.map(\.operationId)), [],
      "operations listed as not in the client that station.yaml does not have")
    document.operations.removeAll { Self.notInClient.contains($0.operationId) }
    return document
  }

  func testServerBasePathMatchesDocument() throws {
    XCTAssertEqual(try loadDocument().serverURL, StationOperation.serverBasePath)
  }

  func testEveryDocumentOperationIsInTheClientAndNothingElse() throws {
    let document = try loadDocument()
    let documented = Set(document.operations.map(\.signature))
    let client = Set(
      StationOperation.allCases.map { "\($0.operationId) \($0.method) \($0.pathTemplate)" })
    XCTAssertEqual(
      documented.subtracting(client), [], "operations in station.yaml missing from the client")
    XCTAssertEqual(
      client.subtracting(documented), [], "client operations not in station.yaml")
    XCTAssertEqual(document.operations.count, StationOperation.allCases.count)
    XCTAssertEqual(StationOperation.allCases.count, 13)
  }

  func testSecurityAndSuccessStatusesMatchDocument() throws {
    let document = try loadDocument()
    for documented in document.operations {
      guard let operation = StationOperation(rawValue: documented.operationId) else {
        XCTFail("\(documented.operationId) is not a StationOperation")
        continue
      }
      XCTAssertEqual(
        operation.requiresAuthorization, !documented.isPublic,
        "\(documented.operationId): security differs from station.yaml")
      XCTAssertEqual(
        operation.successStatuses, documented.successStatuses,
        "\(documented.operationId): success statuses differ from station.yaml")
    }
  }

  /// Calls every public client method; each request must match exactly one document operation
  /// and together they must cover all of them.
  func testClientSendsOnlyDocumentedOperationsAndCoversThemAll() async throws {
    let document = try loadDocument()
    let verdict = try Fixtures.verdict()
    let operations = document.operations
    let unmatched = LockedList()
    let matched = LockedList()

    let transport = StubTransport { request, _ in
      guard let operation = Self.match(request, in: operations) else {
        unmatched.append("\(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        return .respond(.problem(404, code: "not_in_document"))
      }
      matched.append(operation.operationId)
      let body: String
      switch operation.operationId {
      case "getHealth": body = Fixtures.health
      case "listProjects": body = Fixtures.projects
      case "getProject": body = Fixtures.project
      case "createUploadSession": body = Fixtures.uploadSession
      case "listPackages": body = Fixtures.packageSummaries
      case "getPackage", "sealPackage": body = Fixtures.package
      case "completeFile": body = Fixtures.fileCheckVerified
      case "getFileDownloadLink": body = Fixtures.downloadLink
      case "getVerdict": body = verdict
      case "listModelingDecisions": body = Fixtures.decisions
      case "createModelingDecision": body = Fixtures.decision
      case "putNextRevisionNotice": body = Fixtures.nextRevisionNotice
      default: return .respond(.problem(500, code: "no_fixture"))
      }
      return .respond(.json(operation.successStatuses.min() ?? 200, body))
    }
    let client = try makeClient(transport: transport)
    let packageId = Fixtures.packageId

    _ = try await client.getHealth()
    _ = try await client.listProjects(query: "7th Ave", limit: 10)
    _ = try await client.getProject(dealId: "4821")
    _ = try await client.createUploadSession(
      UploadSessionRequest(
        packageId: .init(packageId), visitId: .init(Fixtures.visitId), dealId: "4821",
        revision: 1,
        files: [
          UploadFileDeclaration(
            path: "Field Measurements/field-controls.json", role: .fieldControls,
            sha256: Fixtures.sha, bytes: 512)
        ]))
    _ = try await client.listPackages(dealId: "4821", visitId: Fixtures.visitId)
    _ = try await client.getPackage(packageId: packageId)
    _ = try await client.completeFile(
      packageId: packageId, path: "Field Measurements/field-controls.json")
    _ = try await client.getFileDownloadLink(
      packageId: packageId, path: "Field Measurements/field-controls.json")
    _ = try await client.sealPackage(
      packageId: packageId, manifestJSON: try Fixtures.manifestBytes())
    _ = try await client.getVerdict(packageId: packageId)
    _ = try await client.listModelingDecisions(packageId: packageId)
    _ = try await client.createModelingDecision(
      packageId: packageId,
      ModelingDecisionInput(
        element: "Floor 1 kitchen north wall", decision: "Wall length from tape distance A",
        sources: [DecisionSource(path: "Field Measurements/field-controls.json")]))
    _ = try await client.putNextRevisionNotice(
      packageId: packageId, Fixtures.nextRevisionNoticeInput)

    XCTAssertEqual(unmatched.items, [], "client sent requests that are not in station.yaml")
    XCTAssertEqual(
      Set(matched.items), Set(operations.map(\.operationId)),
      "client methods do not cover every operation in station.yaml")
    XCTAssertEqual(matched.items.count, operations.count, "an operation was called more than once")
  }

  /// The document operation whose method and path template match the request.
  static func match(_ request: URLRequest, in operations: [DocumentOperation])
    -> DocumentOperation?
  {
    guard let url = request.url, let method = request.httpMethod else { return nil }
    let prefix = StationOperation.serverBasePath
    guard url.path.hasPrefix(prefix + "/") else { return nil }
    let segments = url.path.dropFirst(prefix.count).split(
      separator: "/", omittingEmptySubsequences: false
    ).dropFirst()
    let candidates = operations.filter { operation in
      guard operation.method == method else { return false }
      let template = operation.path.split(separator: "/", omittingEmptySubsequences: false)
        .dropFirst()
      guard template.count == segments.count else { return false }
      return zip(template, segments).allSatisfy { expected, actual in
        expected.hasPrefix("{") && expected.hasSuffix("}") ? !actual.isEmpty : expected == actual
      }
    }
    return candidates.count == 1 ? candidates[0] : nil
  }
}

final class LockedList: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [String] = []

  func append(_ item: String) {
    lock.withLock { storage.append(item) }
  }

  var items: [String] {
    lock.withLock { storage }
  }
}
