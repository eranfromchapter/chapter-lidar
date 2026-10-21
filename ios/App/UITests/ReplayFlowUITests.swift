import XCTest

/// The phone's screens end to end in the Debug replay mode (bundled box-room capture, fixture
/// photo, in-process station and token, scripted compass): phone-capture §10.3 (U1–U10),
/// phone-field §15.3, phone-package §13.3 and compass §13.4. Every screen is attached as a
/// screenshot (kept in the result bundle) for the review against artboards 2b, 2d and 2f.
/// Main-actor isolated, as XCUIAutomation is; XCTest runs each test on the main thread.
@MainActor
final class ReplayFlowUITests: XCTestCase {
  private lazy var app = XCUIApplication()

  nonisolated override func setUp() {
    continueAfterFailure = false
  }

  // MARK: Helpers

  /// Launches the replay mode with the compass script and any other UI-test arguments.
  private func launch(compass: String = "verified", _ extra: [String] = []) {
    app.launchArguments =
      ["-ChapterUITestReplay", "box-room", "-ChapterUITestCompass", compass] + extra
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

  /// The element with this accessibility identifier, of any type.
  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// Any element whose label contains `text`.
  private func anyText(containing text: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text))
      .firstMatch
  }

  private func texts(containing text: String) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text))
  }

  /// Keeps a screenshot in the result bundle, to look at the screen after the run.
  private func shot(_ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }

  private func waitForLabel(
    _ element: XCUIElement, _ label: String, timeout: TimeInterval = 30,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !(element.exists && element.label == label) {
      Thread.sleep(forTimeInterval: 0.25)
    }
    XCTAssertEqual(element.label, label, file: file, line: line)
  }

  private func waitFor(
    _ description: String, timeout: TimeInterval = 30, file: StaticString = #filePath,
    line: UInt = #line, _ condition: () -> Bool
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !condition() {
      Thread.sleep(forTimeInterval: 0.25)
    }
    XCTAssertTrue(condition(), description, file: file, line: line)
  }

  /// Replaces a text field's text. The cursor goes to the end first (a right-aligned field
  /// puts it where the tap lands).
  private func replaceText(in field: XCUIElement, with text: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    // Deleting removes what is before the cursor; a tap may land before the last letter, so
    // tap the right end again until nothing is left.
    // (An empty field reports its placeholder as its value, so the first pass always deletes.)
    for pass in 0..<4 {
      let current = (field.value as? String) ?? ""
      if pass > 0, current.isEmpty || current == field.placeholderValue { break }
      field.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.5)).tap()
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
    }
    field.typeText(text)
    XCTAssertEqual(field.value as? String, text)
  }

  /// Scrolls until `element` is above the screen's bottom action bar (`bar`, its button). At the
  /// accessibility sizes a row can sit under the bar and still count as hittable, so a tap on
  /// it would land on the bar.
  private func scrollAbove(
    _ bar: XCUIElement, _ element: XCUIElement, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(element.waitForExistence(timeout: 10), "missing \(element)", file: file, line: line)
    XCTAssertTrue(bar.waitForExistence(timeout: 10), "missing \(bar)", file: file, line: line)
    var swipes = 0
    while element.frame.maxY > bar.frame.minY, swipes < 6 {
      app.swipeUp()
      swipes += 1
    }
    XCTAssertLessThanOrEqual(element.frame.maxY, bar.frame.minY, file: file, line: line)
  }

  /// The system back chevron of the navigation bar on top.
  private func goBack() {
    let back = app.navigationBars.buttons.element(boundBy: 0)
    tap(back)
  }

  /// "Fonts" registered and every UIKit text of the screen in Inter or Times (phone-capture
  /// §10.4, phone-field §15.3).
  private func assertFonts(_ screen: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(element("debug.fonts").value as? String, "ok", screen, file: file, line: line)
    let audit = element("debug.fontAudit")
    Thread.sleep(forTimeInterval: 1.0)  // the audit runs every 0.7 s
    XCTAssertEqual(audit.value as? String, "ok", "\(screen): \(audit.value ?? "")", file: file, line: line)
  }

  /// Captures home → New capture → step 2, with the HUB project chosen and the address
  /// confirmed.
  private func openStepTwo() {
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    tap(app.buttons["captures.newCapture"])
    XCTAssertTrue(app.staticTexts["New capture"].waitForExistence(timeout: 10))
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    tap(app.switches["capture.addressConfirmed"])
    tap(app.buttons["capture.continue"])
    XCTAssertTrue(app.staticTexts["What are you scanning?"].waitForExistence(timeout: 10))
  }

  /// Step 2 → the live scan (whole floor) → Finish floor: the photo step's viewfinder.
  private func scanFloor(name: String? = nil) {
    if let name {
      replaceText(in: app.textFields["capture.floorName"], with: name)
    }
    tap(app.buttons["capture.mode.floor"])
    tap(app.buttons["capture.startScan"])
    let finish = app.buttons["scan.finish"]
    XCTAssertTrue(finish.waitForExistence(timeout: 20))
    waitFor("Finish floor enabled once a wall is found") { finish.isEnabled }
    finish.tap()
    XCTAssertTrue(element("photo.coverage").waitForExistence(timeout: 30), "the photo step")
  }

  /// The overview after a floor: the photo step's Done.
  private func leavePhotosForTheOverview() {
    tap(app.buttons["photo.done"])
    XCTAssertTrue(app.buttons["overview.review"].waitForExistence(timeout: 15), "the overview")
  }

  /// From the overview: "All rooms scanned" on Before you leave, one labeled photo of the room
  /// that needs one, back on the overview with every blocking item passed.
  private func passTheChecklist() {
    tap(app.buttons["overview.skippedRooms"])
    tap(app.buttons["checklist.allRoomsScanned"])
    tap(app.buttons["checklist.takePhoto"])
    tap(app.buttons["photo.shutter"], timeout: 20)
    tap(app.buttons["photo.direction.N"])
    tap(app.buttons["photo.subject.general"])
    tap(app.buttons["photo.doneWithPhotos"])
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 15))
    goBack()
    XCTAssertTrue(app.buttons["overview.review"].waitForExistence(timeout: 10))
  }

  /// A new capture with one floor whose checklist passes, at Package ready.
  private func reachPackageReady() {
    openStepTwo()
    scanFloor()
    leavePhotosForTheOverview()
    passTheChecklist()
    let review = app.buttons["overview.review"]
    waitForLabel(review, "Review the package")
    review.tap()
    XCTAssertTrue(app.staticTexts["Package ready"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.buttons["package.seal"].waitForExistence(timeout: 60))
    waitFor("the plan is built", timeout: 60) { app.buttons["package.seal"].isEnabled }
  }

  // MARK: U1, phone-field §15.3, phone-package §13.3 (1), compass §13.4 (verified)

  func testCaptureFromTheHomeToChecksQueued() {
    launch()

    // Captures home, empty (phone-capture §3.1.3).
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["No captures on this phone yet."].exists)
    XCTAssertTrue(app.staticTexts["Tap New capture to scan a floor or room."].exists)
    XCTAssertTrue(element("Chapter Renovation").exists || anyText(containing: "Chapter Renovation").exists)
    assertFonts("Captures")
    shot("01 Captures, empty")

    // New capture.
    tap(app.buttons["captures.newCapture"])
    XCTAssertTrue(app.staticTexts["New capture"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 1 of 3"].exists)
    XCTAssertEqual(app.buttons["capture.continue"].label, "Choose a HUB project to continue")
    XCTAssertFalse(app.buttons["capture.continue"].isEnabled)
    shot("02 New capture, no project")
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    tap(app.switches["capture.addressConfirmed"])
    XCTAssertTrue(app.staticTexts["618 Valley Street, Test Town"].exists)
    assertFonts("New capture")
    shot("03 New capture")
    tap(app.buttons["capture.continue"])

    // What are you scanning? The compass pre-check (compass §5.1): reading, then verified.
    XCTAssertTrue(app.staticTexts["What are you scanning?"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 2 of 3"].exists)
    XCTAssertEqual(app.textFields["capture.floorName"].value as? String, "Floor 1")
    let compass = element("compass.row")
    waitForLabel(
      compass,
      "Compass. North 212 degrees true, plus or minus 8 degrees. Verified, read just now.")
    XCTAssertTrue(app.staticTexts["North 212° true · ±8°"].exists || compass.label.contains("212"))
    XCTAssertEqual(compass.textFields.count, 0, "the heading is never typed")
    XCTAssertEqual(app.buttons["capture.startScan"].label, "Choose what you are scanning")
    assertFonts("What are you scanning?")
    shot("04 What are you scanning")
    tap(app.buttons["compass.readAgain"])
    waitForLabel(compass, "Compass. Reading the compass.", timeout: 5)
    shot("04b What are you scanning, reading")
    waitForLabel(
      compass,
      "Compass. North 212 degrees true, plus or minus 8 degrees. Verified, read just now.")
    tap(app.buttons["capture.mode.floor"])
    XCTAssertEqual(app.buttons["capture.startScan"].label, "Start scan")
    tap(app.buttons["capture.startScan"])

    // Live scan: the compass chip (compass §5.2).
    let chip = element("scan.compass")
    XCTAssertTrue(chip.waitForExistence(timeout: 20))
    waitForLabel(chip, "Compass verified, true north, plus or minus 8 degrees", timeout: 20)
    XCTAssertTrue(element("scan.title").label.hasPrefix("Floor 1 · Whole floor"))
    shot("05 Live scan")
    let finish = app.buttons["scan.finish"]
    waitFor("Finish floor enabled") { finish.isEnabled }
    finish.tap()

    // Photos (phone-field §3). The box room is "Room 1"; the viewfinder names what needs a photo.
    let coverage = element("photo.coverage")
    waitForLabel(coverage, "Still needs a photo: Room 1")
    shot("06 Viewfinder")
    // Rename it from the viewfinder ("Rooms").
    tap(app.buttons["photo.rooms"])
    let nameField = app.textFields["rooms.name.room-1"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 10))
    XCTAssertEqual(nameField.value as? String, "Room 1")
    let noPhotoYet = element("rooms.needsPhoto.room-1")
    XCTAssertEqual(noPhotoYet.label, "No photo yet")
    shot("07 Rename rooms")
    tap(app.buttons["rooms.suggest.room-1.Shower"])
    XCTAssertEqual(nameField.value as? String, "Shower")
    tap(app.buttons["rooms.save"])
    waitForLabel(coverage, "Still needs a photo: Shower")
    // Take the photo: Label a photo, the direction pre-filled from the camera heading.
    tap(app.buttons["photo.shutter"], timeout: 20)
    waitForLabel(element("photo.labelTitle"), "Photo 1 \u{00B7} Floor 1")
    XCTAssertTrue(element("photo.format").label.hasPrefix("JPEG"), element("photo.format").label)
    let east = app.buttons["photo.direction.E"]
    XCTAssertTrue(east.waitForExistence(timeout: 10))
    XCTAssertTrue(east.isSelected, "85° from the compass gives E")
    XCTAssertTrue(
      anyText(containing: "from the compass, change if wrong").exists,
      "Looking toward · from the compass, change if wrong")
    // No room yet (the first photo of the floor): choose Shower, which still needs a photo.
    let shower = app.buttons["photo.room.Shower"]
    XCTAssertEqual(shower.value as? String, "needs photo")
    shower.tap()
    XCTAssertTrue(shower.isSelected)
    waitForLabel(
      element("photo.strip"),
      "1 photo in Shower \u{00B7} keep people and personal items out of the frame")
    assertFonts("Label a photo")
    shot("08 Label a photo, E from the compass")
    tap(app.buttons["photo.direction.N"])
    XCTAssertTrue(anyText(containing: "chosen by you").waitForExistence(timeout: 5))
    tap(app.buttons["photo.subject.general"])
    // "Rename rooms" from the room picker ("More").
    tap(app.buttons["photo.moreRooms"])
    XCTAssertTrue(app.buttons["photo.renameRooms"].waitForExistence(timeout: 10))
    shot("09 Room picker")
    app.buttons["Cancel"].firstMatch.tap()
    tap(app.buttons["photo.doneWithPhotos"])

    // Capture overview (phone-capture §3.5): back from the photos.
    let review = app.buttons["overview.review"]
    XCTAssertTrue(review.waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["UI test visit"].exists, "the project title")
    XCTAssertTrue(app.staticTexts["Deal UITEST-0001"].exists)
    XCTAssertTrue(
      app.staticTexts["Captured today by UI Test Operator \u{00B7} not sealed yet"].exists)
    let floor = app.buttons["overview.floor.floor-1"]
    XCTAssertTrue(floor.label.contains("Whole floor \u{00B7} 1 room \u{00B7} 1 photo"), floor.label)
    XCTAssertTrue(floor.label.contains("Done"), floor.label)
    XCTAssertTrue(app.buttons["overview.photos"].label.contains("Every room has a photo"))
    let compassRow = app.buttons["overview.compass"]
    XCTAssertTrue(compassRow.label.contains("Every floor verified"), compassRow.label)
    XCTAssertTrue(compassRow.label.contains("Verified"), compassRow.label)
    let skipped = app.buttons["overview.skippedRooms"]
    XCTAssertTrue(
      skipped.label.contains("Record skipped rooms, or confirm none were skipped"), skipped.label)
    waitForLabel(review, "Fix 1 item to review the package")
    XCTAssertFalse(review.isEnabled)
    assertFonts("Capture overview")
    shot("10 Capture overview")

    // Field controls (phone-field §4): tape checks as two fields, then back to the overview.
    tap(app.buttons["overview.controls"])
    XCTAssertTrue(app.staticTexts["Field controls"].waitForExistence(timeout: 10))
    shot("11 Field controls")
    func saveEntry() {
      tap(app.buttons["Save"])
      XCTAssertTrue(element("entry.sheet").waitForNonExistence(timeout: 10), "sheet stays open")
    }
    tap(app.buttons["controls.row.floor-1.distanceA"])
    type("Entry wall", into: element("entry.from"))
    type("Back wall", into: element("entry.to"))
    type("12", into: element("entry.feet"))
    type("4", into: element("entry.inches"))
    XCTAssertTrue(element("entry.footnote").label.hasPrefix("Stored as 3,759 mm."))
    shot("12 Entry sheet")
    saveEntry()
    tap(app.buttons["controls.row.floor-1.distanceB"])
    type("Left wall", into: element("entry.from"))
    type("Right wall", into: element("entry.to"))
    type("10", into: element("entry.feet"))
    type("2", into: element("entry.inches"))
    saveEntry()
    tap(app.buttons["controls.row.floor-1.ceilingHeight"])
    tap(app.buttons["entry.room.Shower"])
    type("8", into: element("entry.feet"))
    type("1", into: element("entry.inches"))
    saveEntry()
    let rowA = app.buttons["controls.row.floor-1.distanceA"]
    // The row reads "3,759 mm" over "12' 4\""; VoiceOver says the units.
    XCTAssertTrue(rowA.label.contains("3,759 millimetres"), rowA.label)
    XCTAssertTrue(rowA.label.contains("12 feet 4 inches"), rowA.label)
    assertFonts("Field controls")
    shot("13 Field controls, recorded")
    goBack()
    XCTAssertTrue(review.waitForExistence(timeout: 10))

    // Before you leave (phone-field §6) from the Rooms not scanned row, focused on it.
    skipped.tap()
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Rooms not scanned recorded"].exists)
    XCTAssertTrue(app.staticTexts["Compass reading"].exists)
    XCTAssertFalse(app.buttons["checklist.readCompass"].exists, "Read is hidden (R-22)")
    XCTAssertEqual(element("checklist.detail.compass").label, "Floor 1 verified")
    shot("14 Before you leave, open")
    tap(app.buttons["checklist.allRoomsScanned"])
    waitForLabel(element("checklist.detail.skippedRoomsRecorded"), "All rooms scanned")
    // Rename again from the checklist: the photo labeled Shower follows the new name.
    tap(app.buttons["checklist.renameRooms"])
    XCTAssertTrue(nameField.waitForExistence(timeout: 10))
    XCTAssertEqual(nameField.value as? String, "Shower")
    XCTAssertFalse(noPhotoYet.exists, "the room has its photo")
    nameField.tap()
    nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Walk-in shower")
    tap(app.buttons["rooms.save"])
    XCTAssertTrue(app.staticTexts["1 photo, 1 room covered"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Walk-in shower has no photo"].exists)
    let finishCapture = app.buttons["checklist.finish"]
    waitForLabel(finishCapture, "Finish capture")
    assertFonts("Before you leave")
    shot("15 Before you leave, passed")
    finishCapture.tap()

    // Package ready (phone-package §13.3 test 1): the real file list, no phone report.
    XCTAssertTrue(app.staticTexts["Package ready"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["Step 3 of 3"].exists)
    let packageFloor = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'package.floor.'")
    ).firstMatch
    XCTAssertTrue(packageFloor.waitForExistence(timeout: 60))
    XCTAssertTrue(packageFloor.label.hasPrefix("Original Exports, "), packageFloor.label)
    XCTAssertEqual(packageFloor.value as? String, "expanded")
    let plans = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier ENDSWITH '.plans'")).firstMatch
    XCTAssertTrue(
      plans.label.hasPrefix("Plan DXF \u{00B7} rooms CSV \u{00B7} plan sheet PDF"), plans.label)
    XCTAssertTrue(texts(containing: "revision 1").firstMatch.exists)
    XCTAssertTrue(texts(containing: "The station makes the spatial report.").firstMatch.exists)
    XCTAssertTrue(texts(containing: "compass: recorded").firstMatch.exists)
    XCTAssertEqual(texts(containing: "Spatial Report").count, 0)
    assertFonts("Package ready")
    shot("16 Package ready")
    tap(app.buttons["package.seal"])

    // Package status (§4): registered, uploaded, the checks queued at the stub station.
    let checks = element("station.checks")
    XCTAssertTrue(checks.waitForExistence(timeout: 30))
    waitForLabel(checks, "Checks, not yet, queued", timeout: 60)
    XCTAssertTrue(app.staticTexts["Uploaded"].exists)
    XCTAssertTrue(element("station.registered").label.hasPrefix("Registered, done, "))
    XCTAssertEqual(element("station.published").label, "Published to the HUB, not yet")
    XCTAssertTrue(app.staticTexts["Revision 1 \u{00B7} sealed"].exists)
    assertFonts("Package status")
    shot("17 Uploaded")

    // Back on the overview of the sealed visit: "Upload status", no new floor; the floor row
    // opens the scan's Floorplan (with its north symbol).
    goBack()
    waitForLabel(review, "Upload status")
    XCTAssertFalse(app.buttons["overview.addFloor"].exists, "nothing is added after sealing")
    XCTAssertTrue(
      app.staticTexts["Captured today by UI Test Operator \u{00B7} revision 1 sealed"].exists)
    shot("18 Capture overview, sealed")
    tap(app.buttons["overview.floor.floor-1"])
    let page = element("floorplan.page")
    XCTAssertTrue(page.waitForExistence(timeout: 30), "floor plan page")
    let download = element("floorplan.download")
    waitForLabel(download, "Download floor plan, PDF and PNG")
    assertFonts("Floor scan")
    shot("19 Floorplan")
    let units = app.buttons["floorplan.units"]
    XCTAssertEqual(units.label, "Units, feet and inches")
    units.tap()
    tap(app.buttons["Metric (m)"].firstMatch)
    waitForLabel(units, "Units, metres")
    waitForLabel(download, "Download floor plan, PDF and PNG")
    shot("20 Floorplan, metric")
    XCTAssertTrue(app.buttons["scan.view3D"].exists)
    goBack()
    XCTAssertTrue(review.waitForExistence(timeout: 10))

    // The sealed visit's Before you leave is read-only (phone-field B4).
    tap(app.buttons["overview.photos"])
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["checklist.finish"].exists)
    XCTAssertTrue(
      element("checklist.footnote").label.hasPrefix("Revision 1 is sealed."),
      element("checklist.footnote").label)
    shot("21 Before you leave, sealed")
    goBack()

    // Back to the Captures home: the visit is In progress, its upload checked.
    goBack()
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 10))
    let row = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'captures.row.' AND label CONTAINS 'UI test visit'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    waitFor("the row says checks running") {
      row.label.contains("1 floor \u{00B7} uploaded \u{00B7} checks running")
    }
    XCTAssertTrue(row.label.contains("Checking"), row.label)
    XCTAssertTrue(app.staticTexts["In progress"].exists)
    shot("22 Captures, checking")

    // The account dialog (U9). In the replay mode signing out shows the sign-in screen, and
    // "Sign in with Microsoft" signs the stub operator back in (there is no MSAL): the
    // captures are still there (sign-out deletes nothing).
    tap(app.buttons["account.avatar"])
    XCTAssertTrue(app.staticTexts["Signed in as UI Test Operator"].waitForExistence(timeout: 5))
    shot("23 Account")
    tap(app.buttons["account.signOut"].firstMatch)
    XCTAssertTrue(app.staticTexts["Sign in"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Use your Chapter Microsoft account."].exists)
    XCTAssertTrue(anyText(containing: "Chapter Renovation").exists, "the real logo")
    assertFonts("Sign in")
    shot("24 Sign in")
    tap(app.buttons["signIn.microsoft"])
    XCTAssertTrue(row.waitForExistence(timeout: 15), "the capture is still on the phone")
  }

  // MARK: Not configured (phone-capture §3.6)

  func testNotConfigured() {
    // A Debug build without the replay mode and with the placeholder configuration.
    app.launchArguments = []
    app.launch()
    XCTAssertTrue(app.staticTexts["App is not configured"].waitForExistence(timeout: 30))
    XCTAssertTrue(
      app.staticTexts["This build has no sign-in or station settings. Nothing is sent anywhere."]
        .exists)
    XCTAssertTrue(anyText(containing: "Chapter Renovation").exists, "the real logo")
    shot("25 Not configured")
  }

  // MARK: U3 Address different on site

  func testAddressDifferentOnSite() {
    launch()
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    tap(app.buttons["captures.newCapture"])
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    let toggle = app.switches["capture.addressConfirmed"]
    tap(toggle)
    tap(toggle)
    let alert = app.alerts["Address is different on site?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    XCTAssertTrue(alert.buttons["Go back"].exists)
    XCTAssertTrue(alert.buttons["Call the PM"].exists)
    XCTAssertTrue(
      alert.staticTexts.matching(
        NSPredicate(
          format: "label == %@",
          "Do not scan under this project. Call the PM to fix the HUB record, then start the "
            + "capture again. Nothing is saved.")
      ).firstMatch.exists)
    shot("30 New capture, address different")
    alert.buttons["Go back"].tap()
    XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["New capture"].exists, "Go back stays on New capture")
    let next = app.buttons["capture.continue"]
    XCTAssertEqual(next.label, "Confirm the address to continue")
    XCTAssertFalse(next.isEnabled)
    XCTAssertTrue(app.staticTexts["618 Valley Street, Test Town"].exists, "the project is kept")
    shot("31 New capture, address not confirmed")

    // Call the PM: no PM phone from the HUB, so no call; the draft is discarded, nothing saved.
    tap(toggle)
    tap(toggle)
    tap(app.alerts.buttons["Call the PM"])
    XCTAssertTrue(app.staticTexts["No captures on this phone yet."].waitForExistence(timeout: 10))
  }

  // MARK: U4 Offline at New capture

  func testOfflineProjectListAtNewCapture() {
    launch(["-ChapterUITestOffline"])
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    Thread.sleep(forTimeInterval: 1)  // the list is saved once at launch, then the HUB is offline
    tap(app.buttons["captures.newCapture"])
    let banner = anyText(
      containing: "No connection. Showing the 1 project saved on this phone (updated ")
    XCTAssertTrue(banner.waitForExistence(timeout: 15))
    XCTAssertTrue(banner.label.contains("You can scan offline; the upload waits for a connection."))
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    let project = app.buttons["capture.project"]
    waitFor("the row says the copy is saved") {
      (project.value as? String)?.hasSuffix("\u{00B7} saved on this phone") == true
    }
    XCTAssertTrue(
      anyText(containing: "A project not in this list cannot be started offline").exists)
    tap(app.switches["capture.addressConfirmed"])
    waitForLabel(app.buttons["capture.continue"], "Continue offline")
    XCTAssertTrue(app.buttons["capture.continue"].isEnabled)
    shot("32 New capture, offline")
  }

  // MARK: U5 Tracking lost, paused, restart

  func testTrackingLostPauseAndRestart() {
    launch(["-ChapterUITestTrackingLost", "2", "5", "-ChapterUITestScanStep", "1.2"])
    openStepTwo()
    tap(app.buttons["capture.mode.floor"])
    tap(app.buttons["capture.startScan"])
    let card = element("scan.trackingLost")
    XCTAssertTrue(card.waitForExistence(timeout: 20), "Tracking lost")
    XCTAssertTrue(app.staticTexts["Tracking lost"].exists)
    XCTAssertFalse(app.buttons["scan.pause"].isEnabled, "Pause is disabled while tracking is lost")
    XCTAssertTrue(element("scan.status").label.hasPrefix("Recording paused"))
    shot("33 Live scan, tracking lost")

    // Restart this floor instead: confirmation, then a new scan from 0.
    tap(app.buttons["scan.restartFloor"])
    let alert = app.alerts["Restart Floor 1?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    shot("34 Live scan, restart")
    alert.buttons["Restart"].tap()
    XCTAssertTrue(anyText(containing: "0 walls").waitForExistence(timeout: 3), "counts reset")
    // The new scan loses tracking too, then finds it again.
    XCTAssertTrue(card.waitForExistence(timeout: 20))
    XCTAssertTrue(card.waitForNonExistence(timeout: 20), "tracking comes back")
    let pause = app.buttons["scan.pause"]
    waitFor("Pause enabled again") { pause.isEnabled }

    // Paused by the operator (not drawn): Resume, the paused pill and the recording line.
    pause.tap()
    waitForLabel(pause, "Resume", timeout: 5)
    XCTAssertTrue(element("scan.status").label.hasPrefix("Recording paused"))
    shot("35 Live scan, paused")
    pause.tap()
    waitForLabel(pause, "Pause", timeout: 5)
  }

  // MARK: U6 Overview statuses, U8 another floor

  func testOverviewStatusesAndAnotherFloor() {
    launch()
    openStepTwo()
    scanFloor()
    leavePhotosForTheOverview()

    // The first floor without photos: Photos and Rooms not scanned are missing. Field controls
    // never block under the shipping policy (owner question Q-A), so 2 items, not 3.
    let photos = app.buttons["overview.photos"]
    XCTAssertTrue(photos.label.contains("Room 1 has no photo"), photos.label)
    XCTAssertTrue(photos.label.contains("Missing"), photos.label)
    let review = app.buttons["overview.review"]
    waitForLabel(review, "Fix 2 items to review the package")
    XCTAssertFalse(review.isEnabled)
    XCTAssertTrue(app.buttons["overview.floor.floor-1"].label.contains("Open"))
    shot("36 Capture overview, open items")

    // Scan another floor or room: step 2 with the project title, "Floor 2"; Back leaves it.
    tap(app.buttons["overview.addFloor"])
    XCTAssertTrue(app.staticTexts["What are you scanning?"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["UI test visit"].exists, "the caption is the project title")
    XCTAssertEqual(app.textFields["capture.floorName"].value as? String, "Floor 2")
    goBack()
    XCTAssertTrue(review.waitForExistence(timeout: 10))
    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.floor.'")).count,
      1)

    // A name already captured is refused before the scan.
    tap(app.buttons["overview.addFloor"])
    let name = app.textFields["capture.floorName"]
    XCTAssertTrue(name.waitForExistence(timeout: 10))
    tap(app.buttons["capture.mode.floor"])
    replaceText(in: name, with: "Floor 1")
    let start = app.buttons["capture.startScan"]
    waitForLabel(start, "Floor 1 is already captured. Use another name")
    XCTAssertFalse(start.isEnabled)
    shot("37 What are you scanning, name taken")
    replaceText(in: name, with: "Floor 2")
    waitForLabel(start, "Start scan")
    start.tap()
    let finish = app.buttons["scan.finish"]
    XCTAssertTrue(finish.waitForExistence(timeout: 20))
    waitFor("Finish floor enabled") { finish.isEnabled }
    finish.tap()
    leavePhotosForTheOverview()
    XCTAssertTrue(app.buttons["overview.floor.floor-2"].waitForExistence(timeout: 10))
    XCTAssertTrue(photos.label.contains("Room 1 and 1 more room have no photo"), photos.label)
    shot("38 Capture overview, two floors")
  }

  // MARK: U7 Resume after a relaunch

  func testResumeAfterRelaunch() {
    let root = ["-ChapterUITestVisitsRoot", "relaunch-\(UUID().uuidString.prefix(8))"]
    launch(root)
    openStepTwo()
    scanFloor()
    leavePhotosForTheOverview()
    app.terminate()

    launch(root)
    XCTAssertTrue(app.staticTexts["In progress"].waitForExistence(timeout: 30))
    let row = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'captures.row.' AND label CONTAINS 'UI test visit'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    XCTAssertTrue(row.label.contains("1 floor \u{00B7} not sealed yet"), row.label)
    shot("39 Captures, in progress after a relaunch")
    row.tap()
    let floor = app.buttons["overview.floor.floor-1"]
    XCTAssertTrue(floor.waitForExistence(timeout: 15))
    waitFor("the floor is mapped again") { floor.label.contains("Whole floor \u{00B7} 1 room") }
    XCTAssertTrue(app.staticTexts["UI test visit"].exists)
    shot("40 Capture overview, resumed")
  }

  // MARK: The v1 visits on the phone show up after the update

  func testV1VisitsShowUpOnTheCapturesHome() {
    launch(["-ChapterUITestV1Visits"])
    XCTAssertTrue(app.staticTexts["In progress"].waitForExistence(timeout: 30))
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'captures.row.'"))
    waitFor("three v1 visits") { rows.count == 3 }
    let drafted = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH 'captures.row.' AND label CONTAINS 'Fixture box-room' "
          + "AND label CONTAINS 'not sealed yet'")
    ).firstMatch
    XCTAssertTrue(drafted.exists, "the visit that reached Package ready")
    let sealed = app.buttons.matching(
      NSPredicate(
        format: "identifier BEGINSWITH 'captures.row.' AND label CONTAINS 'Fixture box-room' "
          + "AND NOT (label CONTAINS 'not sealed yet')")
    ).firstMatch
    XCTAssertTrue(sealed.exists, "the sealed visit, its upload resumed")
    let scans = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'captures.row.' AND label BEGINSWITH 'Scan of '")
    ).firstMatch
    XCTAssertTrue(scans.exists, "the visit with scans only")
    XCTAssertTrue(scans.label.contains("1 scan \u{00B7} no HUB project recorded"), scans.label)
    shot("26 Captures, v1 visits")

    // The scans-only visit: its scan's Floorplan is still there.
    scans.tap()
    XCTAssertTrue(app.staticTexts["Scans"].waitForExistence(timeout: 10))
    shot("27 v1 scans")
    tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'legacy.scan.'")).firstMatch)
    XCTAssertTrue(element("floorplan.page").waitForExistence(timeout: 30))
    goBack()
    goBack()

    // The drafted visit opens at its overview, where it was left.
    tap(drafted)
    let floor = app.buttons["overview.floor.floor-1"]
    XCTAssertTrue(floor.waitForExistence(timeout: 15))
    waitFor("mapped") { floor.label.contains("One room \u{00B7} 1 room \u{00B7} 1 photo") }
    XCTAssertTrue(app.staticTexts["Fixture box-room"].exists)
    shot("28 Capture overview, v1 visit")
  }

  // MARK: phone-package §13.3 (2) and (5): the verdict, then revision 2

  func testVerdictThenRevisionTwo() {
    launch(["-ChapterUITestVerdict", "limited"])
    reachPackageReady()
    tap(app.buttons["package.seal"])
    let registered = element("station.registered")
    XCTAssertTrue(registered.waitForExistence(timeout: 30))
    waitFor("registered") { registered.label.hasPrefix("Registered, done, ") }
    let card = element("verdict.card")
    XCTAssertTrue(card.waitForExistence(timeout: 60), "Verdict received")
    XCTAssertTrue(card.label.hasPrefix("Verdict: Limited."), card.label)
    XCTAssertTrue(app.staticTexts["UI test visit"].exists, "the title is the project title (R-29)")
    let published = element("station.published")
    waitFor("published", timeout: 60) { published.label.hasPrefix("Published to the HUB, done, ") }
    XCTAssertTrue(app.buttons["verdict.openHub"].exists)
    assertFonts("Verdict received")
    shot("41 Verdict received, limited")

    // Add to this capture: the overview in revision mode.
    tap(app.buttons["verdict.addToCapture"])
    let review = app.buttons["overview.review"]
    XCTAssertTrue(review.waitForExistence(timeout: 15))
    XCTAssertTrue(
      app.staticTexts["Captured today by UI Test Operator \u{00B7} revision 2 not sealed yet"]
        .exists)
    waitForLabel(review, "Review revision 2")
    shot("42 Capture overview, revision 2")
    // One more photo.
    tap(app.buttons["overview.photos"])
    tap(app.buttons["photo.shutter"], timeout: 20)
    tap(app.buttons["photo.room.Room 1"])
    tap(app.buttons["photo.direction.S"])
    tap(app.buttons["photo.subject.ceiling"])
    tap(app.buttons["photo.doneWithPhotos"])
    tap(review)

    // Revision 2: what changed.
    XCTAssertTrue(app.staticTexts["Revision 2"].waitForExistence(timeout: 60))
    XCTAssertTrue(anyText(containing: "1 photo").waitForExistence(timeout: 60))
    let manifest = element("revision.manifest")
    XCTAssertTrue(manifest.waitForExistence(timeout: 30))
    XCTAssertTrue(manifest.label.contains("entries"), manifest.label)
    XCTAssertTrue(anyText(containing: "Only the 1 new file is uploaded.").exists)
    assertFonts("Revision 2")
    shot("43 Revision 2")
    tap(app.buttons["revision.seal"])

    // Revision 2 uploads only its new file and gets its own verdict.
    XCTAssertTrue(card.waitForExistence(timeout: 90), "revision 2's verdict")
    XCTAssertTrue(app.staticTexts["Revision 2"].waitForExistence(timeout: 10))
    shot("44 Verdict received, revision 2")

    // The overview offers the verdict; the home lists the capture as sealed.
    goBack()
    waitForLabel(review, "Open the verdict")
    goBack()
    let row = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'captures.row.' AND label CONTAINS 'UI test visit'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    waitFor("sealed with the verdict") {
      row.label.contains("Revision 2 \u{00B7} sealed") && row.label.contains("Limited")
    }
    XCTAssertTrue(app.staticTexts["Sealed"].exists)
    shot("45 Captures, sealed")
    // A Sealed row opens Verdict received on its own.
    row.tap()
    XCTAssertTrue(card.waitForExistence(timeout: 15))
    goBack()
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 10))
  }

  // MARK: phone-package §13.3 (3): paused offline

  func testUploadPausedOfflineThenResumes() {
    launch(["-ChapterUITestOffline", "10"])
    reachPackageReady()
    tap(app.buttons["package.seal"])
    let paused = anyText(
      containing: "Paused: no connection. Resumes on its own. You can close the app.")
    XCTAssertTrue(paused.waitForExistence(timeout: 30))
    XCTAssertTrue(app.staticTexts["Uploading"].exists)
    assertFonts("Uploading, paused")
    shot("46 Uploading, paused")
    // The home row while paused.
    goBack()
    goBack()
    let row = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'captures.row.' AND label CONTAINS 'UI test visit'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    if row.label.contains("upload paused") {
      shot("47 Captures, upload paused")
    }
    // It resumes on its own.
    waitFor("uploaded", timeout: 90) { row.label.contains("uploaded \u{00B7} checks running") }
  }

  // MARK: phone-package §13.3 (4): Upload stopped, re-seal as revision 2

  func testUploadStoppedThenResealAsRevisionTwo() {
    launch(["-ChapterUITestRefuse"])
    reachPackageReady()
    tap(app.buttons["package.seal"])
    XCTAssertTrue(app.staticTexts["Upload stopped"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.buttons["upload.retry"].exists)
    let reseal = app.buttons["upload.reseal"]
    XCTAssertEqual(reseal.label, "Re-seal as revision 2")
    XCTAssertTrue(
      anyText(containing: "The station refused the upload (409 package_conflict).").exists)
    assertFonts("Upload stopped")
    shot("48 Upload stopped")

    // The home row says so (In progress, ■ Stopped).
    goBack()
    let review = app.buttons["overview.review"]
    waitForLabel(review, "Upload status")
    goBack()
    let row = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'captures.row.' AND label CONTAINS 'UI test visit'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    waitFor("stopped") { row.label.contains("upload stopped") && row.label.contains("Stopped") }
    shot("49 Captures, upload stopped")
    row.tap()
    tap(review)
    XCTAssertTrue(app.staticTexts["Upload stopped"].waitForExistence(timeout: 15))

    // Re-seal as revision 2: the alert, then revision 2 uploads.
    tap(reseal)
    let alert = app.alerts["Re-seal as revision 2?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    XCTAssertTrue(
      alert.staticTexts.matching(
        NSPredicate(
          format: "label == %@",
          "The app builds revision 2 from the scans, photos and controls on this phone and "
            + "uploads it. Revision 1 stays on this phone and is not uploaded further.")
      ).firstMatch.exists)
    shot("50 Re-seal alert")
    alert.buttons["Re-seal"].tap()
    XCTAssertTrue(app.staticTexts["Revision 2 \u{00B7} sealed"].waitForExistence(timeout: 60))
    let checks = element("station.checks")
    waitForLabel(checks, "Checks, not yet, queued", timeout: 60)
    shot("51 Uploaded, revision 2")
  }

  // MARK: compass §13.4 approximate and none

  func testCompassApproximate() {
    launch(compass: "approximate")
    openStepTwo()
    waitForLabel(
      element("compass.row"),
      "Compass. North 212 degrees magnetic, plus or minus 12 degrees. Approximate, read just now.")
    shot("52 What are you scanning, approximate")
    tap(app.buttons["capture.mode.floor"])
    tap(app.buttons["capture.startScan"])
    waitForLabel(
      element("scan.compass"), "Compass approximate, magnetic north, plus or minus 12 degrees")
    shot("53 Live scan, approximate")
    let finish = app.buttons["scan.finish"]
    waitFor("Finish floor enabled") { finish.isEnabled }
    finish.tap()
    leavePhotosForTheOverview()
    let compass = app.buttons["overview.compass"]
    XCTAssertTrue(compass.label.contains("Floor 1 approximate"), compass.label)
    XCTAssertTrue(compass.label.contains("Approx."), compass.label)
    shot("54 Capture overview, compass approximate")
  }

  func testCompassNone() {
    launch(compass: "none", ["-ChapterUITestScanStep", "2.5"])
    openStepTwo()
    waitForLabel(
      element("compass.row"),
      "Compass. No compass reading. Not verified, move the phone in a figure 8, then read again.")
    shot("55 What are you scanning, no reading")
    tap(app.buttons["capture.mode.floor"])
    tap(app.buttons["capture.startScan"])
    let chip = element("scan.compass")
    waitForLabel(chip, "Compass reading", timeout: 10)
    shot("56 Live scan, compass reading")
    waitForLabel(chip, "Compass not verified", timeout: 15)
    shot("57 Live scan, compass not verified")
    let finish = app.buttons["scan.finish"]
    waitFor("Finish floor enabled") { finish.isEnabled }
    finish.tap()

    // No camera heading: nothing pre-filled.
    tap(app.buttons["photo.shutter"], timeout: 20)
    XCTAssertTrue(anyText(containing: "no compass reading, choose one").waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["photo.direction.E"].isSelected)
    tap(app.buttons["photo.room.Room 1"])
    tap(app.buttons["photo.direction.W"])
    tap(app.buttons["photo.subject.general"])
    tap(app.buttons["photo.doneWithPhotos"])

    let compass = app.buttons["overview.compass"]
    XCTAssertTrue(compass.waitForExistence(timeout: 15))
    XCTAssertTrue(compass.label.contains("Floor 1 not read"), compass.label)
    XCTAssertTrue(compass.label.contains("Not verified"), compass.label)
    compass.tap()
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 10))
    XCTAssertEqual(
      element("checklist.detail.compass").label,
      "Floor 1 not read: its plan will say \"not verified\"")
    XCTAssertFalse(app.buttons["checklist.readCompass"].exists)
    let finishCapture = app.buttons["checklist.finish"]
    XCTAssertEqual(finishCapture.label, "Fix 1 item to finish", "the compass never counts")
    tap(app.buttons["checklist.allRoomsScanned"])
    waitForLabel(finishCapture, "Finish capture")
    XCTAssertTrue(finishCapture.isEnabled, "the compass never blocks")
    shot("58 Before you leave, compass not read")
  }

  // MARK: U10 Accessibility audit

  func testAccessibilityAudit() throws {
    launch()
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    try audit("Captures")
    tap(app.buttons["captures.newCapture"])
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    tap(app.switches["capture.addressConfirmed"])
    try audit("New capture")
    tap(app.buttons["capture.continue"])
    waitForLabel(
      element("compass.row"),
      "Compass. North 212 degrees true, plus or minus 8 degrees. Verified, read just now.")
    try audit("What are you scanning?")
    scanFloor()
    leavePhotosForTheOverview()
    try audit("Capture overview")
    goBack()
    XCTAssertTrue(app.staticTexts["In progress"].waitForExistence(timeout: 10))
    try audit("Captures, in progress")
  }

  /// The home, New capture, step 2 and the overview at the largest accessibility text size
  /// (screenshots for the review: rows stack, nothing is cut).
  func testLargestTextSize() {
    launch([
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    shot("60 Captures, AX5")
    tap(app.buttons["captures.newCapture"])
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    let toggle = app.switches["capture.addressConfirmed"]
    scrollAbove(app.buttons["capture.continue"], toggle)
    tap(toggle)
    XCTAssertEqual(toggle.value as? String, "1")
    shot("61 New capture, AX5")
    tap(app.buttons["capture.continue"])
    XCTAssertTrue(app.textFields["capture.floorName"].waitForExistence(timeout: 10))
    shot("62 What are you scanning, AX5")
    let floor = app.buttons["capture.mode.floor"]
    scrollAbove(app.buttons["capture.startScan"], floor)
    tap(floor)
    tap(app.buttons["capture.startScan"])
    let finish = app.buttons["scan.finish"]
    XCTAssertTrue(finish.waitForExistence(timeout: 20))
    waitFor("Finish floor enabled") { finish.isEnabled }
    finish.tap()
    leavePhotosForTheOverview()
    shot("63 Capture overview, AX5")
    app.swipeUp()
    shot("64 Capture overview, AX5, scrolled")
  }

  /// `performAccessibilityAudit` on the screen (phone-capture §10.3 U10: contrast, hit regions,
  /// labels, traits, element detection and Dynamic Type support), with the listed known
  /// exceptions (`isKnownException`). Clipping at the accessibility sizes is reviewed on the
  /// screenshots of `testLargestTextSize` instead: the audit flags texts the design caps at a
  /// number of lines (the 3-line subtitle under a large title, ChapterUI's `ScreenSubtitle`).
  ///
  /// A first look only notes issues; when it finds one, the audit looks again 8 seconds later
  /// and fails on what is still there. Element detection reads the screen's pixels, and a
  /// freshly booted simulator shows system banners over the app for a few seconds ("Ready for
  /// Apple Intelligence"), read as the app's own inaccessible text.
  private func audit(_ screen: String) throws {
    var types = XCUIAccessibilityAuditType.all
    types.remove(.textClipped)
    var found = false
    try app.performAccessibilityAudit(for: types) { issue in
      let ignored = self.isKnownException(issue)
      self.log(screen, issue, ignored ? "known" : "first look")
      found = found || !ignored
      return true
    }
    guard found else { return }
    Thread.sleep(forTimeInterval: 8)
    try app.performAccessibilityAudit(for: types) { issue in
      let ignored = self.isKnownException(issue)
      self.log(screen, issue, ignored ? "known" : "ISSUE")
      return ignored
    }
  }

  private func log(_ screen: String, _ issue: XCUIAccessibilityAuditIssue, _ verdict: String) {
    print(
      "audit \(screen): \(verdict) \(issue.auditType.rawValue) "
        + "\(issue.compactDescription) | \(issue.detailedDescription) | "
        + "\(issue.element?.debugDescription ?? "no element")")
  }

  /// The known exceptions (phone-capture §10.3 U10):
  /// - the system switch (phone-capture §2.4.2 accepts the system toggle);
  /// - the navigation bar, whose items iOS keeps at bar size and shows in the large content
  ///   viewer instead of growing with Dynamic Type (the "Step 1 of 3" caption).
  private func isKnownException(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
    guard let element = issue.element else { return false }
    if element.elementType == .switch || element.elementType == .navigationBar { return true }
    let bar = app.navigationBars.firstMatch
    if issue.auditType == .dynamicType, bar.exists, bar.frame.contains(element.frame) {
      return true
    }
    return false
  }
}
