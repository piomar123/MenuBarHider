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

    /// `pinned | middle » right wifi`, collapsed on the wide screen: the expanded bar is 900 pt,
    /// 600 of them outside `|`…`»`.
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
        XCTAssertEqual(settings.expandedBarWidth, 900)
        XCTAssertEqual(settings.visibleExtent, 600)
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
        leftSeparatorX = 450
        running.bundleIDs = ["right"]
        items.positions = [.init(bundleID: "right", x: 700)]
        controller.hide()
        XCTAssertEqual(settings.expandedBarWidth, 550)
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
        XCTAssertEqual(settings.expandedBarWidth, 660, "the 60 pt group plus the 600 pt narrow mode hid")
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

    func testSeparatorInsideNotchIsIgnored() {
        bar = Self.notched
        running.bundleIDs = ["middle"]
        leftSeparatorX = 120
        items.positions = [.init(bundleID: "middle", x: 450), .init(bundleID: "right", x: 600)]

        controller.hide()

        XCTAssertEqual(controller.hiddenSet, ["middle"])
    }

    func testFrontmostAppMenusPastTheNotchLeaveTooLittleRoom() {
        leftSeparatorX = 460
        running.bundleIDs = ["right"]
        items.positions = [.init(bundleID: "right", x: 700)]
        controller.hide()
        XCTAssertEqual(settings.expandedBarWidth, 540)

        bar = MenuBarSpace(minX: 400, maxX: 1000, hasNotch: true, menuOverlap: 100)
        controller.toggle()

        XCTAssertTrue(controller.isNarrow, "600 pt beside the notch, 100 of them taken by menus")
    }

    func testNarrowModeEndsOnceTheGroupFitsAgain() {
        collapseOnWideScreen()
        bar = Self.notched
        controller.toggle()
        XCTAssertTrue(controller.isNarrow)
        // Menus no longer overlap and the group shrank: 60 + 600 does not fit 560 yet, so widen the screen.
        bar = MenuBarSpace(minX: 300, maxX: 1000, hasNotch: true)
        leftSeparatorX = 480
        items.positions = [.init(bundleID: "middle", x: 490)]

        controller.toggle()
        XCTAssertEqual(settings.expandedBarWidth, 620)
        controller.toggle()

        XCTAssertFalse(controller.isNarrow, "620 pt fits 700 - 40")
    }

    func testOverflowRaisesTheReserve() {
        collapseOnWideScreen()
        // The prediction says 900 pt fit in 990 beside this notch, yet `middle` overflowed.
        bar = MenuBarSpace(minX: 0, maxX: 990, hasNotch: true)
        controller.toggle()
        XCTAssertFalse(controller.isNarrow)
        items.positions = [.init(bundleID: "right", x: 600)]
        leftSeparatorX = 560

        controller.toggle()

        XCTAssertEqual(controller.hiddenSet, ["middle"])
        XCTAssertEqual(settings.notchReserve, 98)
        XCTAssertEqual(settings.expandedBarWidth, 900, "`|` is unreliable while icons overflow")
        controller.toggle()
        XCTAssertTrue(controller.isNarrow)
    }

    func testLearnedReserveIsCapped() {
        collapseOnWideScreen()
        bar = MenuBarSpace(minX: 0, maxX: 1200, hasNotch: true)
        controller.toggle()
        items.positions = [.init(bundleID: "right", x: 600)]

        controller.toggle()

        XCTAssertEqual(settings.notchReserve, 100, "308 needed, capped")
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
