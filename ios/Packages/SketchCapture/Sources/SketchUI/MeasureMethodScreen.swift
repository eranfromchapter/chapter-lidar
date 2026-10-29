#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import SketchEntry
  import SwiftUI

  /// Step 2 of 5, How do you want to measure? (spec F15 2): walk the rooms with the camera
  /// (recommended, the default on every phone that tracks the camera) or enter the
  /// measurements from a sketch (the F14 screens follow, unchanged). For the walk it also asks
  /// the floor or area name, what is walked and the units, as step 2 of a scan does. Continue
  /// hands the choice to the host (`onContinue`).
  public struct MeasureMethodScreen: View {
    @Bindable var model: MeasureMethodModel
    let caption: String
    let onContinue: @MainActor () -> Void

    public init(
      model: MeasureMethodModel, caption: String = "Step 2 of 5",
      onContinue: @escaping @MainActor () -> Void
    ) {
      self.model = model
      self.caption = caption
      self.onContinue = onContinue
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          methodSection
          if model.method == .walk {
            floorSection
          }
        }
        .sketchContent()
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(MeasureMethodText.title)
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(model.continueTitle) { onContinue() }
          .buttonStyle(.chapter(.primary))
          .disabled(!model.canContinue)
          .accessibilityIdentifier("walkthrough.method.continue")
      }
    }

    private var methodSection: some View {
      ChapterSection(
        header: MeasureMethodText.question,
        footer:
          "Walking gives every capture the same plans and 3D model: each tap is measured by the "
          + "phone's motion tracking. Tape one long wall on the next screen to check the scale."
      ) {
        NavigationRow(
          title: MeasureMethodText.walkTitle,
          subtitle: model.canWalk ? MeasureMethodText.walkSubtitle : MeasureMethodText.walkUnsupported,
          status: model.method == .walk ? RowStatus(.done, "Chosen") : nil
        ) {
          model.choose(.walk)
        }
        .disabled(!model.canWalk)
        .accessibilityIdentifier("walkthrough.method.walk")
        NavigationRow(
          title: MeasureMethodText.sketchTitle, subtitle: MeasureMethodText.sketchSubtitle,
          status: model.method == .sketch ? RowStatus(.done, "Chosen") : nil
        ) {
          model.choose(.sketch)
        }
        .accessibilityIdentifier("walkthrough.method.sketch")
      }
    }

    private var floorSection: some View {
      ChapterSection(
        header: "Floor or area",
        footer: "Walk one room at a time and close each room on its first corner."
      ) {
        TextFieldRow(
          label: "Name", text: $model.floorLabel, prompt: "Floor 1",
          accessibilityLabel: "Floor or area"
        )
        .submitLabel(.done)
        .accessibilityIdentifier("walkthrough.floorName")
        SketchSegmentedRow(
          label: "What you are walking", selection: $model.mode,
          options: [
            .init(CaptureMode.room, SketchText.modeTitle(.room), accessibilityIdentifier: "walkthrough.mode.room"),
            .init(.floor, SketchText.modeTitle(.floor), accessibilityIdentifier: "walkthrough.mode.floor"),
          ])
        SketchSegmentedRow(
          label: "Units",
          selection: Binding<DisplayUnitSystem?>(
            get: { model.displayUnits }, set: { if let value = $0 { model.displayUnits = value } }),
          options: [
            .init(DisplayUnitSystem.imperial, "Feet and inches", accessibilityIdentifier: "walkthrough.units.imperial"),
            .init(.metric, "Millimetres", accessibilityIdentifier: "walkthrough.units.metric"),
          ])
      }
    }
  }
#endif
