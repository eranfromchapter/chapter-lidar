import Foundation
import StationClient

/// Info.plist keys the app reads its configuration from. The values come from build settings in
/// `ios/App/Config/*.xcconfig` (committed with placeholders, no secrets).
public enum ConfigurationKey: String, CaseIterable, Sendable {
  /// Microsoft Entra application (client) id of the Chapter Capture app registration.
  case entraClientId = "ChapterEntraClientID"
  /// Microsoft Entra directory (tenant) id.
  case entraTenantId = "ChapterEntraTenantID"
  /// The station API scope the app asks a token for, for example `api://<station app id>/Capture.Upload`.
  case stationScope = "ChapterStationAPIScope"
  /// The station host, for example `https://station.example.com` (the client appends `/v1`).
  case stationURL = "ChapterStationURL"

  /// Name shown on the "App is not configured" screen.
  public var title: String {
    switch self {
    case .entraClientId: return "Entra client id"
    case .entraTenantId: return "Entra tenant id"
    case .stationScope: return "Station API scope"
    case .stationURL: return "Station URL"
    }
  }
}

/// Why the configuration cannot be used. Never carries more than the key and a short reason.
public enum ConfigurationIssue: Hashable, Sendable, CustomStringConvertible {
  case missing(ConfigurationKey)
  case placeholder(ConfigurationKey)
  case invalid(ConfigurationKey, String)

  public var key: ConfigurationKey {
    switch self {
    case .missing(let key), .placeholder(let key), .invalid(let key, _): return key
    }
  }

  public var description: String {
    switch self {
    case .missing(let key): return "\(key.title) is missing (\(key.rawValue))."
    case .placeholder(let key): return "\(key.title) is still a placeholder (\(key.rawValue))."
    case .invalid(let key, let reason): return "\(key.title) is not valid: \(reason)"
    }
  }
}

/// The validated configuration: everything sign-in and the station client need.
public struct AppConfiguration: Equatable, Sendable {
  public let entraClientId: String
  public let entraTenantId: String
  public let stationScope: String
  public let station: StationClientConfiguration

  /// `https://login.microsoftonline.com/<tenant id>`.
  public var authorityURL: URL {
    // The tenant id is checked to be a UUID or a domain name, so this URL always forms.
    URL(string: "https://login.microsoftonline.com/\(entraTenantId)")!
  }

  public var stationURL: URL { station.stationURL }
}

/// Result of reading the configuration. A placeholder or missing value never falls back to a
/// default: the app shows "App is not configured" and sends nothing anywhere.
public enum ConfigurationState: Equatable, Sendable {
  case configured(AppConfiguration)
  case notConfigured([ConfigurationIssue])

  public var configuration: AppConfiguration? {
    if case .configured(let configuration) = self { return configuration }
    return nil
  }
}

public enum ConfigurationLoader {
  /// Reads and validates the four keys from an Info.plist dictionary (`Bundle.main.infoDictionary`).
  public static func load(infoDictionary: [String: Any]?) -> ConfigurationState {
    let dictionary = infoDictionary ?? [:]
    return load { dictionary[$0.rawValue] as? String }
  }

  /// Validates the values returned by `value` for each key.
  public static func load(_ value: (ConfigurationKey) -> String?) -> ConfigurationState {
    var issues: [ConfigurationIssue] = []

    func read(_ key: ConfigurationKey) -> String? {
      guard let raw = value(key) else {
        issues.append(.missing(key))
        return nil
      }
      let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty {
        issues.append(.missing(key))
        return nil
      }
      if isPlaceholder(text) {
        issues.append(.placeholder(key))
        return nil
      }
      return text
    }

    let clientId = read(.entraClientId)
    if let clientId, UUID(uuidString: clientId) == nil {
      issues.append(.invalid(.entraClientId, "must be the application (client) id, a UUID."))
    }

    let tenantId = read(.entraTenantId)
    if let tenantId, !isTenant(tenantId) {
      issues.append(.invalid(.entraTenantId, "must be the directory (tenant) id, a UUID."))
    }

    let scope = read(.stationScope)
    if let scope, !isScope(scope) {
      issues.append(
        .invalid(.stationScope, "must be the full scope, for example api://<app id>/<scope name>."))
    }

    var station: StationClientConfiguration?
    if let text = read(.stationURL) {
      if let url = URL(string: text) {
        do {
          station = try StationClientConfiguration(stationURL: url)
        } catch {
          issues.append(.invalid(.stationURL, "must be an https URL with a host and no query."))
        }
      } else {
        issues.append(.invalid(.stationURL, "is not a URL."))
      }
    }

    guard issues.isEmpty, let clientId, let tenantId, let scope, let station else {
      return .notConfigured(issues)
    }
    return .configured(
      AppConfiguration(
        entraClientId: clientId.lowercased(), entraTenantId: tenantId.lowercased(),
        stationScope: scope, station: station))
  }

  /// Values committed in the xcconfig look like `__SET_ENTRA_CLIENT_ID__`. An unexpanded build
  /// setting (`$(NAME)`) or an obvious example value also counts as a placeholder.
  public static func isPlaceholder(_ text: String) -> Bool {
    let upper = text.uppercased()
    return text.contains("__") || text.contains("$(") || text.contains("${")
      || upper.contains("PLACEHOLDER") || upper.contains("REPLACE_ME")
      || upper.contains("EXAMPLE.COM") || upper.contains("EXAMPLE.ORG")
      || UUID(uuidString: text) == UUID(uuidString: "00000000-0000-0000-0000-000000000000")
  }

  /// A tenant id is a UUID. (Domain-name tenants are deliberately not accepted, so the authority
  /// is always the exact directory the app is registered in.)
  static func isTenant(_ text: String) -> Bool {
    UUID(uuidString: text) != nil
  }

  /// `api://...` or `https://...` with a path, no whitespace.
  static func isScope(_ text: String) -> Bool {
    guard !text.contains(where: { $0.isWhitespace }) else { return false }
    for prefix in ["api://", "https://"] where text.lowercased().hasPrefix(prefix) {
      let rest = text.dropFirst(prefix.count)
      guard let slash = rest.firstIndex(of: "/") else { return false }
      return slash != rest.startIndex && rest.index(after: slash) != rest.endIndex
    }
    return false
  }
}
