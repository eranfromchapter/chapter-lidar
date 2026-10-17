import Foundation

#if canImport(Security)
  import Security
#endif

/// Supplies the Microsoft Entra ID access token for the station API.
///
/// The app shell implements this with MSAL (silent token acquisition, interactive sign-in when
/// needed). The station client asks for a token before every authorized request and, when the
/// station answers 401, asks once more with `forceRefresh: true` before giving up with
/// `StationError.unauthorized`.
///
/// Implementations must never log, print or persist a token outside the Keychain.
public protocol AccessTokenProvider: Sendable {
  /// A bearer token for the station API. `forceRefresh` asks for a new token even when a cached
  /// one looks valid (the station rejected the cached one). Throws when no token can be
  /// obtained, for example when interactive sign-in is required.
  func accessToken(forceRefresh: Bool) async throws -> String
}

/// Secret storage for sign-in material (tokens, MSAL account data). The Apple implementation is
/// `KeychainTokenStore`; there is deliberately no file, UserDefaults or in-memory-on-disk
/// implementation in this package.
public protocol SecureTokenStore: Sendable {
  /// The stored secret for `account`, or nil when there is none.
  func read(account: String) throws -> Data?
  /// Stores `secret` for `account`, replacing any existing value.
  func write(_ secret: Data, account: String) throws
  /// Removes the secret for `account`. Removing a missing secret is not an error.
  func delete(account: String) throws
}

/// A Keychain call failed. Carries only the OSStatus, never the secret.
public struct SecureTokenStoreError: Error, Sendable, Equatable, CustomStringConvertible {
  public let operation: String
  public let status: Int32

  public init(operation: String, status: Int32) {
    self.operation = operation
    self.status = status
  }

  public var description: String {
    "Keychain \(operation) failed with OSStatus \(status)"
  }
}

#if canImport(Security)
  /// `SecureTokenStore` backed by the iOS/macOS Keychain (generic password items).
  ///
  /// Items are `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable by background
  /// uploads after the first unlock, never synced to iCloud Keychain and never restored onto
  /// another device from a backup.
  public struct KeychainTokenStore: SecureTokenStore {
    /// Keychain service name, for example the app's bundle id plus `.station`.
    public let service: String
    /// Optional Keychain access group shared with app extensions.
    public let accessGroup: String?

    public init(service: String, accessGroup: String? = nil) {
      self.service = service
      self.accessGroup = accessGroup
    }

    private func baseQuery(account: String) -> [String: Any] {
      var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrSynchronizable as String: false,
      ]
      if let accessGroup {
        query[kSecAttrAccessGroup as String] = accessGroup
      }
      return query
    }

    public func read(account: String) throws -> Data? {
      var query = baseQuery(account: account)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      switch status {
      case errSecSuccess:
        guard let data = result as? Data else {
          throw SecureTokenStoreError(operation: "read", status: errSecInternalError)
        }
        return data
      case errSecItemNotFound:
        return nil
      default:
        throw SecureTokenStoreError(operation: "read", status: status)
      }
    }

    public func write(_ secret: Data, account: String) throws {
      let query = baseQuery(account: account)
      let attributes: [String: Any] = [
        kSecValueData as String: secret,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ]
      let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
      switch updateStatus {
      case errSecSuccess:
        return
      case errSecItemNotFound:
        var item = query
        for (key, value) in attributes {
          item[key] = value
        }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
          throw SecureTokenStoreError(operation: "add", status: addStatus)
        }
      default:
        throw SecureTokenStoreError(operation: "update", status: updateStatus)
      }
    }

    public func delete(account: String) throws {
      let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw SecureTokenStoreError(operation: "delete", status: status)
      }
    }
  }
#endif
