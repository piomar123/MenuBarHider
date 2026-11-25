import AppKit

@MainActor
final class ClockHoverMonitor {
    private static let menuBarStripHeight: CGFloat = 40

    private let clock = SystemMenuItems()
    private let isRelevant: () -> Bool
    private let wantsHover: () -> Bool
    private var monitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var isOverClock = false
    private var hoveredFrame: CGRect?

    /// Pointer on or off the clock, only while `isRelevant`: drives the Notification Center workaround.
    var onChange: ((Bool) -> Void)?
    /// The clock's frame while the pointer is on it, nil when it leaves; only while `wantsHover`.
    var onHover: ((CGRect?) -> Void)?

    init(isRelevant: @escaping () -> Bool, wantsHover: @escaping () -> Bool = { false }) {
        self.isRelevant = isRelevant
        self.wantsHover = wantsHover
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.update()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clock.invalidateCache()
                self?.update()
            }
        }
    }

    func update() {
        let location = NSEvent.mouseLocation
        let relevant = isRelevant()
        let wantsHover = wantsHover()
        let frame =
            (relevant || wantsHover) && Self.isInMenuBarStrip(location) ? clock.clockFrame(at: location) : nil
        let hovered = wantsHover ? frame : nil
        if hovered != hoveredFrame {
            hoveredFrame = hovered
            onHover?(hovered)
        }
        let over = relevant && frame != nil
        guard over != isOverClock else { return }
        isOverClock = over
        Log.ui.error("pointer over clock: \(over), position=(\(location.x), \(location.y))")
        onChange?(over)
    }

    private static func isInMenuBarStrip(_ location: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else { return false }
        return location.y > screen.frame.maxY - menuBarStripHeight
    }
}
