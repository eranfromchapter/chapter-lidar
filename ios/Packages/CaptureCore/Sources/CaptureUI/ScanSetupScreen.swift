#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureContract
  import CaptureCore
  import ChapterUI
  import SwiftUI

  /// Step 2 of 3, What are you scanning? (phone-capture §3.3, artboard 2b-2, compass §5.1): the
  /// floor or area name (prefilled "Floor N"), the mode, the rooms that will not be scanned, the
  /// coverage notes and the compass pre-check. Start scan moves the model to the live scan
  /// (`model.step == .scanning`), which the host presents full screen. The compass never blocks
  /// Start scan. When adding a floor, the caption is the project title.
  public struct ScanSetupScreen: View {
    @Bindable var model: CaptureFlowModel
    @State private var showsAddRoom = false
    @State private var newRoomName = ""
    @State private var newRoomReason = ""
    @State private var readAgain: Task<Void, Never>?

    public init(model: CaptureFlowModel) {
      self.model = model
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          ChapterCard {
            TextFieldRow(
              label: "Name", text: $model.draft.floorLabel, prompt: "Floor 1",
              accessibilityLabel: "Floor or area"
            )
            .submitLabel(.done)
            .accessibilityIdentifier("capture.floorName")
            ChapterSegmented(
              "Mode", selection: $model.draft.mode,
              options: CaptureMode.allCases.map {
                .init($0, CaptureText.modeTitle($0), accessibilityIdentifier: "capture.mode.\($0.rawValue)")
              }
            )
            // Three columns: beyond AX1 "Exterior" would break inside the word.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, ChapterTheme.Metric.rowPadding)
            .padding(.vertical, ChapterTheme.Metric.navigationRowVerticalPadding)
          }
          skippedRooms
          ChapterSection(header: "Coverage notes") {
            TextAreaRow(
              text: $model.draft.coverageNotes, prompt: "Optional",
              accessibilityLabel: "Coverage notes"
            )
            .accessibilityIdentifier("capture.coverageNotes")
          }
          ChapterSection(header: "Compass") {
            CompassRow(state: model.compassPrecheck, now: { model.now() }) {
              readAgain?.cancel()
              readAgain = Task { await model.readCompassAgain() }
            }
          } footer: {
            CompassFootnotes(isLocationOff: model.isLocationOff) { model.openLocationSettings() }
          }
        }
        .captureContent(top: ChapterTheme.Metric.contentTopCompact)
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("What are you scanning?")
      .navigationBarTitleDisplayMode(.large)
      .captureNavigationCaption(model.scanSetupCaption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(model.startScanTitle) { Task { await model.startScan() } }
          .buttonStyle(.chapter(.primary))
          .disabled(!model.canStartScan)
          .accessibilityIdentifier("capture.startScan")
      }
      .alert("Add a room you cannot scan", isPresented: $showsAddRoom) {
        TextField("Room name", text: $newRoomName)
        TextField("Reason (for example locked)", text: $newRoomReason)
        Button("Cancel", role: .cancel) {}
        Button("Add") { model.addOmittedRoom(name: newRoomName, reason: newRoomReason) }
      } message: {
        Text("A room you will not scan, for example a locked closet.")
      }
      // The pre-check runs on appear and stops when the screen goes (cancelled with the task).
      .task { await model.readCompassAgain() }
      .onDisappear { readAgain?.cancel() }
    }

    private var skippedRooms: some View {
      ChapterSection(header: "Rooms you will not scan") {
        ForEach(Array(model.draft.omittedRooms.enumerated()), id: \.offset) { index, room in
          RemovableRow(
            title: room.name, subtitle: room.reason.map(CaptureText.capitalizedFirst),
            removeAccessibilityIdentifier: "capture.removeSkippedRoom.\(index)"
          ) {
            model.removeOmittedRoom(at: index)
          }
        }
        AddRow(title: "Add a room you cannot scan") {
          newRoomName = ""
          newRoomReason = ""
          showsAddRoom = true
        }
        .accessibilityIdentifier("capture.addSkippedRoom")
      }
    }
  }
#endif
