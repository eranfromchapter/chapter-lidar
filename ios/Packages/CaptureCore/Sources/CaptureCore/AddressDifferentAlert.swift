import Foundation

/// The system alert of New capture when "I am at this address" is turned off (phone-capture
/// §3.2.2, artboard 2b-1c). Pure, so its words, the order of its buttons and what each does are
/// tested on Linux; `NewCaptureScreen` only draws them (`CaptureFlowModel.addressAlert(_:dial:
/// discard:)` runs a button).
public enum AddressDifferentAlert {
  public static let title = "Address is different on site?"
  public static let message =
    "Do not scan under this project. Call the PM to fix the HUB record, then start the capture "
    + "again. Nothing is saved."

  /// A button of the alert.
  public enum Action: Hashable, Sendable, CaseIterable {
    /// Closes the alert: New capture stays, with the switch off and the project kept, so the
    /// operator can pick another project.
    case goBack
    /// Dials the PM when the HUB project has a phone number, then discards the draft and goes
    /// back to the Captures home. Nothing was saved.
    case callProjectManager

    public var title: String {
      switch self {
      case .goBack: return "Go back"
      case .callProjectManager: return "Call the PM"
      }
    }

    /// Go back has the cancel role.
    public var isCancel: Bool { self == .goBack }

    /// Call the PM is the default button (bold).
    public var isDefault: Bool { self == .callProjectManager }
  }

  /// The buttons in the order the alert shows them.
  public static let actions: [Action] = [.goBack, .callProjectManager]
}
