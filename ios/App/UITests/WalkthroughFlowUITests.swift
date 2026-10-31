import XCTest

/// The AR walkthrough (spec F15, AC6) end to end in the Debug replay mode, where a scripted walk
/// of a 4 × 3 m bedroom stands in for ARKit (UITestWalkthroughBedroom.json): Captures home →
/// Capture without LiDAR → New capture → How do you want to measure? (Walk the rooms) → the AR
/// walk (name the room, four corners, the closing tap, the ceiling, a door with its head, a
/// window with its sill and head) → Done → Check the scale (wall 1 taped 13' 1.5") → Check
/// ("Complete") → Finish floor → photos → the overview's floor row says "walked" → Before you
/// leave → Package ready lists the walkthrough log and the mesh. Every screen is attached as a
/// screenshot. Main-actor isolated, as XCUIAutomation is.
@MainActor
final class WalkthroughFlowUITests: XCTestCase {
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

  private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(element)", file: file, line: line)
    var swipes = 0
    while !element.isHittable, swipes < 8 {
      app.swipeUp(velocity: .slow)
      swipes += 1
    }
    XCTAssertTrue(element.isHittable, "\(element) is not on screen", file: file, line: line)
  }

  /// Types a length into a field and closes the keyboard with Return (the tap is repeated
  /// until the keyboard is up).
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

  /// The instruction at the top of the AR screen.
  private var instruction: XCUIElement { element("walkthrough.instruction") }

  /// "+" once it is enabled (normal tracking and a point under the reticle); waits for the
  /// tap to land (the button's value counts the points tapped).
  private func plus(file: StaticString = #filePath, line: UInt = #line) {
    let button = app.buttons["walkthrough.tap"]
    XCTAssertTrue(button.waitForExistence(timeout: 10), file: file, line: line)
    waitFor("+ is enabled", timeout: 10, file: file, line: line) { button.isEnabled }
    let before = button.value as? String
    button.tap()
    waitFor("the tap landed", timeout: 10, file: file, line: line) {
      (button.value as? String) != before
    }
  }

  // MARK: AC6

  func testAWalkedBedroomReachesPackageReady() {
    launch()

    // Captures home: "Capture without LiDAR".
    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    let withoutLidar = app.buttons["captures.sketchCapture"]
    XCTAssertTrue(withoutLidar.waitForExistence(timeout: 10))
    XCTAssertEqual(withoutLidar.label, "Capture without LiDAR")
    shot("W01 Captures")
    withoutLidar.tap()

    // New capture, step 1 of 5: the HUB project and the address, no device gate.
    XCTAssertTrue(app.staticTexts["New capture"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 1 of 5"].exists)
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    tap(app.switches["capture.addressConfirmed"])
    waitForLabel(app.buttons["capture.continue"], "Continue")
    tap(app.buttons["capture.continue"])

    // How do you want to measure? Walk the rooms (the second option; the sketch photo is the
    // default, spec F16 2).
    XCTAssertTrue(app.staticTexts["How to measure"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 2 of 5"].exists)
    let walk = app.buttons["walkthrough.method.walk"]
    XCTAssertTrue(walk.exists)
    walk.tap()
    waitFor("the walk is chosen") { walk.label.contains("Chosen") }
    XCTAssertEqual(app.textFields["walkthrough.floorName"].value as? String, "Floor 1")
    waitForLabel(app.buttons["walkthrough.method.continue"], "Walk the rooms")
    shot("W02 How do you want to measure")
    tap(app.buttons["walkthrough.method.continue"])

    // The AR walk: the room card first.
    let card = element("walkthrough.room.card")
    XCTAssertTrue(card.waitForExistence(timeout: 15), "the room card")
    let name = app.textFields["walkthrough.room.name"]
    tap(name)
    name.typeText("Bedroom\n")
    tap(app.buttons["walkthrough.room.type.bedroom"])
    shot("W03 Walk, room card")
    tap(app.buttons["walkthrough.room.start"])
    waitFor("the card closes") { !card.exists }

    // Four floor corners, then the closing tap on the first.
    waitForLabel(instruction, "Point at a floor corner and tap +")
    XCTAssertEqual(element("walkthrough.room").label, "Bedroom")
    for _ in 0..<4 { plus() }
    waitForLabel(instruction, "Tap + on the first corner to close the room")
    let outline = element("walkthrough.outline")
    XCTAssertTrue(outline.label.contains("4 corners"), outline.label)
    shot("W04 Walk, four corners")
    plus()

    // The ceiling line, then a door (two jambs at the floor and its head) and a window (two
    // jambs, the sill and the head on the wall).
    waitForLabel(instruction, "Point where a wall meets the ceiling and tap +")
    plus()
    waitForLabel(instruction, "Add the doors, windows and openings, then the next room")
    tap(app.buttons["walkthrough.add.door"])
    waitForLabel(instruction, "Door: tap + where its left side meets the floor")
    for _ in 0..<3 { plus() }
    tap(app.buttons["walkthrough.add.window"])
    waitForLabel(instruction, "Window: point at its left side and tap +")
    plus()
    plus()
    waitForLabel(instruction, "Window: point at the sill and tap +")
    plus()
    plus()
    waitForLabel(instruction, "Add the doors, windows and openings, then the next room")
    shot("W05 Walk, openings added")
    let done = app.buttons["walkthrough.done"]
    waitFor("Done is enabled") { done.isEnabled }
    done.tap()

    // Check the scale, step 4 of 5: wall 1 taped 13' 1.5".
    XCTAssertTrue(app.staticTexts["Check the scale"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Step 4 of 5"].exists)
    let wall1 = app.buttons["walkthrough.scale.wall.room-1.0"]
    XCTAssertTrue(wall1.waitForExistence(timeout: 10))
    XCTAssertTrue(wall1.label.hasPrefix("Bedroom · wall 1 · 13' "), wall1.label)
    XCTAssertTrue(wall1.label.contains("walked"), wall1.label)
    wall1.tap()
    enter("13' 1.5\"", into: "walkthrough.scale.tape")
    let useLength = app.buttons["walkthrough.scale.continue"]
    waitForLabel(useLength, "Use this length")
    shot("W06 Check the scale")
    useLength.tap()

    // Check, step 5 of 5: the plan from the solver, "Complete", Finish floor.
    XCTAssertTrue(app.buttons["sketch.finish"].waitForExistence(timeout: 15), "the Check screen")
    XCTAssertTrue(app.staticTexts["Check"].exists)
    XCTAssertTrue(app.staticTexts["Step 5 of 5"].exists)
    let status = element("sketch.status")
    waitFor("the solver says Complete") { status.exists && status.label.contains("Complete") }
    XCTAssertTrue(element("sketch.plan").exists, "the Floorplan preview")
    XCTAssertFalse(element("sketch.solveError").exists)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label BEGINSWITH %@", "Scale checked with a tape on Bedroom wall 1")
      ).firstMatch.exists, "the converter's scale note")
    shot("W07 Check")
    let finish = app.buttons["sketch.finish"]
    waitFor("Finish floor enabled") { finish.isEnabled }
    finish.tap()

    // Photos, then the overview: the floor row reads "Floor 1 · … walked …".
    let coverage = element("photo.coverage")
    XCTAssertTrue(coverage.waitForExistence(timeout: 30), "the photo step")
    waitForLabel(coverage, "Still needs a photo: Bedroom")
    tap(app.buttons["photo.done"])
    let floorRow = app.buttons["overview.floor.floor-1"]
    XCTAssertTrue(floorRow.waitForExistence(timeout: 15), "the overview")
    XCTAssertTrue(floorRow.label.hasPrefix("Floor 1"), floorRow.label)
    XCTAssertTrue(floorRow.label.contains("Whole floor · walked · 1 room"), floorRow.label)
    let compass = app.buttons["overview.compass"]
    XCTAssertTrue(compass.label.contains("Not needed"), compass.label)
    let controls = app.buttons["overview.controls"]
    XCTAssertTrue(controls.label.contains("Measured by the AR walkthrough"), controls.label)
    shot("W08 Capture overview, walked floor")

    // Before you leave: all rooms covered, one photo of the bedroom; back on the overview.
    tap(app.buttons["overview.skippedRooms"])
    tap(app.buttons["checklist.allRoomsScanned"])
    tap(app.buttons["checklist.takePhoto"])
    tap(app.buttons["photo.shutter"], timeout: 20)
    tap(app.buttons["photo.direction.N"])
    tap(app.buttons["photo.subject.general"])
    tap(app.buttons["photo.doneWithPhotos"])
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 15))
    shot("W09 Before you leave")
    goBack()
    let review = app.buttons["overview.review"]
    waitForLabel(review, "Review the package")
    review.tap()

    // Package ready: the walkthrough log and the measurements, the mesh; no RoomPlan file.
    XCTAssertTrue(app.staticTexts["Package ready"].waitForExistence(timeout: 30))
    let packageFloor = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'package.floor.'")
    ).firstMatch
    XCTAssertTrue(packageFloor.waitForExistence(timeout: 90), "the plan is built")
    let raw = element("package.floor.floor-1.raw")
    XCTAssertTrue(raw.waitForExistence(timeout: 10))
    XCTAssertTrue(raw.label.contains("walkthrough log + measurements"), raw.label)
    XCTAssertFalse(raw.label.contains("RoomPlan"), raw.label)
    let meshes = element("package.floor.floor-1.meshes")
    XCTAssertTrue(meshes.exists, "mesh.glb, mesh.obj and mesh.mtl")
    XCTAssertTrue(meshes.label.contains("Mesh GLB"), meshes.label)
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "compass: not needed for a walkthrough")
      ).firstMatch.exists)
    waitFor("Seal and upload is enabled", timeout: 60) { app.buttons["package.seal"].isEnabled }
    shot("W10 Package ready, walked floor")
  }
}
