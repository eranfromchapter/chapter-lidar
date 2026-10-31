#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import SketchEntry
  import SketchUI
  import SwiftUI

  /// Step 4 of 5, Check the scale (spec F15 2, 3.5; recommended, not required): pick one walked
  /// wall, ideally a long one, tape it and type the length; every length of the floor is then
  /// scaled by tape / walked. Skip keeps the phone's own scale. Either way the Check follows.
  public struct WalkthroughScaleScreen: View {
    @Bindable var model: WalkthroughModel
    let caption: String

    public init(model: WalkthroughModel, caption: String = "Step 4 of 5") {
      self.model = model
      self.caption = caption
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          ChapterSection(
            header: "Wall to tape",
            footer:
              "Recommended: tape one long wall. Its length corrects the scale of the whole floor "
              + "to about 0.3 %; without it the scale is the phone's own, about 1 to 3 %."
          ) {
            ForEach(model.scaleWalls) { wall in
              NavigationRow(
                title: wall.title(units: model.displayUnits),
                status: model.scaleWallId == wall.id ? RowStatus(.done, "Chosen") : nil
              ) {
                model.scaleWallId = wall.id
              }
              .accessibilityIdentifier("walkthrough.scale.wall.\(wall.roomId).\(wall.wallIndex)")
            }
          }
          if let wall = model.scaleWall {
            ChapterSection(
              header: "Tape length",
              footer: "Feet and inches (13' 1.5\") or millimetres, corner to corner at the floor."
            ) {
              SketchLengthRow(
                title: "\(wall.roomLabel) wall \(wall.wallIndex + 1)", field: $model.tape,
                identifier: "walkthrough.scale.tape", showsMeasuredChip: false)
            }
          }
        }
        .sketchContent()
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Check the scale")
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(model.canApplyScale ? "Use this length" : continueBlocker) { model.applyScale() }
          .buttonStyle(.chapter(.primary))
          .disabled(!model.canApplyScale)
          .accessibilityIdentifier("walkthrough.scale.continue")
        Button("Skip the scale check") { model.skipScale() }
          .buttonStyle(.chapter(.text))
          .accessibilityIdentifier("walkthrough.scale.skip")
      }
    }

    private var continueBlocker: String {
      model.scaleWall == nil ? "Choose a wall to tape" : "Type the tape length"
    }
  }

  /// Step 5 of 5, Check (spec F15 2): the F14 Check screen for the walked floor: the plan from
  /// the solver, the scale and the converter's notes, then the solver's, "Complete" or
  /// "Limited", Finish floor.
  public struct WalkthroughCheckScreen: View {
    @Bindable var model: WalkthroughModel
    let caption: String
    let onFinish: @MainActor () -> Void

    public init(
      model: WalkthroughModel, caption: String = "Step 5 of 5",
      onFinish: @escaping @MainActor () -> Void
    ) {
      self.model = model
      self.caption = caption
      self.onFinish = onFinish
    }

    public var body: some View {
      SketchCheckView(
        result: model.result, solveError: model.solveError,
        leadingNotes: model.notes
          + (model.scaleText == nil
            ? ["Scale from the phone's motion tracking only: no wall was taped."] : []),
        completenessWord: model.completenessWord, caption: caption,
        isFinishing: model.isFinishing, canFinish: model.canFinish, onFinish: onFinish)
    }
  }
#endif
