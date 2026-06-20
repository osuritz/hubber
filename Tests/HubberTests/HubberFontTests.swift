import SwiftUI
import Testing
@testable import Hubber

@Suite("HubberFont scaling")
struct HubberFontTests {

    // MARK: - scaledSize

    @Test("scaled size at factor 1.0 returns base unchanged")
    func scalingIdentity() {
        #expect(HubberFont.scaledSize(base: 13, factor: 1.0) == 13)
    }

    @Test("scaled size at factor 1.5 returns base × 1.5")
    func scalingFactor() {
        #expect(HubberFont.scaledSize(base: 13, factor: 1.5) == 19.5)
    }

    @Test("scaled size is monotonically larger with larger factor")
    func scalingMonotonic() {
        #expect(HubberFont.scaledSize(base: 11, factor: 2.0) > HubberFont.scaledSize(base: 11, factor: 1.0))
    }

    // MARK: - Role base sizes must match HubberType.PointSize exactly

    @Test("Role.title base matches HubberType.PointSize.title (13)")
    func roleTitleBase() {
        #expect(HubberFont.Role.title.base == HubberType.PointSize.title)
    }

    @Test("Role.secondary base matches HubberType.PointSize.secondary (11)")
    func roleSecondaryBase() {
        #expect(HubberFont.Role.secondary.base == HubberType.PointSize.secondary)
    }

    @Test("Role.sloPill base matches HubberType.PointSize.sloPill (11)")
    func roleSloPillBase() {
        #expect(HubberFont.Role.sloPill.base == HubberType.PointSize.sloPill)
    }

    @Test("Role.ciDetail base matches HubberType.PointSize.ciDetail (11)")
    func roleCiDetailBase() {
        #expect(HubberFont.Role.ciDetail.base == HubberType.PointSize.ciDetail)
    }

    @Test("Role.log base matches HubberType.PointSize.log (11)")
    func roleLogBase() {
        #expect(HubberFont.Role.log.base == HubberType.PointSize.log)
    }

    @Test("Role.section base matches HubberType.PointSize.section (11)")
    func roleSectionBase() {
        #expect(HubberFont.Role.section.base == HubberType.PointSize.section)
    }

    @Test("Role.footer base matches HubberType.PointSize.footer (11)")
    func roleFooterBase() {
        #expect(HubberFont.Role.footer.base == HubberType.PointSize.footer)
    }

    @Test("Role.headerTitle base is 15")
    func roleHeaderTitleBase() {
        #expect(HubberFont.Role.headerTitle.base == 15)
    }

    @Test("Role.settingsLabel base is 12.5")
    func roleSettingsLabelBase() {
        #expect(HubberFont.Role.settingsLabel.base == 12.5)
    }

    @Test("Role.settingsSub base is 11")
    func roleSettingsSubBase() {
        #expect(HubberFont.Role.settingsSub.base == 11)
    }

    @Test("Role.badge base is 10")
    func roleBadgeBase() {
        #expect(HubberFont.Role.badge.base == 10)
    }

    @Test("Role.prNumber base is 11")
    func rolePrNumberBase() {
        #expect(HubberFont.Role.prNumber.base == 11)
    }

    // MARK: - Role weights match HubberType

    @Test("Role.title weight is .medium")
    func roleTitleWeight() {
        #expect(HubberFont.Role.title.weight == Font.Weight.medium)
    }

    @Test("Role.section weight is .semibold")
    func roleSectionWeight() {
        #expect(HubberFont.Role.section.weight == Font.Weight.semibold)
    }

    @Test("Role.headerTitle weight is .semibold")
    func roleHeaderTitleWeight() {
        #expect(HubberFont.Role.headerTitle.weight == Font.Weight.semibold)
    }

    @Test("Role.badge weight is .semibold")
    func roleBadgeWeight() {
        #expect(HubberFont.Role.badge.weight == Font.Weight.semibold)
    }

    @Test("Role.sloPill weight is .medium")
    func roleSloPillWeight() {
        #expect(HubberFont.Role.sloPill.weight == Font.Weight.medium)
    }

    @Test("Role.secondary weight is .regular")
    func roleSecondaryWeight() {
        #expect(HubberFont.Role.secondary.weight == Font.Weight.regular)
    }

    // MARK: - Monospaced design roles

    @Test("Role.log design is .monospaced")
    func roleLogDesign() {
        #expect(HubberFont.Role.log.design == Font.Design.monospaced)
    }

    @Test("Role.prNumber design is .monospaced")
    func rolePrNumberDesign() {
        #expect(HubberFont.Role.prNumber.design == Font.Design.monospaced)
    }

    @Test("Role.title design is .default (not monospaced)")
    func roleTitleDesign() {
        #expect(HubberFont.Role.title.design == Font.Design.default)
    }
}
