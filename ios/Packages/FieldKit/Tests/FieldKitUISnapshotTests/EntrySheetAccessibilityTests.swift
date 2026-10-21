#if canImport(UIKit) && os(iOS)
  import ChapterUI
  @testable import FieldKitUI
  import FieldRules
  import SwiftUI
  import UIKit
  import XCTest

  /// The accessibility identifiers of the Field controls entry sheet's bar, read from the
  /// accessibility tree SwiftUI gives UIKit (the tree XCUITest queries): Cancel (`entry.cancel`),
  /// Save (`entry.save`) and the title are three distinct elements, and `entry.sheet` names one
  /// node only, the sheet's container, so it no longer covers the bar's buttons (it did when the
  /// identifier was set on the sheet's stack, which hands it to every element inside).
  @MainActor
  final class EntrySheetAccessibilityTests: XCTestCase {
    private typealias F = SnapshotFixtures

    /// One node of the accessibility tree: an element, or a container that has an identifier.
    struct Node: Equatable, CustomStringConvertible {
      var identifier: String
      var label: String
      var isElement: Bool
      var isButton = false
      var isHeader = false

      var description: String {
        "\(isElement ? "element" : "container") \(identifier.isEmpty ? "-" : identifier) "
          + "\"\(label)\"\(isButton ? " button" : "")\(isHeader ? " header" : "")"
      }
    }

    // SwiftUI builds its accessibility tree only for an accessibility client. Nothing asks in the
    // bare xctest process, so these tests turn accessibility automation on (as XCUITest does for
    // the app it drives) through libAccessibility, and off again after each test.
    private typealias SetAutomationEnabled = @convention(c) (Bool) -> Void
    private static let setAutomationEnabled: SetAutomationEnabled? = {
      guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
        let symbol = dlsym(library, "_AXSSetAutomationEnabled")
      else { return nil }
      return unsafeBitCast(symbol, to: SetAutomationEnabled.self)
    }()

    override func setUp() async throws {
      try await super.setUp()
      let enable = try XCTUnwrap(Self.setAutomationEnabled, "libAccessibility")
      enable(true)
    }

    override func tearDown() async throws {
      Self.setAutomationEnabled?(false)
      try await super.tearDown()
    }

    /// The accessibility tree of `view` hosted in a window of the iPhone 17 Pro screen, in order.
    private func nodes<V: View>(
      of view: V, dynamicTypeSize: DynamicTypeSize = .large
    ) -> [Node] {
      let host = UIHostingController(
        rootView: view.chapterRoot().environment(\.dynamicTypeSize, dynamicTypeSize))
      let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 402, height: 874)))
      window.rootViewController = host
      window.isHidden = false
      defer {
        window.isHidden = true
        window.rootViewController = nil
      }
      for _ in 0..<3 {
        window.setNeedsLayout()
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      }
      let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
      var found: [Node] = []
      var seen = Set<ObjectIdentifier>()
      func visit(_ object: NSObject, depth: Int) {
        guard depth < 60, seen.insert(ObjectIdentifier(object)).inserted else { return }
        // SwiftUI's nodes answer accessibilityIdentifier without declaring
        // UIAccessibilityIdentification.
        let identifier =
          object.responds(to: identifierSelector)
          ? (object.perform(identifierSelector)?.takeUnretainedValue() as? String) ?? "" : ""
        if object.isAccessibilityElement || !identifier.isEmpty {
          let traits = object.accessibilityTraits
          found.append(
            Node(
              identifier: identifier, label: object.accessibilityLabel ?? "",
              isElement: object.isAccessibilityElement, isButton: traits.contains(.button),
              isHeader: traits.contains(.header)))
        }
        var children: [NSObject] = []
        if let list = object.accessibilityElements as? [NSObject], !list.isEmpty {
          children = list
        } else if let view = object as? UIView {
          children = view.subviews
        }
        for child in children { visit(child, depth: depth + 1) }
      }
      visit(window, depth: 0)
      return found
    }

    private func sheet(isReadOnly: Bool = false) throws -> ControlEntrySheet {
      let model = try F.controlsModel(policy: .standard, withScan: true, isReadOnly: isReadOnly)
      model.focus(rowId: "floor-1.distanceA")
      let entry = try XCTUnwrap(model.entry)
      return ControlEntrySheet(entry: entry, onCancel: {}, onSave: {}, onEditRecorded: { _ in })
    }

    /// The bar's elements and the nodes named `entry.sheet`.
    private func assertBar(
      _ found: [Node], cancelTitle: String, hasSave: Bool, title: String,
      file: StaticString = #filePath, line: UInt = #line
    ) {
      let description = found.map(\.description).joined(separator: "\n")
      XCTAssertEqual(
        found.filter { $0.identifier == "entry.sheet" },
        [Node(identifier: "entry.sheet", label: "", isElement: false)],
        "entry.sheet names the sheet's container only:\n\(description)", file: file, line: line)
      XCTAssertEqual(
        found.filter { $0.label == cancelTitle },
        [Node(identifier: "entry.cancel", label: cancelTitle, isElement: true, isButton: true)],
        description, file: file, line: line)
      let save = Node(identifier: "entry.save", label: "Save", isElement: true, isButton: true)
      XCTAssertEqual(
        found.filter { $0.label == "Save" }, hasSave ? [save] : [], description, file: file,
        line: line)
      let titles = found.filter(\.isHeader)
      XCTAssertEqual(titles.map(\.label), [title], description, file: file, line: line)
      XCTAssertEqual(
        titles.first.map { ["entry.sheet", "entry.cancel", "entry.save"].contains($0.identifier) },
        false, "the title is its own element:\n\(description)", file: file, line: line)
    }

    func testCancelSaveAndTheTitleAreDistinct() throws {
      assertBar(
        nodes(of: try sheet()), cancelTitle: "Cancel", hasSave: true, title: "Long distance A")
    }

    /// At accessibility text sizes the title takes a row of its own under the buttons.
    func testCancelSaveAndTheTitleAreDistinctAtAX3() throws {
      assertBar(
        nodes(of: try sheet(), dynamicTypeSize: .accessibility3), cancelTitle: "Cancel",
        hasSave: true, title: "Long distance A")
    }

    /// Sealed: Close and no Save.
    func testTheReadOnlySheetHasCloseAndNoSave() throws {
      assertBar(
        nodes(of: try sheet(isReadOnly: true)), cancelTitle: "Close", hasSave: false,
        title: "Long distance A")
    }
  }
#endif
