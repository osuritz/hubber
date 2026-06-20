import Foundation

/// Pure, testable text that VoiceOver speaks. No SwiftUI/AppKit so it unit-tests cleanly.
enum AccessibilityText {
    static func ciPhrase(_ ci: PullRequestCI) -> String {
        switch ci {
        case .passing: "checks passing"
        case .failing: "checks failing"
        case .running: "checks running"
        case .pending: "checks pending"
        case .noChecks: "no checks"
        }
    }

    static func reviewerPhrase(_ state: ReviewerState) -> String {
        switch state {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .commented: "commented"
        case .pending: "review pending"
        }
    }

    static func sloPhrase(_ status: SLOStatus) -> String {
        switch status {
        case .green: "on track"
        case .amber: "due soon"
        case .red: "overdue"
        }
    }
}
