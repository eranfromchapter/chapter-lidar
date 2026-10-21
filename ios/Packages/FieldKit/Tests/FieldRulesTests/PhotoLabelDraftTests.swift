import CaptureContract
import FieldRules
import Foundation
import XCTest

/// AC5 (phone-field §9.3): the saved label records whether the direction is the compass's
/// untouched suggestion (compass) or the operator's choice (manual).
final class PhotoLabelDraftTests: XCTestCase {
  private func complete(_ draft: PhotoLabelDraft) -> PhotoLabelDraft {
    var draft = draft
    draft.room = "Kitchen"
    draft.subject = .cabinetry
    return draft
  }

  func testACompassSuggestionKeptIsSavedAsCompass() throws {
    var draft = complete(PhotoLabelDraft())
    draft.applyCompass(.east)
    XCTAssertEqual(draft.direction, .east)
    XCTAssertEqual(draft.directionSource, .compass)
    XCTAssertEqual(draft.compassSuggestion, .east)
    XCTAssertFalse(draft.directionTouched)
    XCTAssertEqual(draft.directionCaptionSuffix, "\u{00B7} from the compass, change if wrong")
    let labels = try XCTUnwrap(draft.labels(takenAt: Fixtures.t0))
    XCTAssertEqual(labels.direction, .east)
    XCTAssertEqual(labels.directionSource, .compass)
  }

  func testTappingThePrefilledSegmentKeepsTheCompassSource() throws {
    var draft = complete(PhotoLabelDraft())
    draft.applyCompass(.east)
    draft.chooseDirection(.east)
    XCTAssertEqual(draft.directionSource, .compass)
    XCTAssertFalse(draft.directionTouched)
    XCTAssertEqual(try XCTUnwrap(draft.labels(takenAt: Fixtures.t0)).directionSource, .compass)
  }

  func testChoosingAnotherDirectionIsManualEvenWhenChangedBack() throws {
    var draft = complete(PhotoLabelDraft())
    draft.applyCompass(.east)
    draft.chooseDirection(.north)
    XCTAssertEqual(draft.direction, .north)
    XCTAssertEqual(draft.directionSource, .manual)
    XCTAssertTrue(draft.directionTouched)
    XCTAssertEqual(draft.directionCaptionSuffix, "\u{00B7} chosen by you")
    XCTAssertEqual(try XCTUnwrap(draft.labels(takenAt: Fixtures.t0)).directionSource, .manual)
    // Back to the suggestion: the operator chose it, so it is theirs.
    draft.chooseDirection(.east)
    XCTAssertEqual(try XCTUnwrap(draft.labels(takenAt: Fixtures.t0)).directionSource, .manual)
  }

  func testNoReadingLeavesTheDirectionToTheOperator() throws {
    var draft = complete(PhotoLabelDraft())
    draft.applyCompass(nil)
    XCTAssertNil(draft.direction)
    XCTAssertNil(draft.directionSource)
    XCTAssertEqual(draft.missing, [.direction])
    XCTAssertEqual(draft.directionCaptionSuffix, "\u{00B7} no compass reading, choose one")
    draft.chooseDirection(.west)
    XCTAssertEqual(draft.directionCaptionSuffix, "\u{00B7} chosen by you")
    XCTAssertEqual(try XCTUnwrap(draft.labels(takenAt: Fixtures.t0)).directionSource, .manual)
  }

  func testANewReadingResetsTheChoice() {
    var draft = complete(PhotoLabelDraft())
    draft.applyCompass(.east)
    draft.chooseDirection(.north)
    draft.applyCompass(.south)
    XCTAssertEqual(draft.direction, .south)
    XCTAssertEqual(draft.savedDirectionSource, .compass)
  }

  func testTheNextPhotoKeepsTheRoomOnly() {
    var draft = complete(PhotoLabelDraft())
    draft.applyCompass(.east)
    let next = draft.forNextPhoto()
    XCTAssertEqual(next.room, "Kitchen")
    XCTAssertNil(next.direction)
    XCTAssertNil(next.subject)
    XCTAssertNil(next.directionSource)
    XCTAssertNil(next.compassSuggestion)
    XCTAssertEqual(next.missing, [.direction, .subject])
  }

  func testSevenSubjectsInTheDrawnOrder() {
    XCTAssertEqual(
      PhotoSubject.primaryChoices.map(\.chipTitle),
      ["Opening", "Cabinetry", "Ceiling", "Fixture", "Defect", "General", "Equipment"])
    XCTAssertEqual(Set(PhotoSubject.primaryChoices), Set(PhotoSubject.allCases))
    XCTAssertEqual(
      PhotoDirection.allCases.map(\.spokenTitle), ["North", "East", "South", "West"])
  }

  /// The labels with `directionSource` are a valid manifest 1.1.0 photo entry.
  func testLabelsValidateAgainstTheManifestPhotoSchema() throws {
    let schema = try JSONSchemaValidator.loadSchema(named: "manifest.schema.json")
    var draft = complete(PhotoLabelDraft())
    for suggestion in [PhotoDirection.east, nil] {
      draft.applyCompass(suggestion)
      if suggestion == nil { draft.chooseDirection(.west) }
      let labels = try XCTUnwrap(draft.labels(takenAt: Fixtures.t0))
      let data = try CaptureContractJSON.makeEncoder().encode(labels)
      XCTAssertEqual(try schema.validate(data: data, definition: "photo"), [])
    }
    // Without a source (1.0.0 labels) the entry is valid too, and the key is left out.
    let legacy = PackageManifest.PhotoLabels(
      room: "Kitchen", direction: .east, subject: .general, takenAt: Fixtures.t0)
    let data = try CaptureContractJSON.makeEncoder().encode(legacy)
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("directionSource"))
    XCTAssertEqual(try schema.validate(data: data, definition: "photo"), [])
  }
}
