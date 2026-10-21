// UI-test mode. DEBUG ONLY: compiled only in the Debug configuration (`#if DEBUG`; ios/project.yml
// excludes `UITest*` files from Release builds), and run only with `-ChapterUITestV1Visits`.
#if DEBUG
  import AppCore
  import CaptureContract
  import FieldRules
  import Foundation
  import PackageCore
  import PhotoStore

  /// Visit folders as the v1 app left them on the owner's phone (no `visit.json`), made from the
  /// bundled box-room fixture before the Captures home first reads the disk:
  ///
  /// 1. scans only (the v1 app kept the capture record in memory until "Package ready");
  /// 2. scans, the photo and a "Package ready" draft, never sealed;
  /// 3. the same, sealed (its upload resumes at launch).
  ///
  /// The UI test checks that all three show up on the Captures home after the update.
  enum UITestV1Visits {
    static func seed(in visitsRoot: URL, fixture package: URL) throws {
      let decoder = CaptureContractJSON.makeDecoder()
      let register = package.appendingPathComponent(PackageFolder.sourceRegister.name)
      guard
        let visitFolder = try FileManager.default.contentsOfDirectory(
          at: register, includingPropertiesForKeys: nil
        ).first
      else { return }
      let record = try decoder.decode(
        CaptureRecord.self,
        from: Data(contentsOf: visitFolder.appendingPathComponent(PackageLayout.captureRecordFileName)))
      let manifest = try decoder.decode(
        PackageManifest.self, from: Data(contentsOf: visitFolder.appendingPathComponent("manifest.json")))

      // 1. Scans only.
      let scans = try VisitWorkspace.create(in: visitsRoot)
      try copyOriginals(of: record, from: package, to: scans)

      // 2. and 3. A draft, then a sealed package.
      for sealed in [false, true] {
        let workspace = try VisitWorkspace.create(in: visitsRoot)
        try copyOriginals(of: record, from: package, to: workspace)
        let store = try PhotoRecordStore(files: DiskPhotoFileStore(root: workspace.photosRoot))
        var photos: [PhotoRecord] = []
        for entry in manifest.files where entry.role == .photo {
          guard let captureId = entry.captureId, let areaKey = entry.areaKey, let labels = entry.photo
          else { continue }
          photos.append(
            try store.save(
              original: Data(contentsOf: url(package, entry.path)),
              capture: FieldControls.CaptureRef(captureId: captureId, areaKey: areaKey),
              labels: labels))
        }
        let controls = FieldControlsEditor(visitId: record.visitId).controls
        let plan = try VisitPackageBuilder(workspace: workspace, appVersion: "1.0.0")
          .plan(record: record, photos: photos, controls: controls)
        if sealed {
          _ = try PackageAssembler().assemble(
            plan.draft, at: workspace.packageURL(packageId: plan.draft.packageId.rawValue))
        }
      }
    }

    private static func copyOriginals(
      of record: CaptureRecord, from package: URL, to workspace: VisitWorkspace
    ) throws {
      for capture in record.captures {
        let path = "\(PackageFolder.originalExports.name)/\(capture.areaKey)/\(capture.captureId.rawValue)"
        let target = workspace.originalsRoot.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["roomplan.json", "depth-samples.bin"] {
          try FileManager.default.copyItem(
            at: url(package, "\(path)/\(name)"), to: target.appendingPathComponent(name))
        }
      }
    }

    private static func url(_ root: URL, _ path: String) -> URL {
      path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }
  }
#endif
