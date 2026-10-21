import CaptureCore
import XCTest

/// The alert of artboard 2b-1c (phone-capture §3.2.2): the package snapshots cannot draw a system
/// alert, so its words and buttons are checked here. What each button does is in
/// `CaptureFlowModelV2Tests` (`testAddressAlertActions`).
final class AddressDifferentAlertTests: XCTestCase {
  func testWords() {
    XCTAssertEqual(AddressDifferentAlert.title, "Address is different on site?")
    XCTAssertEqual(
      AddressDifferentAlert.message,
      "Do not scan under this project. Call the PM to fix the HUB record, then start the capture "
        + "again. Nothing is saved.")
  }

  func testButtonsInOrder() {
    XCTAssertEqual(AddressDifferentAlert.actions, [.goBack, .callProjectManager])
    XCTAssertEqual(AddressDifferentAlert.actions.map(\.title), ["Go back", "Call the PM"])
    XCTAssertEqual(AddressDifferentAlert.actions.map(\.isCancel), [true, false], "Go back cancels")
    XCTAssertEqual(
      AddressDifferentAlert.actions.map(\.isDefault), [false, true], "Call the PM is the bold default")
    XCTAssertEqual(Set(AddressDifferentAlert.actions), Set(AddressDifferentAlert.Action.allCases))
  }
}
