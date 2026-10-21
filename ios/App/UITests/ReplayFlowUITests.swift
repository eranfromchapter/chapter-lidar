import XCTest

/// Replays the bundled box-room capture through every screen of the frozen design:
/// capture record -> scan (replay) -> photos -> controls -> checklist -> package ready (and the
/// scan's Floorplan) -> uploading -> station status "Checks queued". Uses the Debug-only stub
/// station. On the way the room is renamed twice, from the viewfinder ("Rooms") and from the
/// checklist ("Rename rooms"), and the photo (and the ceiling height measured in it) follows the
/// name.
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

  /// Keeps a screenshot in the result bundle, to look at the screen after the run.
  private func attachScreenshot(_ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }

  private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 30) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !(element.exists && element.label == label) {
      Thread.sleep(forTimeInterval: 0.25)
    }
    XCTAssertEqual(element.label, label)
  }

  func testReplayCaptureReachesChecksQueued() {
    // 1 New capture: HUB project and address.
    XCTAssertTrue(app.staticTexts["New capture"].waitForExistence(timeout: 20))
    // Who is signed in, with the sign-out link (not tapped: the replay mode has no MSAL).
    XCTAssertTrue(app.buttons["account.signOut"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH %@", "Signed in as UI Test Operator")
      ).firstMatch.exists)
    tap(app.buttons["HUB project"])
    tap(button("UI test visit"))
    tap(button("I am at this address"))
    tap(app.buttons["Continue"])

    // 2 What are you scanning? No skipped room is entered: the box room has none, and the
    // checklist's "No rooms skipped" confirms that below. The sign-out link is gone from here on.
    XCTAssertTrue(app.staticTexts["What are you scanning?"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["account.signOut"].exists)
    type("Floor 1", into: app.textFields["Floor 1"])
    tap(app.buttons["Whole floor"])
    tap(app.buttons["Start scan"])

    // 3 Live scan (replay).
    tap(button("Finish floor"), timeout: 20)

    // Photos. The box room is "Room 1": its RoomPlan section is unidentified and a table alone
    // does not tell the room type. The viewfinder says which rooms still need a photo (the
    // checklist's rule).
    let coverage = app.descendants(matching: .any)["photo.coverage"]
    waitForLabel(coverage, "Still needs a photo: Room 1")
    attachScreenshot("1 Viewfinder")

    // Rename it from the viewfinder ("Rooms"), with a quick name: the scan cannot tell a shower
    // (field report 2026-10-20).
    tap(app.buttons["photo.rooms"])
    let nameField = app.textFields["rooms.name.room-1"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 10))
    XCTAssertEqual(nameField.value as? String, "Room 1")
    // The sheet says which room still needs a photo.
    let noPhotoYet = app.descendants(matching: .any)["rooms.needsPhoto.room-1"]
    XCTAssertTrue(noPhotoYet.exists)
    XCTAssertEqual(noPhotoYet.label, "No photo yet")
    attachScreenshot("2 Rename rooms")
    tap(app.buttons["rooms.suggest.room-1.Shower"])
    XCTAssertEqual(nameField.value as? String, "Shower")
    Thread.sleep(forTimeInterval: 0.5)  // let the chip's tap highlight fade for the screenshot
    attachScreenshot("3 Rename rooms, Shower chosen")
    tap(app.buttons["rooms.save"])
    waitForLabel(coverage, "Still needs a photo: Shower")
    attachScreenshot("4 Viewfinder after rename")
    // No photo yet: "Before you leave" will ask for one.
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
    // Measured in the room by its name now; a later rename moves the control with it.
    type("Shower", into: app.textFields["Room"])
    type("8 1", into: app.textFields["Value"])
    tap(button("Save measurement"))
    tap(app.buttons["controls.continue"])

    // Before you leave: "Skipped rooms recorded" is open until "No rooms skipped", and the
    // renamed room has no photo yet.
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 10))
    tap(button("No rooms skipped"))
    XCTAssertTrue(app.staticTexts["Shower has no photo"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["checklist.renameRooms"].exists)
    attachScreenshot("5 Checklist, Shower has no photo")

    // "Take photo" opens the camera for that room: the title says which.
    tap(app.buttons["Take photo"])
    waitForLabel(app.staticTexts["photo.title"], "Shower \u{00B7} Photo 1 of Floor 1")
    waitForLabel(coverage, "Still needs a photo: Shower")
    attachScreenshot("6 Viewfinder for Shower")

    // The fixture photo: the labeling screen keeps the room in its title, and the Room chip is
    // Shower, chosen and marked as still needing a photo.
    tap(app.buttons["Take photo"], timeout: 20)
    waitForLabel(app.staticTexts["photo.labelTitle"], "Shower \u{00B7} Photo 1 of Floor 1")
    let shower = button("Shower")
    XCTAssertTrue(shower.waitForExistence(timeout: 10))
    XCTAssertEqual(shower.value as? String, "needs photo")
    XCTAssertTrue(shower.isSelected)
    XCTAssertFalse(button("Room 1").exists, "the old name is gone from the chips")
    XCTAssertTrue(app.buttons["photo.renameRooms"].exists)
    attachScreenshot("7 Labeling with renamed chips")
    tap(app.buttons["N"])
    tap(button("General"))
    tap(button("Save and take next"))
    waitForLabel(coverage, "Every room has a photo")
    tap(app.buttons["Done"])

    // Back on the checklist, which passes.
    XCTAssertTrue(app.staticTexts["1 photo, 1 room covered"].waitForExistence(timeout: 10))
    attachScreenshot("8 Checklist after rename")

    // Rename again from the checklist row: the photo labeled Shower follows the new name, so
    // the row still passes.
    tap(app.buttons["checklist.renameRooms"])
    XCTAssertTrue(nameField.waitForExistence(timeout: 10))
    XCTAssertEqual(nameField.value as? String, "Shower")
    XCTAssertFalse(noPhotoYet.exists, "the room has its photo now")
    nameField.tap()
    nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Walk-in shower")
    XCTAssertEqual(nameField.value as? String, "Walk-in shower")
    attachScreenshot("9 Rename rooms from the checklist")
    tap(app.buttons["rooms.save"])
    XCTAssertTrue(app.staticTexts["1 photo, 1 room covered"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Walk-in shower has no photo"].exists)
    attachScreenshot("10 Checklist after renaming again")
    tap(button("Finish capture"))

    // Package ready, then seal and upload.
    XCTAssertTrue(app.staticTexts["Package ready"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["Source Register"].waitForExistence(timeout: 30))

    // Review the scan first: the Floorplan, its units and Download (PDF and PNG).
    tap(button("Floor 1"))
    let page = app.descendants(matching: .any)["floorplan.page"]
    XCTAssertTrue(page.waitForExistence(timeout: 30), "floor plan page")
    let download = app.descendants(matching: .any)["floorplan.download"]
    waitForLabel(download, "Download floor plan, PDF and PNG")
    attachScreenshot("Floorplan")
    let units = app.buttons["floorplan.units"]
    XCTAssertTrue(units.waitForExistence(timeout: 10))
    XCTAssertEqual(units.label, "Units, feet and inches")
    units.tap()
    tap(app.buttons["Metric (m)"])
    waitForLabel(units, "Units, metres")
    waitForLabel(download, "Download floor plan, PDF and PNG")
    attachScreenshot("Floorplan, metric")
    XCTAssertTrue(page.exists)
    XCTAssertTrue(app.buttons["scan.view3D"].exists)
    tap(app.buttons["Done"])
    XCTAssertTrue(app.staticTexts["Package ready"].waitForExistence(timeout: 10))

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
