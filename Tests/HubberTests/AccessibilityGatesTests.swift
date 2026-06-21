import SwiftUI
import Testing
@testable import Hubber

@Suite("Accessibility preference gates")
struct AccessibilityGatesTests {
    @Test("pulse disabled under reduce motion")
    func pulse() {
        #expect(AccessibilityGates.pulseEnabled(reduceMotion: false) == true)
        #expect(AccessibilityGates.pulseEnabled(reduceMotion: true) == false)
    }

    @Test("animation nil under reduce motion")
    func animation() {
        #expect(AccessibilityGates.animation(.easeInOut, reduceMotion: false) != nil)
        #expect(AccessibilityGates.animation(.easeInOut, reduceMotion: true) == nil)
    }
}
