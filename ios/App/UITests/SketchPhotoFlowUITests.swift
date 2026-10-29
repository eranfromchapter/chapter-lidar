import XCTest

/// "Photograph a sketch" (spec F16, AC5) end to end in the Debug replay mode: Captures home →
/// Capture without LiDAR → New capture → How do you want to measure? (Photograph a sketch, the
/// default) → Photograph the sketch (the fixture photo stands in for the camera) → Reading your
/// sketch… (the in-process station answers the bundled reading of a 4 x 3 m bedroom with a
/// door, a window, a bed and a wardrobe, no written dimensions) → One length (wall 1 is
/// 13' 1.5") → Check with the 3D preview and the plan → Finish floor → photos → overview (the
/// floor's viewer: View in 3D) → Before you leave → Package ready lists the sketch read by Claude and the mesh. Every screen is
/// attached as a screenshot. Main-actor isolated, as XCUIAutomation is.
@MainActor
final class SketchPhotoFlowUITests: XCTestCase {
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

  // MARK: AC5

  func testASketchPhotoReachesPackageReadyWithA3DPreview() {
    launch()

    XCTAssertTrue(app.staticTexts["Captures"].waitForExistence(timeout: 30))
    let withoutLidar = app.buttons["captures.sketchCapture"]
    XCTAssertTrue(withoutLidar.waitForExistence(timeout: 10))
    shot("P01 Captures")
    withoutLidar.tap()

    // New capture, step 1 of 5.
    XCTAssertTrue(app.staticTexts["New capture"].waitForExistence(timeout: 10))
    tap(app.buttons["capture.project"])
    tap(button("UI test visit"))
    tap(app.switches["capture.addressConfirmed"])
    waitForLabel(app.buttons["capture.continue"], "Continue")
    tap(app.buttons["capture.continue"])

    // How do you want to measure? Photograph a sketch: first, recommended, chosen.
    XCTAssertTrue(app.staticTexts["How to measure"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 2 of 5"].exists)
    let photo = app.buttons["walkthrough.method.photo"]
    XCTAssertTrue(photo.exists)
    XCTAssertTrue(photo.label.contains("Photograph a sketch"), photo.label)
    XCTAssertTrue(photo.label.contains("Chosen"), photo.label)
    XCTAssertLessThan(photo.frame.minY, app.buttons["walkthrough.method.walk"].frame.minY, "first")
    XCTAssertEqual(app.textFields["walkthrough.floorName"].value as? String, "Floor 1")
    waitForLabel(app.buttons["walkthrough.method.continue"], "Photograph the sketch")
    shot("P02 How do you want to measure, photo")
    tap(app.buttons["walkthrough.method.continue"])

    // Photograph the sketch: the camera (the fixture photo in the replay mode).
    XCTAssertTrue(app.staticTexts["Photograph the sketch"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Step 3 of 5"].exists)
    shot("P03 Photograph the sketch")
    tap(app.buttons["sketchPhoto.source.camera"])

    // Reading your sketch…: the photo, the spinner and Cancel while the station reads.
    XCTAssertTrue(element("sketchPhoto.reading").waitForExistence(timeout: 10), "the reading screen")
    XCTAssertTrue(app.buttons["sketchPhoto.cancel"].exists)
    XCTAssertTrue(element("sketchPhoto.photo").exists, "the photo is shown")
    XCTAssertTrue(app.staticTexts["Step 4 of 5"].exists)
    shot("P04 Reading your sketch")

    // One length: the sketch has no written dimensions. Wall 1 of the bedroom is 13' 1.5".
    XCTAssertTrue(app.staticTexts["One length"].waitForExistence(timeout: 30), "the one-length step")
    XCTAssertTrue(element("sketchPhoto.plan").exists, "the drawn plan")
    let lengthContinue = app.buttons["sketchPhoto.length.continue"]
    XCTAssertEqual(lengthContinue.label, "Tap a wall on the plan")
    tapRevealed("sketchPhoto.wall.0-0")
    waitForLabel(lengthContinue, "Enter the wall's length")
    enter("13' 1.5\"", into: "sketchPhoto.length")
    XCTAssertEqual(element("sketchPhoto.length.stored").label, "4,001 mm · 13' 1.5\"")
    waitForLabel(lengthContinue, "Continue")
    shot("P05 One length")
    lengthContinue.tap()

    // Check: the 3D preview on top, the plan, Limited (every other length is estimated).
    XCTAssertTrue(app.buttons["sketch.finish"].waitForExistence(timeout: 15), "the Check screen")
    XCTAssertTrue(app.staticTexts["Check"].exists)
    XCTAssertTrue(app.staticTexts["Step 5 of 5"].exists)
    let model3D = element("sketchPhoto.model3D")
    XCTAssertTrue(model3D.waitForExistence(timeout: 10), "the 3D preview")
    XCTAssertTrue(element("sketch.plan").exists, "the plan")
    XCTAssertLessThan(model3D.frame.minY, element("sketch.plan").frame.minY, "3D on top")
    let status = element("sketch.status")
    waitFor("the solver says Limited") { status.exists && status.label.contains("Limited") }
    XCTAssertFalse(element("sketch.solveError").exists)
    shot("P06 Check with the 3D preview")
    let finish = app.buttons["sketch.finish"]
    waitFor("Finish floor enabled") { finish.isEnabled }
    reveal(finish)
    finish.tap()

    // Photos, then the overview: the floor row says sketch.
    let coverage = element("photo.coverage")
    XCTAssertTrue(coverage.waitForExistence(timeout: 30), "the photo step")
    waitForLabel(coverage, "Still needs a photo: Bedroom")
    shot("P07 Viewfinder after the sketch photo")
    tap(app.buttons["photo.done"])
    let floorRow = app.buttons["overview.floor.floor-1"]
    XCTAssertTrue(floorRow.waitForExistence(timeout: 15), "the overview")
    XCTAssertTrue(floorRow.label.contains("sketch"), floorRow.label)
    shot("P08 Capture overview, sketch photo floor")

    // The floor's viewer offers View in 3D for a sketch floor: the extruded, coloured model.
    floorRow.tap()
    let view3D = app.buttons["scan.view3D"]
    XCTAssertTrue(view3D.waitForExistence(timeout: 15), "View in 3D on the floor's viewer")
    waitFor("View in 3D enabled") { view3D.isEnabled }
    reveal(view3D)
    view3D.tap()
    XCTAssertTrue(element("sketchPhoto.model3D").waitForExistence(timeout: 10), "the 3D model")
    shot("P08b View in 3D")
    tap(app.buttons["scan.sketch3D.close"])
    XCTAssertTrue(view3D.waitForExistence(timeout: 10))
    goBack()
    XCTAssertTrue(floorRow.waitForExistence(timeout: 15), "back on the overview")

    // Before you leave: all rooms scanned, one photo of the bedroom; back on the overview.
    tap(app.buttons["overview.skippedRooms"])
    tap(app.buttons["checklist.allRoomsScanned"])
    tap(app.buttons["checklist.takePhoto"])
    tap(app.buttons["photo.shutter"], timeout: 20)
    tap(app.buttons["photo.direction.N"])
    tap(app.buttons["photo.subject.general"])
    tap(app.buttons["photo.doneWithPhotos"])
    XCTAssertTrue(app.staticTexts["Before you leave"].waitForExistence(timeout: 15))
    shot("P09 Before you leave")
    goBack()
    let review = app.buttons["overview.review"]
    waitForLabel(review, "Review the package")
    review.tap()

    // Package ready: the sketch read by Claude, the measurements and the mesh.
    XCTAssertTrue(app.staticTexts["Package ready"].waitForExistence(timeout: 30))
    let packageFloor = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'package.floor.'")
    ).firstMatch
    XCTAssertTrue(packageFloor.waitForExistence(timeout: 90), "the plan is built")
    let raw = element("package.floor.floor-1.raw")
    XCTAssertTrue(raw.waitForExistence(timeout: 10))
    XCTAssertTrue(raw.label.contains("sketch read by Claude + measurements"), raw.label)
    let meshes = element("package.floor.floor-1.meshes")
    XCTAssertTrue(meshes.exists, "mesh.glb, mesh.obj and mesh.mtl")
    XCTAssertTrue(meshes.label.contains("Mesh GLB"), meshes.label)
    waitFor("Seal and upload is enabled", timeout: 60) { app.buttons["package.seal"].isEnabled }
    shot("P10 Package ready, sketch photo")
  }
}
