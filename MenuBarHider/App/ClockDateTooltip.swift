import AppKit

/// A small label with the weekday, date and week number under the clock while the pointer rests on it,
/// for a clock set to show the time only.
@MainActor
final class ClockDateTooltip {
    private static let delay: TimeInterval = 0.5
    private static let gap: CGFloat = 4
    private static let padding = CGSize(width: 8, height: 3)

    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var pending: DispatchWorkItem?

    /// The clock's frame while the pointer is on it, nil once it leaves.
    func hover(_ clockFrame: CGRect?) {
        pending?.cancel()
        pending = nil
        guard let clockFrame else {
            panel?.orderOut(nil)
            return
        }
        if panel?.isVisible == true {
            present(below: clockFrame)  // Moved to the other display's clock.
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.present(below: clockFrame) }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: item)
    }

    /// "Wed 25 Nov · W48", in the locale's own order; the week number follows the region's rules.
    nonisolated static func text(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return "\(formatter.string(from: date)) · W\(calendar.component(.weekOfYear, from: date))"
    }

    private func present(below clockFrame: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        label.stringValue = Self.text(for: Date())
        let text = label.fittingSize
        let size = CGSize(
            width: ceil(text.width) + 2 * Self.padding.width, height: ceil(text.height) + 2 * Self.padding.height)
        var origin = CGPoint(x: clockFrame.midX - size.width / 2, y: clockFrame.minY - Self.gap - size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(clockFrame) }) {
            origin.x = min(max(origin.x, screen.frame.minX + Self.gap), screen.frame.maxX - Self.gap - size.width)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        label.frame = CGRect(
            x: Self.padding.width, y: Self.padding.height, width: size.width - 2 * Self.padding.width,
            height: ceil(text.height))
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 5
        background.layer?.masksToBounds = true
        label.font = .menuFont(ofSize: NSFont.smallSystemFontSize + 1)
        label.textColor = .labelColor
        label.alignment = .center
        background.addSubview(label)
        panel.contentView = background
        return panel
    }
}
