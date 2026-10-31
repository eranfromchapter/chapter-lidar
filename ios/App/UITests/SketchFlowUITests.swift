import XCTest

/// The sketch capture (spec F14, AC7) end to end in the Debug replay mode: Captures home →
/// Capture without LiDAR → New capture (no device gate) → How do you want to measure? (Enter
/// from a sketch, spec F15 2) → What are you drawing from? (no sketch) →
/// Rooms and measurements (one rectangular bedroom with two walls, the ceiling, a door and a
/// window) → Check ("Complete") → Finish floor → photos → the Capture overview's floor row
/// says "sketch" → Before you leave → Package ready lists the sketch measurements and the mesh.
/// Every screen is attached as a screenshot. Main-actor isolated, as XCUIAutomation is.
@MainActor
final class SketchFlowUITests: XCTestCase {
  private lazy var app = XCUIApplication()

  nonisolated override func setUp() {
    continueAfterFailure = false
  }

  // MARK: Helpers

  private func launch() {
    app.launchArguments = ["-ChapterUITestReplay", "box-room", "-ChapterUITestCompass", "verified"]
    app.launch()
  }

  private func tap(_ element: XCUIElement, timeout: TimeInterval = 15) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout), "missing \(element)")
    element.tap()
  }

  private func button(_ label: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
  }

  /// The element with this accessibility identifier, of any type.
  private func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func shot(_ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
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

  private func waitForLabel(
    _ element: XCUIElement, _ label: String, timeout: TimeInterval = 30,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    waitFor("label \(label)", timeout: timeout, file: file, line: line) {
      element.exists && element.label == label
    }
  }

  /// The system back chevron of the navigation bar on top.
  private func goBack() {
    tap(app.navigationBars.buttons.element(boundBy: 0))
  }

  /// Scrolls (up, then down) until `element` can be tapped: the room sheet and the screens are
  /// longer than the phone, and XCTest does not scroll on its own.
  private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(element)", file: file, line: line)
    var swipes = 0
    while !element.isHittable, swipes < 8 {
      app.swipeUp(velocity: .slow)
      swipes += 1
    }
    swipes = 0
    while !element.isHittable, swipes < 8 {
      app.swipeDown(velocity: .slow)
      swipes += 1
    }
    XCTAssertTrue(element.isHittable, "\(element) is not on screen", file: file, line: line)
  }

  /// Types a length into one of the sketch fields and closes the keyboard with Return. A tap
  /// while the previous field's keyboard is still going away does not always focus the field,
  /// so the tap is repeated until the keyboard is up.
  private func enter(_ text: String, into identifier: String) {
    let field = app.textFields[identifier]
    reveal(field)
    for attempt in 0..<4 {
      field.tap()
      if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
      XCTAssertLessThan(attempt, 3, "no keyboard for \(identifier)")
      Thread.sleep(forTimeInterval: 0.5)
    }
    field.typeText(text + "\n")
    XCTAssertEqual(field.value as? String, text, identifier)
  }

  private func tapRevealed(_ identifier: String) {
    let control = app.buttons[identifier].exists ? app.buttons[identifier] : element(identifier)
    reveal(control)
    control.tap()
  }

  // MARK: AC7

  func testSketchCaptureFromTheHomeToPackageReady() {
    launch()

    // Captures home: "Capture without LiDAR" next to "New capture", with the footnote (2.1).
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    let sketch = app.buttons["captures.sketchCapture"]
    XCTAssertTrue(sketch.waitForExistence(timeout: 10))
    XCTAssertEqual(sketch.label, "Capture without LiDAR")
    XCTAssertEqual(
      element("captures.sketchFootnote").label,
      "No LiDAR? Walk the rooms with the camera, or enter the measurements from a sketch.")
    shot("S01 Captures, with Capture without LiDAR")
    sketch.tap()

    // New capture, step 1 of 5: the HUB project and the address, no device gate.
    XCTAssertTrue(app.staticTexts["New capture"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 1 of 5"].exists)
    XCTAssertEqual(app.buttons["capture.continue"].label, "Choose a HUB project to continue")
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    tap(app.switches["capture.addressConfirmed"])
    waitForLabel(app.buttons["capture.continue"], "Continue")
    shot("S02 New capture (sketch)")
    tap(app.buttons["capture.continue"])

    // How do you want to measure? (spec F16 2): the sketch photo is the default; enter from a
    // sketch.
    XCTAssertTrue(app.staticTexts["How to measure"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 2 of 5"].exists)
    waitForLabel(app.buttons["walkthrough.method.continue"], "Photograph the sketch")
    tap(app.buttons["walkthrough.method.sketch"])
    waitForLabel(app.buttons["walkthrough.method.continue"], "Continue")
    shot("S02b How do you want to measure, sketch")
    tap(app.buttons["walkthrough.method.continue"])

    // What are you drawing from? No sketch; the floor and the mode as step 2 of a scan.
    XCTAssertTrue(app.staticTexts["What are you drawing from?"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 3 of 5"].exists)
    XCTAssertEqual(app.textFields["sketch.floorName"].value as? String, "Floor 1")
    XCTAssertEqual(app.buttons["sketch.continue"].label, "Choose what you are drawing")
    tap(app.buttons["sketch.source.none"])
    tap(app.buttons["sketch.mode.floor"])
    waitForLabel(app.buttons["sketch.continue"], "Continue")
    shot("S03 What are you drawing from")
    tap(app.buttons["sketch.continue"])

    // Rooms and measurements: the ceiling, then the one room's entry.
    XCTAssertTrue(app.staticTexts["Rooms and measurements"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 4 of 5"].exists)
    enter("8' 0\"", into: "sketch.ceiling")
    let roomRow = app.buttons["sketch.room.room-1"]
    XCTAssertTrue(roomRow.waitForExistence(timeout: 10), "Continue adds the first room")
    XCTAssertTrue(roomRow.label.contains("Room 1"), roomRow.label)
    shot("S04 Rooms and measurements")
    roomRow.tap()

    // The room sheet: name, type, two adjacent walls (Measured), a door in wall 3 and a window
    // in wall 1 (the required set of 1.6).
    XCTAssertTrue(element("sketch.room.sheet").waitForExistence(timeout: 10))
    let name = app.textFields["sketch.room.name"]
    tap(name)
    name.typeText("Bedroom\n")
    tap(app.buttons["sketch.room.type.bedroom"])
    enter("13' 1.5\"", into: "sketch.wall.wall-1.length")
    XCTAssertEqual(app.buttons["sketch.wall.wall-1.length.measured"].label, "Wall 1: measured")
    XCTAssertEqual(element("sketch.wall.wall-1.length.stored").label, "4,001 mm · 13' 1.5\"")
    enter("9' 10.5\"", into: "sketch.wall.wall-2.length")
    shot("S05 Room entry, walls")

    tapRevealed("sketch.opening.add.door")
    tapRevealed("sketch.opening.door-1.wall.wall-3")
    enter("32", into: "sketch.opening.door-1.width")
    tapRevealed("sketch.opening.door-1.fromCorner.start")
    enter("12", into: "sketch.opening.door-1.distance")

    tapRevealed("sketch.opening.add.window")
    tapRevealed("sketch.opening.window-1.wall.wall-1")
    enter("36", into: "sketch.opening.window-1.width")
    tapRevealed("sketch.opening.window-1.fromCorner.end")
    enter("48", into: "sketch.opening.window-1.distance")
    enter("36", into: "sketch.opening.window-1.sill")
    enter("48", into: "sketch.opening.window-1.height")
    shot("S06 Room entry, openings")
    tap(app.buttons["sketch.room.done"])
    waitFor("the room sheet closes") { !element("sketch.room.sheet").exists }

    // The room row: entered, nothing of the required set missing.
    waitFor("the room row says Bedroom and Entered") {
      roomRow.label.contains("Bedroom") && roomRow.label.contains("Entered")
    }
    shot("S07 Rooms and measurements, entered")
    tap(app.buttons["sketch.check"])

    // Check: the plan drawn from the solver, "Complete", Finish floor.
    XCTAssertTrue(app.buttons["sketch.finish"].waitForExistence(timeout: 10), "the Check screen")
    XCTAssertTrue(app.staticTexts["Check"].exists)
    XCTAssertTrue(app.staticTexts["Step 5 of 5"].exists)
    let status = element("sketch.status")
    waitFor("the solver says Complete") { status.exists && status.label.contains("Complete") }
    XCTAssertTrue(element("sketch.plan").exists, "the Floorplan preview")
    XCTAssertFalse(element("sketch.solveError").exists)
    shot("S08 Check")
    let finish = app.buttons["sketch.finish"]
    waitFor("Finish floor enabled") { finish.isEnabled }
    finish.tap()

    // Photos, then the overview: the floor row reads "Floor 1 · sketch …".
    let coverage = element("photo.coverage")
    XCTAssertTrue(coverage.waitForExistence(timeout: 30), "the photo step")
    waitForLabel(coverage, "Still needs a photo: Bedroom")
    shot("S09 Viewfinder after the sketch floor")
    tap(app.buttons["photo.done"])
    let floorRow = app.buttons["overview.floor.floor-1"]
    XCTAssertTrue(floorRow.waitForExistence(timeout: 15), "the overview")
    XCTAssertTrue(floorRow.label.hasPrefix("Floor 1"), floorRow.label)
    XCTAssertTrue(floorRow.label.contains("Whole floor · sketch · 1 room"), floorRow.label)
    let compass = app.buttons["overview.compass"]
    XCTAssertTrue(compass.label.contains("Not needed"), compass.label)
    let controls = app.buttons["overview.controls"]
    XCTAssertTrue(controls.label.contains("Measured from the sketch"), controls.label)
    shot("S10 Capture overview, sketch floor")

    // Before you leave: all rooms scanned, one photo of the bedroom; back on the overview.
    tap(app.buttons["overview.skippedRooms"])
    tap(app.buttons["checklist.allRoomsScanned"])
    tap(app.buttons["checklist.takePhoto"])
    tap(app.buttons["photo.shutter"], timeout: 20)
    tap(app.buttons["photo.direction.N"])
    tap(app.buttons["photo.subject.general"])
    tap(app.buttons["photo.doneWithPhotos"])
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 15))
    shot("S11 Before you leave")
    goBack()
    let review = app.buttons["overview.review"]
    waitForLabel(review, "Review the package")
    review.tap()

    // Package ready: the sketch measurements and the mesh in the file list, no RoomPlan file.
    XCTAssertTrue(app.staticTexts["Package ready"].waitForExistence(timeout: 30))
    let packageFloor = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'package.floor.'")
    ).firstMatch
    XCTAssertTrue(packageFloor.waitForExistence(timeout: 90), "the plan is built")
    let raw = element("package.floor.floor-1.raw")
    XCTAssertTrue(raw.waitForExistence(timeout: 10))
    XCTAssertTrue(raw.label.contains("sketch measurements · capture model"), raw.label)
    XCTAssertFalse(raw.label.contains("RoomPlan"), raw.label)
    let meshes = element("package.floor.floor-1.meshes")
    XCTAssertTrue(meshes.exists, "mesh.glb, mesh.obj and mesh.mtl")
    XCTAssertTrue(meshes.label.contains("Mesh GLB"), meshes.label)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "compass: not needed for a sketch")
      ).firstMatch.exists)
    waitFor("Seal and upload is enabled", timeout: 60) { app.buttons["package.seal"].isEnabled }
    shot("S12 Package ready, sketch capture")
  }
}
