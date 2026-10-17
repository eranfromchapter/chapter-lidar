import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Every failure the station client reports. No case ever carries a token, an Authorization
/// header or a SAS URL.
public enum StationError: Error, Sendable, Equatable {
  /// 401 after one forced token refresh: the caller must sign in again.
  case unauthorized(Problem?)
  /// 403: the signed-in user has none of the roles the operation accepts.
  case forbidden(Problem?)
  /// 404: the project, package, file or verdict does not exist (yet).
  case notFound(Problem?)
  /// 409: the request conflicts with the package's state.
  case conflict(Problem?)
  /// 400 or 422: the request is malformed or breaks a contract rule.
  case validation(status: Int, problem: Problem?)
  /// 5xx, for example 502 hub_unavailable or 503 storage_unavailable.
  case server(status: Int, problem: Problem?)
  /// Any other status the document does not list for the operation (including redirects,
  /// which the client never follows).
  case unexpectedStatus(Int)
  /// The device could not reach the station (no connection, host unreachable, timed out).
  case offline
  /// Another transport failure (for example TLS). `code` is the URLError code.
  case network(code: Int)
  /// A success response whose body does not match the document.
  case invalidResponse(String)
  /// The call was refused before sending: an argument cannot form a valid request.
  case invalidRequest(String)

  /// The problem details of an HTTP error, when the station sent them.
  public var problem: Problem? {
    switch self {
    case .unauthorized(let problem), .forbidden(let problem), .notFound(let problem),
      .conflict(let problem):
      return problem
    case .validation(_, let problem), .server(_, let problem):
      return problem
    default:
      return nil
    }
  }

  /// True when the caller must run interactive sign-in again.
  public var requiresSignIn: Bool {
    if case .unauthorized = self { return true }
    return false
  }

  /// Maps an HTTP error status (and the decoded problem, if any) to a typed error.
  static func from(status: Int, problem: Problem?) -> StationError {
    switch status {
    case 400, 422: return .validation(status: status, problem: problem)
    case 401: return .unauthorized(problem)
    case 403: return .forbidden(problem)
    case 404: return .notFound(problem)
    case 409: return .conflict(problem)
    case 500...599: return .server(status: status, problem: problem)
    default: return .unexpectedStatus(status)
    }
  }

  /// URLError codes that mean the station could not be reached from this device.
  static let offlineCodes: Set<URLError.Code> = [
    .notConnectedToInternet,
    .networkConnectionLost,
    .timedOut,
    .cannotFindHost,
    .cannotConnectToHost,
    .dnsLookupFailed,
    .internationalRoamingOff,
    .callIsActive,
    .dataNotAllowed,
  ]

  /// Maps a transport error. URLErrors become `.offline` or `.network`; a cancelled request
  /// becomes CancellationError; any other error is passed through unchanged, never hidden.
  static func fromTransport(_ error: Error) -> Error {
    guard let urlError = error as? URLError else {
      return error
    }
    if urlError.code == .cancelled {
      return CancellationError()
    }
    return offlineCodes.contains(urlError.code)
      ? StationError.offline : StationError.network(code: urlError.code.rawValue)
  }
}
