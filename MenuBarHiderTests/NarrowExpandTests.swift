import XCTest

@testable import MenuBarHider

/// Expanding on a notched screen where `|` through the clock does not fit beside the notch.
@MainActor
final class NarrowExpandTests: XCTestCase {
    private static let wide = MenuBarSpace(minX: 0, maxX: 1000, hasNotch: false)
    /// 600 pt beside the notch: an 800 pt expanded bar does not fit.
    private static let notched = MenuBarSpace(minX: 400, maxX: 1000, hasNotch: true)

    private var engine: FakeEngine!
    private var items: FakeItems!
    private var running: FakeRunning!
    private var settings: Settings!
    private var suiteName: String!
    private var leftSeparatorX: CGFloat? = 200
    private var bar: MenuBarSpace? = NarrowExpandTests.wide
    private var controller: HidingController!

    override func setUp() {
        super.setUp()
        engine = FakeEngine()
        engine.acceptsSystemItems = true
        items = FakeItems()
        running = FakeRunning()
        suiteName = "NarrowExpandTests-\(UUID().uuidString)"
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        settings.autoHideSeconds = 0
        controller = HidingController(
            engine: engine, items: items, runningApps: running, extras: FakeExtras(),
            separators: { [unowned self] in
                SeparatorPositions(separatorX: 500, leftSeparatorX: self.leftSeparatorX, bar: self.bar)
            },
            isInApplications: true, settings: settings, scheduler: ManualScheduler())
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// `pinned | middle » right wifi`, collapsed on the wide screen: the expanded bar is 800 pt.
    private func collapseOnWideScreen() {
        running.bundleIDs = ["pinned", "middle", "right", "noicon"]
        items.positions = [
            .init(bundleID: "pinned", x: 100), .init(bundleID: "middle", x: 300),
            .init(bundleID: "right", x: 600), .init(bundleID: "system-item:wifi", x: 700),
        ]
        controller.hide()
    }

    private var allowed: Set<String> { Set(engine.appliedAllowList ?? []) }

    func testWideScanRecordsExpandedWidthAndVisibleItems() {
        collapseOnWideScreen()

        XCTAssertEqual(controller.hiddenSet, ["middle"])
        XCTAssertEqual(settings.expandedBarWidth, 800)
        XCTAssertEqual(settings.visibleBundleIDs, ["pinned", "right", "system-item:wifi"])
    }

    func testExpandOnNotchedScreenHidesVisibleItemsWhenBarDoesNotFit() {
        collapseOnWideScreen()
        bar = Self.notched

        controller.toggle()

        XCTAssertEqual(controller.state, .shown)
        XCTAssertTrue(controller.isNarrow)
        XCTAssertTrue(allowed.isSuperset(of: ["middle", "noicon", "com.apple.controlcenter"]))
        XCTAssertFalse(allowed.contains("pinned"))
        XCTAssertFalse(allowed.contains("right"))
        XCTAssertEqual(engine.lastRestriction?.hiddenSystemItems, [6])
    }

    func testExpandOnWideScreenStaysNormal() {
        collapseOnWideScreen()

        controller.toggle()

        XCTAssertFalse(controller.isNarrow)
        XCTAssertNil(engine.appliedAllowList)
    }

    func testExpandOnNotchedScreenStaysNormalWhenBarFits() {
        leftSeparatorX = 600
        running.bundleIDs = ["middle"]
        items.positions = [.init(bundleID: "middle", x: 700)]
        bar = MenuBarSpace(minX: 0, maxX: 1000, hasNotch: false)
        controller.hide()
        XCTAssertEqual(settings.expandedBarWidth, 400)
        bar = Self.notched

        controller.toggle()

        XCTAssertFalse(controller.isNarrow)
        XCTAssertNil(engine.appliedAllowList)
    }

    func testSystemSettingsMethodNeverExpandsNarrow() {
        collapseOnWideScreen()
        settings.hidingMethod = .systemSettings
        bar = Self.notched

        controller.toggle()

        XCTAssertFalse(controller.isNarrow)
    }

    func testCollapseFromNarrowIgnoresStalePositionsOfItemsItHid() {
        collapseOnWideScreen()
        bar = Self.notched
        controller.toggle()
        // The items narrow mode hid report stale positions, here inside the hidden group.
        items.positions = [
            .init(bundleID: "pinned", x: 450), .init(bundleID: "middle", x: 470),
            .init(bundleID: "right", x: 480), .init(bundleID: "system-item:wifi", x: 490),
        ]
        leftSeparatorX = 440

        controller.toggle()

        XCTAssertEqual(controller.state, .hidden)
        XCTAssertFalse(controller.isNarrow)
        XCTAssertEqual(controller.hiddenSet, ["middle"])
        XCTAssertEqual(settings.visibleBundleIDs, ["pinned", "right", "system-item:wifi"])
        XCTAssertEqual(settings.expandedBarWidth, 800, "a narrow layout says nothing about the full width")
    }

    func testItemDraggedRightOfSeparatorInNarrowModeBecomesVisible() {
        collapseOnWideScreen()
        bar = Self.notched
        controller.toggle()
        items.positions = [.init(bundleID: "middle", x: 520)]
        leftSeparatorX = 440

        controller.toggle()
        controller.toggle()

        XCTAssertTrue(controller.hiddenSet.isEmpty)
        XCTAssertFalse(allowed.contains("middle"), "now a visible item, hidden while expanding narrow")
    }

    func testRestoreVisibilityEndsNarrowMode() {
        collapseOnWideScreen()
        bar = Self.notched
        controller.toggle()

        controller.restoreVisibility()

        XCTAssertFalse(controller.isNarrow)
        XCTAssertNil(engine.appliedAllowList)
    }

    func testSeparatorInsideNotchIsIgnoredAndBarMarkedTooWide() {
        bar = Self.notched
        running.bundleIDs = ["pinned", "middle", "zoom"]
        // `|` and `zoom` overflowed into the system's chevron: `|` reports a position inside the notch.
        leftSeparatorX = 120
        items.positions = [.init(bundleID: "middle", x: 450), .init(bundleID: "right", x: 600)]

        controller.hide()

        XCTAssertEqual(controller.hiddenSet, ["middle"])
        XCTAssertGreaterThan(settings.expandedBarWidth, 600)
        controller.toggle()
        XCTAssertTrue(controller.isNarrow)
    }

    func testRunningItemMissingFromScanKeepsItsState() {
        collapseOnWideScreen()
        controller.show()
        // `middle` overflowed into the system's chevron and is absent from the scan.
        items.positions = [.init(bundleID: "pinned", x: 100), .init(bundleID: "right", x: 600)]

        controller.hide()

        XCTAssertEqual(controller.hiddenSet, ["middle"])
        XCTAssertFalse(allowed.contains("middle"))
    }

    func testItemOfQuitAppIsNotKept() {
        collapseOnWideScreen()
        controller.show()
        running.bundleIDs = ["pinned", "right"]
        items.positions = [.init(bundleID: "pinned", x: 100), .init(bundleID: "right", x: 600)]

        controller.hide()

        XCTAssertTrue(controller.hiddenSet.isEmpty)
    }
}
