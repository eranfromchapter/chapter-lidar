#if canImport(ARKit) && canImport(SwiftUI) && os(iOS)
  import ARKit
  import CaptureContract
  import ChapterUI
  import SceneKit
  import SwiftUI
  import UIKit

  /// The camera of the walkthrough with its AR overlay (spec F15 2): an `ARSCNView` showing the
  /// live session, with SceneKit nodes for every tapped point (corners white, openings in the
  /// ready green, ceiling points in the limited amber), the floor line of each wall, and a
  /// small disc where + would add the next point.
  struct WalkthroughARView: UIViewRepresentable {
    let session: LiveWalkthroughSession
    let markers: [WalkthroughMarker]
    let lines: [(start: Vec3, end: Vec3)]
    let target: Vec3?
    let canTap: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARSCNView {
      let view = ARSCNView(frame: .zero)
      view.session = session.arSession
      view.automaticallyUpdatesLighting = true
      view.rendersCameraGrain = false
      view.scene = SCNScene()
      view.scene.rootNode.addChildNode(context.coordinator.overlay)
      view.scene.rootNode.addChildNode(context.coordinator.targetNode)
      view.accessibilityElementsHidden = true
      return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
      context.coordinator.update(markers: markers, lines: lines)
      context.coordinator.moveTarget(to: target, canTap: canTap)
    }

    @MainActor
    final class Coordinator {
      let overlay = SCNNode()
      let targetNode: SCNNode
      private var drawn: (markers: [WalkthroughMarker], lines: [[Double]])?

      init() {
        let disc = SCNCylinder(radius: 0.03, height: 0.002)
        disc.firstMaterial?.diffuse.contents = UIColor.white
        disc.firstMaterial?.lightingModel = .constant
        targetNode = SCNNode(geometry: disc)
        targetNode.isHidden = true
      }

      func update(markers: [WalkthroughMarker], lines: [(start: Vec3, end: Vec3)]) {
        let flat = lines.map { [$0.start.x, $0.start.y, $0.start.z, $0.end.x, $0.end.y, $0.end.z] }
        if let drawn, drawn.markers == markers, drawn.lines == flat { return }
        drawn = (markers, flat)
        overlay.childNodes.forEach { $0.removeFromParentNode() }
        for marker in markers {
          let sphere = SCNSphere(radius: 0.025)
          sphere.firstMaterial?.diffuse.contents = Self.colour(marker.kind)
          sphere.firstMaterial?.lightingModel = .constant
          let node = SCNNode(geometry: sphere)
          node.simdPosition = SIMD3(Float(marker.point.x), Float(marker.point.y), Float(marker.point.z))
          overlay.addChildNode(node)
        }
        for line in lines {
          if let node = Self.line(from: line.start, to: line.end) { overlay.addChildNode(node) }
        }
      }

      func moveTarget(to target: Vec3?, canTap: Bool) {
        guard let target else {
          targetNode.isHidden = true
          return
        }
        targetNode.isHidden = false
        targetNode.simdPosition = SIMD3(Float(target.x), Float(target.y), Float(target.z))
        targetNode.opacity = canTap ? 0.9 : 0.4
      }

      static func colour(_ kind: WalkthroughMarker.Kind) -> UIColor {
        switch kind {
        case .corner, .wallTap: return .white
        case .opening: return UIColor(ChapterTheme.Color.ready)
        case .ceiling: return UIColor(ChapterTheme.Color.limited)
        }
      }

      /// A thin white bar between two points.
      static func line(from a: Vec3, to b: Vec3) -> SCNNode? {
        let start = SIMD3(Float(a.x), Float(a.y), Float(a.z))
        let end = SIMD3(Float(b.x), Float(b.y), Float(b.z))
        let vector = end - start
        let length = simd_length(vector)
        guard length > 0.01 else { return nil }
        let cylinder = SCNCylinder(radius: 0.008, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = UIColor.white
        cylinder.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (start + end) / 2
        // SCNCylinder runs along +Y: turn +Y onto the line.
        let up = SIMD3<Float>(0, 1, 0)
        let direction = vector / length
        let axis = simd_cross(up, direction)
        let axisLength = simd_length(axis)
        if axisLength > 1e-6 {
          let angle = acos(max(-1, min(1, simd_dot(up, direction))))
          node.simdOrientation = simd_quatf(angle: angle, axis: axis / axisLength)
        }
        return node
      }
    }
  }
#endif
