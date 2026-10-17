#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import SwiftUI

  private typealias Palette = ChapterTokens.Palette
  private typealias Space = ChapterTokens.Space
  private typealias Radius = ChapterTokens.Radius
  private typealias Control = ChapterTokens.Control
  private typealias Typo = ChapterTokens.Typography

  /// Step 3 of 3: live scan with counts and Pause / Finish floor
  /// (docs/waves/design/snapshot.html#screen-capture, panel 3). `preview` is the live camera and
  /// RoomPlan view; the design draws it as a placeholder inside the panel.
  struct LiveScanScreen<Preview: View>: View {
    @Bindable var model: CaptureFlowModel
    @ViewBuilder var preview: () -> Preview

    var body: some View {
      VStack(spacing: Space.s4) {
        HStack {
          Text(model.scanTitle).font(Typo.sans(15)).foregroundStyle(Palette.surface)
          Spacer()
          Text(model.elapsedText).font(Typo.mono(15)).foregroundStyle(Palette.surface)
            .accessibilityLabel("Elapsed \(model.elapsedText)")
        }

        ZStack {
          preview()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sheet))
          VStack {
            HStack {
              Text(model.instruction.message)
                .font(Typo.sans(15, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.chip))
              Spacer()
            }
            Spacer()
            HStack(spacing: Space.s2) {
              count(model.progress.counts.walls, "walls")
              count(model.progress.counts.doors, "doors")
              count(model.progress.counts.windows, "windows")
              count(model.progress.counts.rooms, "rooms")
            }
          }
          .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.scanPanel, in: RoundedRectangle(cornerRadius: Radius.sheet))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet).stroke(Palette.scanPanelBorder, lineWidth: 1))

        HStack(spacing: Space.s2) {
          Circle().fill(Palette.surface).frame(width: 10, height: 10)
          Text("LiDAR depth and mesh recording · originals saved on this phone")
            .font(Typo.caption).foregroundStyle(Palette.scanCaption)
          Spacer(minLength: 0)
        }

        if let message = model.errorMessage {
          Text("■ \(message)").font(Typo.caption).foregroundStyle(Palette.surface)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(spacing: Space.s3) {
          Button {
            Task { await model.togglePause() }
          } label: {
            Text(model.isPaused ? "Resume" : "Pause")
              .font(Typo.body).foregroundStyle(Palette.surface)
              .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
              .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.surface, lineWidth: 1))
          }
          .buttonStyle(.plain)
          Button {
            Task { await model.finishFloor() }
          } label: {
            Text("Finish floor")
              .font(Typo.headline).foregroundStyle(Palette.ink)
              .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
              .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, Space.s2)
      .padding(.bottom, Space.s4)
    }

    private func count(_ value: Int, _ label: String) -> some View {
      VStack(spacing: 2) {
        Text("\(value)").font(Typo.sans(22, weight: .semibold)).foregroundStyle(Palette.surface)
        Text(label).font(Typo.sans(12)).foregroundStyle(Palette.scanCaption)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
    }
  }
#endif
