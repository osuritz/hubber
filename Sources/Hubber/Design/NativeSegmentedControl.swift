import AppKit
import SwiftUI

// MARK: - NativeSegmentedControl

/// A full-width, equal-segment macOS segmented control backed by `NSSegmentedControl`.
///
/// Uses `segmentDistribution = .fillEqually` so every segment shares the available
/// horizontal space, and sets content-hugging priority to `.defaultLow` so the control
/// expands to fill its parent layout — matching the behaviour of the native Wi-Fi /
/// System Settings pickers on macOS 13+.
///
/// Swift 6: the `Coordinator` is `@MainActor`-isolated so all AppKit callbacks run on
/// the main actor with no `@unchecked Sendable` workarounds.
@MainActor
struct NativeSegmentedControl: NSViewRepresentable {
    let segments: [String]
    @Binding var selectedIndex: Int
    var isEnabled = true

    // MARK: NSViewRepresentable

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: segments,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.segmentChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.segmentStyle = .rounded
        // Low horizontal hugging → stretches to fill available width
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.selectedSegment = selectedIndex
        control.isEnabled = isEnabled
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        // Avoid redundant updates that would flicker
        if nsView.segmentCount != segments.count {
            nsView.segmentCount = segments.count
            for (i, label) in segments.enumerated() {
                nsView.setLabel(label, forSegment: i)
            }
        }
        if nsView.selectedSegment != selectedIndex {
            nsView.selectedSegment = selectedIndex
        }
        nsView.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var parent: NativeSegmentedControl

        init(_ parent: NativeSegmentedControl) {
            self.parent = parent
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let idx = sender.selectedSegment
            guard idx >= 0, idx < parent.segments.count else { return }
            parent.selectedIndex = idx
        }
    }
}

// MARK: - CaseIterable + Identifiable convenience

/// Typed wrapper that binds a `CaseIterable & Identifiable` enum value directly.
@MainActor
struct NativeSegmentedPicker<T: CaseIterable & Identifiable & Equatable>: View
    where T.AllCases: RandomAccessCollection {

    let cases: T.AllCases
    @Binding var selection: T
    var isEnabled = true
    /// Optional group label announced by VoiceOver (e.g. "Row density"). Nil = no label.
    var accessibilityLabel: String? = nil

    private var titleForCase: (T) -> String

    init(
        _ type: T.Type = T.self,
        selection: Binding<T>,
        isEnabled: Bool = true,
        title: @escaping (T) -> String,
        accessibilityLabel: String? = nil
    ) {
        cases = T.allCases
        _selection = selection
        self.isEnabled = isEnabled
        titleForCase = title
        self.accessibilityLabel = accessibilityLabel
    }

    private var selectedIndex: Int {
        cases.firstIndex(where: { $0 == selection }).map { cases.distance(from: cases.startIndex, to: $0) } ?? 0
    }

    var body: some View {
        NativeSegmentedControl(
            segments: cases.map { titleForCase($0) },
            selectedIndex: Binding(
                get: { selectedIndex },
                set: { newIndex in
                    let idx = cases.index(cases.startIndex, offsetBy: newIndex)
                    selection = cases[idx]
                }
            ),
            isEnabled: isEnabled
        )
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel ?? "")
    }
}
