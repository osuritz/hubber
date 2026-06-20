import Testing
@testable import Hubber

@Suite("AccessibilityText atomic phrases")
struct AccessibilityTextAtomicTests {
    @Test("CI phrases")
    func ciPhrases() {
        #expect(AccessibilityText.ciPhrase(.passing) == "checks passing")
        #expect(AccessibilityText.ciPhrase(.failing) == "checks failing")
        #expect(AccessibilityText.ciPhrase(.running) == "checks running")
        #expect(AccessibilityText.ciPhrase(.pending) == "checks pending")
        #expect(AccessibilityText.ciPhrase(.noChecks) == "no checks")
    }

    @Test("Reviewer phrases")
    func reviewerPhrases() {
        #expect(AccessibilityText.reviewerPhrase(.approved) == "approved")
        #expect(AccessibilityText.reviewerPhrase(.changesRequested) == "changes requested")
        #expect(AccessibilityText.reviewerPhrase(.commented) == "commented")
        #expect(AccessibilityText.reviewerPhrase(.pending) == "review pending")
    }

    @Test("SLO phrases")
    func sloPhrases() {
        #expect(AccessibilityText.sloPhrase(.green) == "on track")
        #expect(AccessibilityText.sloPhrase(.amber) == "due soon")
        #expect(AccessibilityText.sloPhrase(.red) == "overdue")
    }
}
