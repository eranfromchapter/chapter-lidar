import AppCore
import Foundation
import MSAL
import StationClient
import UIKit

/// The signed-in operator, as the capture record needs it. Never holds a token.
struct SignedInOperator: Equatable, Sendable {
  /// Display name (the `name` claim, else the username).
  var name: String
  /// Entra object id of the user.
  var userId: String?
}

/// Microsoft Entra sign-in with MSAL.
///
/// - Tokens live only in MSAL's Keychain cache (default access group `com.microsoft.adalcache`,
///   the app's `keychain-access-groups` entitlement). Nothing here writes a token anywhere else,
///   and nothing logs one.
/// - `token(forceRefresh:)` is silent only; when MSAL needs the user (no account, expired
///   refresh token, consent), it throws `SignInRequired` and the app shows the sign-in screen.
/// - `signOut()` removes every MSAL account of this app.
@MainActor
final class EntraSignIn {
  private let application: MSALPublicClientApplication
  private let scopes: [String]

  init(configuration: AppConfiguration) throws {
    let authority = try MSALAADAuthority(url: configuration.authorityURL)
    // redirectUri nil: MSAL uses msauth.<bundle id>://auth (registered in Info.plist).
    let config = MSALPublicClientApplicationConfig(
      clientId: configuration.entraClientId, redirectUri: nil, authority: authority)
    application = try MSALPublicClientApplication(configuration: config)
    scopes = [configuration.stationScope]
  }

  /// MSAL's answer to the browser redirect.
  static func handle(_ url: URL) -> Bool {
    MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: nil)
  }

  /// The operator of the cached account, if there is one (no network).
  func currentOperator() -> SignedInOperator? {
    guard let account = (try? application.allAccounts())?.first else { return nil }
    return Self.operatorOf(account)
  }

  /// Interactive sign-in, presented over the app's key window.
  func signIn() async throws -> SignedInOperator {
    guard let presenter = Self.presentingViewController() else { throw SignInRequired() }
    let webview = MSALWebviewParameters(authPresentationViewController: presenter)
    let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webview)
    let outcome = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<TokenOutcome, Error>) in
      application.acquireToken(with: parameters) { result, error in
        continuation.resume(with: Self.outcome(result, error))
      }
    }
    return outcome.signedInOperator
  }

  /// A station access token from MSAL's cache, refreshed silently when needed.
  func token(forceRefresh: Bool) async throws -> String {
    guard let account = (try? application.allAccounts())?.first else { throw SignInRequired() }
    let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
    parameters.forceRefresh = forceRefresh
    let outcome = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<TokenOutcome, Error>) in
      application.acquireTokenSilent(with: parameters) { result, error in
        continuation.resume(with: Self.outcome(result, error))
      }
    }
    return outcome.accessToken
  }

  /// Removes every account (and so its tokens) from MSAL's Keychain cache.
  func signOut() {
    for account in (try? application.allAccounts()) ?? [] {
      try? application.remove(account)
    }
  }

  // MARK: Private

  /// What is kept from an MSAL result: plain values, so nothing non-Sendable leaves the callback.
  private struct TokenOutcome: Sendable {
    var accessToken: String
    var signedInOperator: SignedInOperator
  }

  private static func outcome(_ result: MSALResult?, _ error: Error?) -> Result<TokenOutcome, Error>
  {
    if let error {
      let nsError = error as NSError
      if nsError.domain == MSALErrorDomain
        && nsError.code == MSALError.interactionRequired.rawValue
      {
        return .failure(SignInRequired())
      }
      if nsError.domain == MSALErrorDomain && nsError.code == MSALError.userCanceled.rawValue {
        return .failure(SignInRequired())
      }
      // MSAL errors can carry account details; keep only the domain and code.
      return .failure(EntraSignInError(domain: nsError.domain, code: nsError.code))
    }
    guard let result else { return .failure(SignInRequired()) }
    return .success(
      TokenOutcome(accessToken: result.accessToken, signedInOperator: operatorOf(result.account)))
  }

  private static func operatorOf(_ account: MSALAccount) -> SignedInOperator {
    let name = (account.accountClaims?["name"] as? String) ?? account.username ?? ""
    return SignedInOperator(name: name, userId: account.homeAccountId?.objectId)
  }

  private static func presentingViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let root = scenes.first { $0.activationState == .foregroundActive }?.keyWindow?.rootViewController
      ?? scenes.first?.keyWindow?.rootViewController
    var top = root
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// A sign-in failure other than "the user must sign in". Carries only the error domain and code.
struct EntraSignInError: Error, CustomStringConvertible {
  var domain: String
  var code: Int
  var description: String { "Sign-in failed (\(domain) \(code))." }
}

/// StationClient's token seam over MSAL. Every token comes from MSAL's Keychain cache.
struct EntraTokenProvider: AccessTokenProvider {
  let signIn: EntraSignIn

  func accessToken(forceRefresh: Bool) async throws -> String {
    try await signIn.token(forceRefresh: forceRefresh)
  }
}
