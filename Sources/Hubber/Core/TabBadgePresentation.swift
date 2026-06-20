import Foundation

/// Pure count helpers for the in-popover per-tab badges.
///
/// `needsAttention` surfaces only items that want action; `totalCount` shows the
/// full item count in each tab. Reviews is identical in both modes because every
/// incoming review is a request awaiting the viewer.
enum TabBadgePresentation {
    static func counts(data: HubberData, mode: TabBadgeMode) -> [WorkTab: Int] {
        switch mode {
        case .needsAttention:
            [
                .incoming: data.incoming.count,
                .outgoing: data.outgoing.count(where: { $0.ci == .failing || $0.unresolved > 0 }),
                .drafts: data.drafts.count(where: { $0.ci == .failing }),
            ]
        case .totalCount:
            [
                .incoming: data.incoming.count,
                .outgoing: data.outgoing.count,
                .drafts: data.drafts.count,
            ]
        }
    }
}
