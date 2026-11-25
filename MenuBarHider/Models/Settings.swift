import Foundation

final class Settings {
    static let shared = Settings()

    private let defaults: UserDefaults
    private enum Key {
        static let autoHideSeconds = "autoHideSeconds"
        static let hiddenBundleIDs = "hiddenBundleIDs"
        static let removedMenuExtraIDs = "removedMenuExtraIDs"
        static let hidingMethod = "hidingMethod"
        static let visibleBundleIDs = "visibleBundleIDs"
        static let expandedBarWidth = "expandedBarWidth"
        static let visibleExtent = "visibleExtent"
        static let notchReserve = "notchReserve"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.autoHideSeconds: 10])
    }

    /// 0 disables the auto-hide timer.
    var autoHideSeconds: Int {
        get { defaults.integer(forKey: Key.autoHideSeconds) }
        set { defaults.set(newValue, forKey: Key.autoHideSeconds) }
    }

    /// Last computed hidden set: lets the app hide before the first Accessibility scan.
    var hiddenBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.hiddenBundleIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.hiddenBundleIDs) }
    }

    /// Items seen outside `|`…`»` by the last scans: narrow mode hides them while expanded.
    var visibleBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.visibleBundleIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.visibleBundleIDs) }
    }

    /// Width the fully expanded bar needs, leftmost icon to the screen edge; 0 when unknown.
    var expandedBarWidth: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.expandedBarWidth)) }
        set { defaults.set(Double(newValue), forKey: Key.expandedBarWidth) }
    }

    /// Part of `expandedBarWidth` outside `|`…`»`: what narrow mode hides.
    var visibleExtent: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.visibleExtent)) }
        set { defaults.set(Double(newValue), forKey: Key.visibleExtent) }
    }

    /// Room beside the notch the bar leaves free, learned from overflows; 0 until one is seen.
    var notchReserve: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.notchReserve)) }
        set { defaults.set(Double(newValue), forKey: Key.notchReserve) }
    }

    var removedMenuExtraIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.removedMenuExtraIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.removedMenuExtraIDs) }
    }

    var hidingMethod: HidingMethod {
        get { HidingMethod(rawValue: defaults.string(forKey: Key.hidingMethod) ?? "") ?? .assessment }
        set { defaults.set(newValue.rawValue, forKey: Key.hidingMethod) }
    }
}
