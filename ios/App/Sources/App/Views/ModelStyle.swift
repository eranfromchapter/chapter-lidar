import SceneKit
import UIKit

/// Styles a RoomPlan parametric USDZ for an object view: flat-shaded faces (RoomPlan's meshes
/// carry no usable normals, so every face lit the same and the model looked flat white), a colour
/// per kind of element, soft key and fill light with shadows, and a camera at a three-quarter view.
enum ModelStyle {
  /// The colour of an element, from its node name in the export (`Wall3`, `Door0`, `Storage12`).
  static func color(for name: String) -> UIColor {
    let kind = name.replacingOccurrences(of: "[0-9_]+$", with: "", options: .regularExpression)
      .lowercased()
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
      UIColor(red: r, green: g, blue: b, alpha: 1)
    }
    switch kind {
    case "wall": return rgb(0.93, 0.92, 0.90)
    case "floor": return rgb(0.80, 0.75, 0.68)
    case "door": return rgb(0.60, 0.47, 0.35)
    case "window": return rgb(0.63, 0.75, 0.86)
    case "opening": return rgb(0.86, 0.84, 0.80)
    case "bed", "sofa", "chair", "table": return rgb(0.66, 0.69, 0.80)
    case "storage": return rgb(0.80, 0.73, 0.62)
    case "refrigerator", "oven", "stove", "dishwasher", "washerdryer", "television", "fireplace":
      return rgb(0.64, 0.65, 0.68)
    case "toilet", "sink", "bathtub": return rgb(0.88, 0.92, 0.95)
    case "stairs": return rgb(0.72, 0.68, 0.62)
    default: return rgb(0.75, 0.75, 0.75)
    }
  }

  /// A copy of `geometry` as separate triangles, each with its own face normal.
  static func flatShaded(_ geometry: SCNGeometry) -> SCNGeometry? {
    guard let source = geometry.sources(for: .vertex).first else { return nil }
    let stride = source.dataStride, offset = source.dataOffset, count = source.vectorCount
    let bytesPerComponent = source.bytesPerComponent
    guard source.componentsPerVector >= 3, source.usesFloatComponents else { return nil }
    var points: [SIMD3<Float>] = []
    points.reserveCapacity(count)
    source.data.withUnsafeBytes { raw in
      for i in 0..<count {
        let base = i * stride + offset
        if bytesPerComponent == 4 {
          points.append(SIMD3(raw.load(fromByteOffset: base, as: Float.self),
                              raw.load(fromByteOffset: base + 4, as: Float.self),
                              raw.load(fromByteOffset: base + 8, as: Float.self)))
        } else {
          points.append(SIMD3(Float(raw.load(fromByteOffset: base, as: Double.self)),
                              Float(raw.load(fromByteOffset: base + 8, as: Double.self)),
                              Float(raw.load(fromByteOffset: base + 16, as: Double.self))))
        }
      }
    }
    var positions: [SCNVector3] = []
    var normals: [SCNVector3] = []
    for element in geometry.elements where element.primitiveType == .triangles {
      let indexCount = element.primitiveCount * 3
      var indices: [Int] = []
      indices.reserveCapacity(indexCount)
      element.data.withUnsafeBytes { raw in
        for i in 0..<indexCount {
          switch element.bytesPerIndex {
          case 1: indices.append(Int(raw.load(fromByteOffset: i, as: UInt8.self)))
          case 2: indices.append(Int(raw.load(fromByteOffset: i * 2, as: UInt16.self)))
          default: indices.append(Int(raw.load(fromByteOffset: i * 4, as: UInt32.self)))
          }
        }
      }
      for t in Swift.stride(from: 0, to: indices.count - 2, by: 3) {
        guard indices[t] < count, indices[t + 1] < count, indices[t + 2] < count else { continue }
        let a = points[indices[t]], b = points[indices[t + 1]], c = points[indices[t + 2]]
        var n = simd_cross(b - a, c - a)
        let length = simd_length(n)
        if length < 1e-12 { continue }
        n /= length
        for p in [a, b, c] {
          positions.append(SCNVector3(p.x, p.y, p.z))
          normals.append(SCNVector3(n.x, n.y, n.z))
        }
      }
    }
    guard !positions.isEmpty else { return nil }
    let element = SCNGeometryElement(
      indices: (0..<Int32(positions.count)).map { $0 }, primitiveType: .triangles)
    return SCNGeometry(
      sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
      elements: [element])
  }

  static func apply(to scene: SCNScene, background: UIColor) -> SCNNode {
    scene.background.contents = background
    scene.rootNode.enumerateHierarchy { node, _ in
      guard let geometry = node.geometry else { return }
      let styled = flatShaded(geometry) ?? geometry
      let material = SCNMaterial()
      material.lightingModel = .lambert
      material.diffuse.contents = color(for: node.name ?? "")
      material.isDoubleSided = true
      styled.materials = [material]
      node.geometry = styled
      node.castsShadow = true
    }
    let (low, high) = scene.rootNode.boundingBox
    let center = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
    let size = max(high.x - low.x, high.y - low.y, high.z - low.z, 0.5)

    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light!.type = .ambient
    ambient.light!.intensity = 520
    ambient.light!.color = UIColor(red: 1, green: 0.98, blue: 0.95, alpha: 1)
    scene.rootNode.addChildNode(ambient)

    let key = SCNNode()
    key.light = SCNLight()
    key.light!.type = .directional
    key.light!.intensity = 850
    key.light!.castsShadow = true
    key.light!.shadowMode = .deferred
    key.light!.shadowSampleCount = 16
    key.light!.shadowRadius = 4
    key.light!.shadowColor = UIColor(white: 0, alpha: 0.28)
    key.light!.orthographicScale = CGFloat(size)
    key.light!.automaticallyAdjustsShadowProjection = true
    key.position = SCNVector3(center.x - size, center.y + size * 2, center.z + size * 0.6)
    key.look(at: center)
    scene.rootNode.addChildNode(key)

    let fill = SCNNode()
    fill.light = SCNLight()
    fill.light!.type = .directional
    fill.light!.intensity = 380
    fill.position = SCNVector3(center.x + size, center.y + size, center.z - size)
    fill.look(at: center)
    scene.rootNode.addChildNode(fill)

    // Fit the model's bounding sphere across the screen width (the phone is portrait), seen
    // from a three-quarter view about 55 degrees above the floor, so the near walls hide little.
    let dx = high.x - low.x, dy = high.y - low.y, dz = high.z - low.z
    let radius = Float((dx * dx + dy * dy + dz * dz).squareRoot() / 2)
    let fieldOfView: Float = 42
    let distance = radius / sinf(fieldOfView / 2 * .pi / 180) * 0.88
    let direction = simd_normalize(SIMD3<Float>(0.62, 1.25, 0.62))
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera!.projectionDirection = .horizontal
    camera.camera!.fieldOfView = CGFloat(fieldOfView)
    camera.camera!.zNear = 0.01
    camera.camera!.zFar = Double(distance + radius * 4)
    camera.camera!.screenSpaceAmbientOcclusionIntensity = 0.8
    camera.camera!.screenSpaceAmbientOcclusionRadius = 0.25
    camera.position = SCNVector3(
      Float(center.x) + direction.x * distance, Float(center.y) + direction.y * distance,
      Float(center.z) + direction.z * distance)
    camera.look(at: center)
    scene.rootNode.addChildNode(camera)
    return camera
  }
}
