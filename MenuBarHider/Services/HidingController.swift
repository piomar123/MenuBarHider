import AppKit

protocol RunningAppsSource {
    var bundleIDs: [String] { get }
}

protocol TimerScheduler {
    func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> Cancellable
}

protocol Cancellable {
    func cancel()
}

/// Screen x of the two separators; nil when the item is not on screen.
struct SeparatorPositions {
    var separatorX: CGFloat?
    var leftSeparatorX: CGFloat?
    /// Where status items can sit on the screen showing `»`; nil when unknown.
    var bar: MenuBarSpace?
}

/// The stretch of a screen's menu bar open to status items: right of the notch, if any.
struct MenuBarSpace: Equatable {
    var minX: CGFloat
    var maxX: CGFloat
    var hasNotch: Bool

    var width: CGFloat { maxX - minX }
}

/// Owns the intent, the hidden set and the timers, and derives the restriction MenuBarAgent holds.
@MainActor
final class HidingController {
    enum State { case shown, hidden }

    /// Time for the freshly created separators to be laid out before the first scan.
    private static let launchSettleDelay: TimeInterval = 1.5
    private static let permissionPollInterval: TimeInterval = 2
    private static let hoverGraceDelay: TimeInterval = 0.5
    /// Time for the revealed items to be laid out before a rescan reads their positions.
    private static let rescanSettleDelay: TimeInterval = 0.6
    /// App launches come in bursts of helper processes; one reconcile per burst is enough.
    private static let runningAppsDebounce: TimeInterval = 1
    /// How often a due auto-hide re-checks whether the pointer has left the revealed items.
    static let autoHideHoverRecheck: TimeInterval = 1
    /// Room beside the notch that macOS keeps for its own overflow chevron, plus some slack.
    static let notchOverflowMargin: CGFloat = 40

    private let engine: HidingEngine
    private let items: MenuBarItemSource
    private let runningApps: RunningAppsSource
    private let extras: MenuExtraHost
    private let separators: () -> SeparatorPositions
    /// True while the pointer rests on the revealed items between `|` and `»`.
    private let pointerOverExpandedItems: () -> Bool
    private let scheduler: TimerScheduler
    let settings: Settings
    let isInApplications: Bool

    private(set) var state: State = .shown
    /// Expanded with the normally visible items hidden, because the whole bar does not fit
    /// beside the notch: macOS would move `|` and the leftmost icons into its overflow chevron.
    private(set) var isNarrow = false
    private(set) var hiddenSet: Set<String>
    private(set) var lastError: Error?
    /// Notification Center refuses to open while the restriction is active, and an already-open
    /// panel survives its return: the bar stays unrestricted while the pointer rests on the clock.
    var pointerOverClock = false {
        didSet { pointerOverClockChanged(from: oldValue) }
    }

    private var pendingHide: Cancellable?
    private var hoverGrace: Cancellable?
    private var appsChange: Cancellable?
    private var permissionPoll: Cancellable?
    private var observedBundleIDs: Set<String> = []

    var onChange: (() -> Void)?

    init(
        engine: HidingEngine,
        items: MenuBarItemSource,
        runningApps: RunningAppsSource,
        extras: MenuExtraHost,
        separators: @escaping () -> SeparatorPositions,
        pointerOverExpandedItems: @escaping () -> Bool = { false },
        isInApplications: Bool,
        settings: Settings,
        scheduler: TimerScheduler
    ) {
        self.engine = engine
        self.items = items
        self.runningApps = runningApps
        self.extras = extras
        self.separators = separators
        self.pointerOverExpandedItems = pointerOverExpandedItems
        self.isInApplications = isInApplications
        self.settings = settings
        self.scheduler = scheduler
        self.hiddenSet = settings.hiddenBundleIDs
    }

    var isEngineAvailable: Bool { engine.isAvailable }
    var isAccessibilityTrusted: Bool { items.isTrusted }
    var canHide: Bool { engine.isAvailable && isInApplications && items.isTrusted }
    var requiresClockHover: Bool { engine.requiresClockHover }
    var hidingMethod: HidingMethod { settings.hidingMethod }

    // MARK: - Intent

    func start() {
        lastError = engine.lastOperationError
        reconcileMenuExtras()
        onChange?()
        permissionPoll = scheduler.schedule(after: Self.launchSettleDelay) { [weak self] in
            self?.hideWhenPermitted()
        }
    }

    func toggle() {
        switch state {
        case .shown: hide()
        case .hidden: show(narrowIfCrowded: true)
        }
    }

    /// `narrowIfCrowded` lets an expand on a crowded notched screen hide the normally visible items.
    func show(narrowIfCrowded: Bool = false) {
        cancelPendingHide()
        isNarrow = narrowIfCrowded && state == .hidden && barIsTooWideForNotchedScreen
        Log.controller.error("show, narrow=\(self.isNarrow, privacy: .public)")
        state = .shown
        lastError = nil
        reconcile()
        onChange?()
        armAutoHide()
    }

    func restoreVisibility() {
        permissionPoll?.cancel()
        permissionPoll = nil
        isNarrow = false
        show()
        cancelPendingHide()
    }

    func hide() {
        cancelPendingHide()
        guard canHide else {
            lastError = engine.lastOperationError
            let reasons = "engine=\(engine.isAvailable) in /Applications=\(isInApplications) AX=\(items.isTrusted)"
            Log.controller.error("hide skipped: \(reasons, privacy: .public)")
            onChange?()
            return
        }
        refreshHiddenSet()
        state = .hidden
        isNarrow = false
        reconcile()
        onChange?()
    }

    /// While collapsed the bar is expanded first and re-collapsed; the collapse performs the scan.
    func rescan() {
        switch state {
        case .shown:
            refreshHiddenSet()
        case .hidden:
            show(narrowIfCrowded: true)
            cancelPendingHide()
            pendingHide = scheduler.schedule(after: Self.rescanSettleDelay) { [weak self] in
                self?.hide()
            }
        }
    }

    func setAutoHideSeconds(_ seconds: Int) {
        settings.autoHideSeconds = seconds
        guard state == .shown else { return }
        cancelPendingHide()
        armAutoHide()
    }

    func validateSystemSettingsAvailability() throws {
        guard let router = engine as? HidingEngineRouter else { throw NativeHidingFailure.unavailable }
        try router.validateSystemSettingsAvailability()
    }

    func setHidingMethod(_ method: HidingMethod) {
        guard let router = engine as? HidingEngineRouter else { return }
        let wasHidden = state == .hidden
        let selection = restrictionForHiddenItems
        show()
        guard lastError == nil else { return }
        do {
            try router.select(method, restriction: selection)
            pointerOverClock = false
            lastError = nil
            if wasHidden {
                cancelPendingHide()
                state = .hidden
                reconcile()
            }
        } catch {
            lastError = error
        }
        onChange?()
    }

    /// Call on every app launch or quit: the allow list must follow the running set.
    func runningAppsChanged() {
        appsChange?.cancel()
        appsChange = scheduler.schedule(after: Self.runningAppsDebounce) { [weak self] in
            self?.reconcile()
        }
    }

    @discardableResult
    func shutdown() -> Bool {
        cancelPendingHide()
        hoverGrace?.cancel()
        appsChange?.cancel()
        permissionPoll?.cancel()
        state = .shown
        engine.release()
        lastError = engine.lastOperationError
        reconcileMenuExtras()
        onChange?()
        return lastError == nil
    }

    // MARK: - Derivation

    private var restrictionForHiddenItems: MenuBarRestriction? {
        let hiddenApps = hiddenSet.filter { !MenuExtras.isExtra($0) && !SystemItems.isSystemSelection($0) }
        let hiddenSystemItems = SystemItems.hiddenIdentifiers(in: hiddenSet)
        guard !hiddenApps.isEmpty || !hiddenSystemItems.isEmpty else { return nil }
        return MenuBarRestriction(
            allowedBundleIDs: HiddenSet.allowList(
                running: runningApps.bundleIDs, hidden: hiddenApps, alwaysAllowed: SystemItems.alwaysAllowedBundleIDs),
            hiddenSystemItems: hiddenSystemItems)
    }

    private var desiredRestriction: MenuBarRestriction? {
        guard canHide, !(engine.requiresClockHover && pointerOverClock) else { return nil }
        switch state {
        case .hidden: return restrictionForHiddenItems
        case .shown: return isNarrow ? restrictionForVisibleItems : nil
        }
    }

    /// Narrow mode: hides what normally stays visible, so the hidden group fits beside the notch.
    private var restrictionForVisibleItems: MenuBarRestriction? {
        let visible = settings.visibleBundleIDs
        let visibleApps = visible.filter { !MenuExtras.isExtra($0) && !SystemItems.isSystemSelection($0) }
        let visibleSystemItems = SystemItems.hiddenIdentifiers(in: visible)
        guard !visibleApps.isEmpty || !visibleSystemItems.isEmpty else { return nil }
        return MenuBarRestriction(
            allowedBundleIDs: HiddenSet.allowList(
                running: runningApps.bundleIDs, hidden: visibleApps, alwaysAllowed: SystemItems.alwaysAllowedBundleIDs),
            hiddenSystemItems: visibleSystemItems)
    }

    /// Only the Compatibility method: System Settings would flip persistent switches on every expand.
    private var barIsTooWideForNotchedScreen: Bool {
        guard canHide, hidingMethod == .assessment, let bar = separators().bar, bar.hasNotch else { return false }
        return settings.expandedBarWidth > bar.width - Self.notchOverflowMargin
    }

    /// No pointerOverClock check: unloaded extras do not block Notification Center.
    private var desiredRemovedExtras: Set<String> {
        guard state == .hidden, canHide else { return [] }
        return hiddenSet.filter(MenuExtras.isExtra)
    }

    /// Idempotent: an unchanged allow list is not re-sent.
    private func reconcile() {
        let desired = desiredRestriction
        do {
            if let desired { try engine.validate(desired) }
        } catch {
            lastError = error
            return
        }
        reconcileMenuExtras()
        guard let desired else {
            engine.release()
            lastError = engine.lastOperationError
            return
        }
        guard desired != engine.requestedRestriction else { return }
        engine.restrict(desired) { [weak self] error in
            guard let self else { return }
            self.lastError = error
            if let error { Log.controller.error("restrict failed: \(error.localizedDescription)") }
            self.onChange?()
        }
    }

    private func reconcileMenuExtras() {
        let desired = desiredRemovedExtras
        var removed = settings.removedMenuExtraIDs
        for id in removed.subtracting(desired).sorted() where extras.restore(id) {
            removed.remove(id)
        }
        for id in desired.subtracting(removed).sorted() where extras.remove(id) {
            removed.insert(id)
        }
        settings.removedMenuExtraIDs = removed
    }

    private func refreshHiddenSet() {
        guard state == .shown, items.isTrusted else { return }
        let positions = separators()
        guard let separatorX = positions.separatorX else { return }
        let scanned = items.scan()
        let running = Set(runningApps.bundleIDs)
        let failed = scanned.failedBundleIDs.filter {
            MenuExtras.isExtra($0) || running.contains($0) || SystemItems.selectionIDs.contains($0)
        }
        .union(settings.removedMenuExtraIDs)
        // Items hidden by narrow mode report stale positions; they were visible and stay so.
        let previousVisible = settings.visibleBundleIDs
        let parked =
            isNarrow ? previousVisible.filter { running.contains($0) || SystemItems.isSystemSelection($0) } : []
        let observed = scanned.positions.filter { !failed.contains($0.bundleID) && !parked.contains($0.bundleID) }
        let observedNow = Set(observed.map(\.bundleID))
        observedBundleIDs = observedNow.union(observedBundleIDs.intersection(failed))
        engine.updateObservedBundleIDs(observedBundleIDs, failedBundleIDs: failed)
        // Icons that overflow a notched bar vanish from Accessibility: a running app keeps its state.
        let missing = hiddenSet.union(previousVisible).filter {
            running.contains($0) && !observedNow.contains($0) && !failed.contains($0) && !parked.contains($0)
        }
        let leftX = positions.leftSeparatorX.flatMap { x -> CGFloat? in
            guard let bar = positions.bar, bar.hasNotch, x < bar.minX else { return x }
            return nil  // `|` sits in the notch or the system's overflow chevron.
        }
        hiddenSet = HiddenSet.partition(items: observed, leftSeparatorX: leftX, separatorX: separatorX)
            .union(hiddenSet.intersection(failed))
            .union(hiddenSet.intersection(missing))
        settings.hiddenBundleIDs = hiddenSet
        let carried = previousVisible.filter { missing.contains($0) || parked.contains($0) }
        settings.visibleBundleIDs = observedNow.union(carried).subtracting(hiddenSet)
        if !isNarrow { recordExpandedWidth(positions, leftX: leftX, overflowed: !missing.isEmpty) }
        let dump = observed.map { "\($0.bundleID)@\(Int($0.x))" }
        let left = positions.leftSeparatorX.map { "\($0)" } ?? "none"
        let space = positions.bar.map { "\(Int($0.minX))-\(Int($0.maxX)) notch=\($0.hasNotch)" } ?? "none"
        Log.controller.error(
            """
            scan: sep=\(separatorX) left=\(left, privacy: .public) bar=\(space, privacy: .public) \
            narrow=\(self.isNarrow, privacy: .public) items=\(dump, privacy: .public) \
            missing=\(missing.sorted(), privacy: .public) hidden=\(self.hiddenSet.sorted(), privacy: .public) \
            width=\(self.settings.expandedBarWidth, privacy: .public)
            """)
    }

    /// The width `|` through the screen edge needs, so a later expand can tell whether it fits beside the notch.
    private func recordExpandedWidth(_ positions: SeparatorPositions, leftX: CGFloat?, overflowed: Bool) {
        guard let bar = positions.bar else { return }
        var width = leftX.map { bar.maxX - $0 } ?? settings.expandedBarWidth
        if bar.hasNotch && (overflowed || leftX == nil && positions.leftSeparatorX != nil) {
            width = max(width, bar.width + 1)
        }
        settings.expandedBarWidth = width
    }

    private func pointerOverClockChanged(from previous: Bool) {
        guard previous != pointerOverClock else { return }
        hoverGrace?.cancel()
        if pointerOverClock {
            reconcile()
        } else {
            hoverGrace = scheduler.schedule(after: Self.hoverGraceDelay) { [weak self] in
                self?.reconcile()
            }
        }
    }

    private func hideWhenPermitted() {
        guard state == .shown, isEngineAvailable, isInApplications else {
            if let error = engine.lastOperationError {
                lastError = error
                onChange?()
            }
            return
        }
        if isAccessibilityTrusted {
            hide()
        } else {
            Log.controller.error("waiting for Accessibility permission")
            permissionPoll = scheduler.schedule(after: Self.permissionPollInterval) { [weak self] in
                self?.hideWhenPermitted()
            }
        }
    }

    private func armAutoHide() {
        let seconds = settings.autoHideSeconds
        guard seconds > 0 else { return }
        armAutoHide(after: TimeInterval(seconds))
    }

    /// A due auto-hide waits while the pointer is over the revealed items, so they never vanish
    /// from under it; it fires on the first check after the pointer leaves.
    private func armAutoHide(after seconds: TimeInterval) {
        pendingHide = scheduler.schedule(after: seconds) { [weak self] in
            guard let self else { return }
            if self.pointerOverExpandedItems() {
                self.armAutoHide(after: Self.autoHideHoverRecheck)
            } else {
                self.hide()
            }
        }
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }
}

// MARK: - Default implementations

struct DispatchTimerScheduler: TimerScheduler {
    func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return item
    }
}

extension DispatchWorkItem: Cancellable {}

struct WorkspaceRunningApps: RunningAppsSource {
    var bundleIDs: [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    }
}
