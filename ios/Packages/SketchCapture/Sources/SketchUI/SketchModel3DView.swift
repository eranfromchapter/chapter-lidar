#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import MeshExport
  import SceneKit
  import SketchMesh
  import SwiftUI
  import UIKit

  /// The 3D preview of a capture without LiDAR (spec F16 2, 5): the solver's model extruded by
  /// `SketchMesh` (walls to the ceiling, openings cut, furniture as coloured blocks, the floor
  /// and walls coloured), drawn by SceneKit with the mesh's vertex colours, soft light and a
  /// slight isometric camera from the front-right, on a soft neutral ground. Drag to turn it,
  /// pinch to zoom; the ceilings face down, so the camera from above sees into the rooms.
  public struct SketchModel3DView: UIViewRepresentable {
    let mesh: TriangleMesh
    let accessibilityText: String

    public init(mesh: TriangleMesh, accessibilityText: String = "3D model of the rooms") {
      self.mesh = mesh
      self.accessibilityText = accessibilityText
    }

    /// The mesh of `model`, or nil when it has nothing to extrude.
    public static func mesh(of model: CaptureModel) -> TriangleMesh? {
      try? SketchMesh.extrude(model)
    }

    public func makeUIView(context: Context) -> SCNView {
      let view = FittingSceneView()
      view.backgroundColor = UIColor(ChapterTheme.Color.ground)
      view.antialiasingMode = .multisampling4X
      view.allowsCameraControl = true
      view.autoenablesDefaultLighting = false
      view.defaultCameraController.interactionMode = .orbitTurntable
      view.defaultCameraController.inertiaEnabled = true
      view.isAccessibilityElement = true
      view.accessibilityTraits = .image
      view.accessibilityLabel = accessibilityText
      view.accessibilityIdentifier = "sketchPhoto.model3D"
      context.coordinator.show(mesh, in: view)
      return view
    }

    public func updateUIView(_ view: SCNView, context: Context) {
      view.accessibilityLabel = accessibilityText
      if context.coordinator.mesh != mesh {
        context.coordinator.show(mesh, in: view)
      }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
      var mesh: TriangleMesh?

      func show(_ mesh: TriangleMesh, in view: SCNView) {
        self.mesh = mesh
        let built = SketchModelScene.make(mesh)
        view.scene = built.scene
        view.pointOfView = built.camera
        view.defaultCameraController.target = built.target
      }
    }
  }

  /// An SCNView whose camera's field of view runs along its narrower side, so the model fits a
  /// tall full-screen view as well as a wide card.
  final class FittingSceneView: SCNView {
    override func layoutSubviews() {
      super.layoutSubviews()
      let direction: SCNCameraProjectionDirection =
        bounds.width < bounds.height ? .horizontal : .vertical
      if let camera = pointOfView?.camera, camera.projectionDirection != direction {
        camera.projectionDirection = direction
      }
    }
  }

  /// The SceneKit scene of a sketch mesh: flat-shaded triangles (each with its face normal),
  /// the mesh's vertex colours (warm white where it has none), an ambient and a soft
  /// directional light with a soft shadow, and the camera.
  enum SketchModelScene {
    /// Warm white for a mesh without colours.
    static let plain = SIMD3<Float>(0.95, 0.93, 0.89)

    static func make(_ mesh: TriangleMesh) -> (scene: SCNScene, camera: SCNNode, target: SCNVector3) {
      let scene = SCNScene()
      let node = SCNNode(geometry: geometry(mesh))
      scene.rootNode.addChildNode(node)

      let bounds = mesh.bounds ?? (SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1))
      let centre: SIMD3<Float> = (bounds.min + bounds.max) * 0.5
      let extent: SIMD3<Float> = bounds.max - bounds.min
      let radius: Float = max(simd_length(extent) * 0.5, 0.5)
      let target = SCNVector3(centre.x, centre.y * 0.5, centre.z)

      let ambient = SCNNode()
      ambient.light = SCNLight()
      ambient.light?.type = .ambient
      ambient.light?.intensity = 550
      ambient.light?.color = UIColor(white: 1, alpha: 1)
      scene.rootNode.addChildNode(ambient)

      let sun = SCNNode()
      let light = SCNLight()
      light.type = .directional
      light.intensity = 750
      light.castsShadow = true
      light.shadowMode = .deferred
      light.shadowRadius = 8
      light.shadowSampleCount = 8
      light.shadowColor = UIColor(white: 0, alpha: 0.22)
      sun.light = light
      sun.eulerAngles = SCNVector3(-1.05, 0.6, 0)
      scene.rootNode.addChildNode(sun)

      // A slight isometric view: from the front-right (+X, +Z: plan up is −Z), about 50° above.
      let camera = SCNNode()
      let lens = SCNCamera()
      lens.fieldOfView = 34
      lens.zNear = 0.05
      lens.zFar = Double(radius * 20)
      camera.camera = lens
      let azimuth: Float = .pi / 5
      let elevation: Float = 0.9
      // The bounding sphere fits the field of view (along the view's narrower side).
      let distance: Float = radius / sin(lens.fieldOfView.degreesToRadiansFloat / 2) * 1.1
      let horizontal: Float = distance * cos(elevation)
      camera.position = SCNVector3(
        target.x + horizontal * sin(azimuth), target.y + distance * sin(elevation),
        target.z + horizontal * cos(azimuth))
      camera.look(at: target)
      scene.rootNode.addChildNode(camera)
      return (scene, camera, target)
    }

    /// One vertex per triangle corner with the triangle's normal, so every face is flat.
    static func geometry(_ mesh: TriangleMesh) -> SCNGeometry {
      var positions: [SCNVector3] = []
      var normals: [SCNVector3] = []
      var colours: [Float] = []
      positions.reserveCapacity(mesh.indices.count)
      normals.reserveCapacity(mesh.indices.count)
      colours.reserveCapacity(mesh.indices.count * 3)
      let hasColours = mesh.colors.count == mesh.positions.count
      var corner = 0
      while corner + 2 < mesh.indices.count {
        let ids = [Int(mesh.indices[corner]), Int(mesh.indices[corner + 1]), Int(mesh.indices[corner + 2])]
        corner += 3
        guard ids.allSatisfy({ $0 < mesh.positions.count }) else { continue }
        let a = mesh.positions[ids[0]]
        let b = mesh.positions[ids[1]]
        let c = mesh.positions[ids[2]]
        let cross: SIMD3<Float> = simd_cross(b - a, c - a)
        let length: Float = simd_length(cross)
        let normal: SIMD3<Float> = length > 0 ? cross / length : SIMD3<Float>(0, 1, 0)
        for id in ids {
          let p = mesh.positions[id]
          positions.append(SCNVector3(p.x, p.y, p.z))
          normals.append(SCNVector3(normal.x, normal.y, normal.z))
          let colour: SIMD3<Float>
          if hasColours {
            let rgb = mesh.colors[id]
            colour = SIMD3<Float>(Float(rgb.r) / 255, Float(rgb.g) / 255, Float(rgb.b) / 255)
          } else {
            colour = plain
          }
          colours += [colour.x, colour.y, colour.z]
        }
      }
      let colourData = colours.withUnsafeBufferPointer { Data(buffer: $0) }
      let colourSource = SCNGeometrySource(
        data: colourData, semantic: .color, vectorCount: positions.count, usesFloatComponents: true,
        componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
        dataStride: MemoryLayout<Float>.size * 3)
      let indices = (0..<Int32(positions.count)).map { $0 }
      let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
      let geometry = SCNGeometry(
        sources: [
          SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), colourSource,
        ],
        elements: [element])
      let material = SCNMaterial()
      material.lightingModel = .lambert
      material.diffuse.contents = UIColor.white
      material.isDoubleSided = false
      geometry.materials = [material]
      return geometry
    }
  }

  extension CGFloat {
    fileprivate var degreesToRadiansFloat: Float { Float(self) * .pi / 180 }
  }

  /// The 3D preview as a card: the model in a 280 pt well with the card's corner and border,
  /// "Drag to turn · pinch to zoom" under it.
  public struct SketchModel3DCard: View {
    let mesh: TriangleMesh
    let accessibilityText: String
    let height: CGFloat

    public init(mesh: TriangleMesh, accessibilityText: String = "3D model of the rooms", height: CGFloat = 280) {
      self.mesh = mesh
      self.accessibilityText = accessibilityText
      self.height = height
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionHeaderGap) {
        SketchModel3DView(mesh: mesh, accessibilityText: accessibilityText)
          .frame(height: height)
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius))
          .overlay(
            RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
              .strokeBorder(ChapterTheme.Color.line, lineWidth: ChapterTheme.Metric.cardBorder))
        Text("Drag to turn \u{00B7} pinch to zoom")
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.muted)
          .padding(.horizontal, ChapterTheme.Metric.sectionInset)
      }
    }
  }
#endif
