import SwiftUI

/// Central decisions for system accessibility preferences, so views/AppKit gate uniformly.
enum AccessibilityGates {
    /// The menu-bar refresh pulse animates only when Reduce Motion is off.
    static func pulseEnabled(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// The animation to apply for a transition, or nil to switch state instantly under Reduce Motion.
    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }
}
