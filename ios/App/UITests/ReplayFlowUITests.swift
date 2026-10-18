import XCTest

/// Replays the bundled box-room capture through every screen of the frozen design:
/// capture record -> scan (replay) -> photos -> controls -> checklist -> package ready ->
/// uploading -> station status "Checks queued". Uses the Debug-only stub station.
final class ReplayFlowUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-ChapterUITestReplay", "box-room"]
    app.launch()
  }

  private func tap(_ element: XCUIElement, timeout: TimeInterval = 15) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)")
    element.tap()
  }

  private func type(_ text: String, into field: XCUIElement) {
    tap(field)
    field.typeText(text)
  }

  private func button(_ label: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
  }

  func testReplayCaptureReachesChecksQueued() {
    // 1 New capture: HUB project and address.
    XCTAssertTrue(app.staticTexts["New capture"].waitForExistence(timeout: 20))
    tap(app.buttons["HUB project"])
    tap(button("UI test visit"))
    tap(button("I am at this address"))
    tap(app.buttons["Continue"])

    // 2 What are you scanning?
    XCTAssertTrue(app.staticTexts["What are you scanning?"].waitForExistence(timeout: 10))
    type("Floor 1", into: app.textFields["Floor 1"])
    tap(app.buttons["Whole floor"])
    tap(button("+ Add room"))
    type("Closet", into: app.textFields["Room name"])
    type("locked", into: app.textFields["Reason (optional)"])
    tap(app.alerts.buttons["Add"])
    tap(app.buttons["Start scan"])

    // 3 Live scan (replay).
    tap(button("Finish floor"), timeout: 20)

    // Photos: the fixture photo, labeled.
    tap(app.buttons["Take photo"], timeout: 20)
    tap(button("Room 1"))
    tap(app.buttons["N"])
    tap(button("General"))
    tap(button("Save and take next"))
    tap(app.buttons["Done"])

    // Field controls: long distance A and B, one ceiling height (tape, ft-in).
    XCTAssertTrue(app.staticTexts["Field controls"].waitForExistence(timeout: 10))
    tap(button("Long distance A"))
    type("Entry wall", into: app.textFields["From (for example Kitchen east wall)"])
    type("Back wall", into: app.textFields["To (for example Living west wall)"])
    type("12 4", into: app.textFields["Value"])
    tap(button("Save measurement"))
    tap(button("Long distance B"))
    type("Left wall", into: app.textFields["From (for example Kitchen east wall)"])
    type("Right wall", into: app.textFields["To (for example Living west wall)"])
    type("10 2", into: app.textFields["Value"])
    tap(button("Save measurement"))
    tap(button("Ceiling heights"))
    type("Room 1", into: app.textFields["Room"])
    type("8 1", into: app.textFields["Value"])
    tap(button("Save measurement"))
    tap(app.buttons["controls.continue"])

    // Before you leave: every row passes.
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 10))
    tap(button("Finish capture"))

    // Package ready, then seal and upload.
    XCTAssertTrue(app.staticTexts["Package ready"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["Source Register"].waitForExistence(timeout: 30))
    tap(button("Seal and upload"))

    // Uploading and station status.
    XCTAssertTrue(app.staticTexts["Uploading"].waitForExistence(timeout: 30))
    let queued = app.descendants(matching: .any)["station.Checks queued"]
    let deadline = Date().addingTimeInterval(60)
    while Date() < deadline, (queued.label as String?) != "Checks queued, done" {
      Thread.sleep(forTimeInterval: 0.5)
    }
    XCTAssertEqual(queued.label, "Checks queued, done")
    XCTAssertEqual(
      app.descendants(matching: .any)["station.Registered"].label, "Registered, done")
    XCTAssertEqual(
      app.descendants(matching: .any)["station.Published to the HUB"].label,
      "Published to the HUB, not yet")
  }
}
