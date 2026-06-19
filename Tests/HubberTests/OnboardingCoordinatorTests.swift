import Foundation
import XCTest
@testable import Hubber

@MainActor
final class OnboardingCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private nonisolated(unsafe) var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "OnboardingCoordinatorTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFreshStartsAtWelcomeNotCompleted() {
        let sut = OnboardingCoordinator(defaults: defaults)
        XCTAssertEqual(sut.currentStep, .welcome)
        XCTAssertFalse(sut.isCompleted)
    }

    func testAdvanceMovesThroughStepsInOrder() {
        let sut = OnboardingCoordinator(defaults: defaults)
        sut.advance()
        XCTAssertEqual(sut.currentStep, .consent)
        sut.advance()
        XCTAssertEqual(sut.currentStep, .connect)
        sut.advance()
        XCTAssertEqual(sut.currentStep, .notifications)
        sut.advance()
        XCTAssertEqual(sut.currentStep, .launchAtLogin)
        XCTAssertFalse(sut.isCompleted)
    }

    func testAdvancePastLastStepCompletes() {
        let sut = OnboardingCoordinator(defaults: defaults)
        for _ in OnboardingCoordinator.Step.allCases {
            sut.advance()
        }
        XCTAssertTrue(sut.isCompleted)
        XCTAssertTrue(defaults.bool(forKey: "onboardingCompleted"))
    }

    func testStepPersistsAndResumes() {
        let first = OnboardingCoordinator(defaults: defaults)
        first.advance() // welcome -> consent
        first.advance() // consent -> connect
        let resumed = OnboardingCoordinator(defaults: defaults)
        XCTAssertEqual(resumed.currentStep, .connect)
        XCTAssertFalse(resumed.isCompleted)
    }

    func testCompletedPersistsAcrossInstances() {
        let first = OnboardingCoordinator(defaults: defaults)
        first.complete()
        let resumed = OnboardingCoordinator(defaults: defaults)
        XCTAssertTrue(resumed.isCompleted)
    }

    func testSkipConnectAdvancesWhenConnected() {
        let sut = OnboardingCoordinator(defaults: defaults)
        sut.advance() // consent
        sut.advance() // connect
        sut.skipConnectIfAlreadyConnected(true)
        XCTAssertEqual(sut.currentStep, .notifications)
    }

    func testSkipConnectNoOpWhenNotConnected() {
        let sut = OnboardingCoordinator(defaults: defaults)
        sut.advance()
        sut.advance() // connect
        sut.skipConnectIfAlreadyConnected(false)
        XCTAssertEqual(sut.currentStep, .connect)
    }

    func testSkipConnectNoOpWhenNotOnConnectStep() {
        let sut = OnboardingCoordinator(defaults: defaults)
        sut.skipConnectIfAlreadyConnected(true) // on welcome
        XCTAssertEqual(sut.currentStep, .welcome)
    }
}
