import SwiftUI

struct DeveloperPanelView: View {
    @ObservedObject var store: HubberStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            actions

            if let error = store.pullRequestRefreshError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.hubberError)
                    .fixedSize(horizontal: false, vertical: true)
            }

            logRows
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                store.copyDeveloperLog()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(store.developerLog.isEmpty)

            Button {
                store.clearDeveloperLog()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(store.developerLog.isEmpty)

            Spacer()
        }
        .controlSize(.small)
    }

    private var logRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.developerLog.isEmpty {
                Text("No logs yet")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                ForEach(store.developerLog.prefix(12)) { entry in
                    DeveloperLogRow(entry: entry)
                }
            }
        }
    }
}

private struct DeveloperLogRow: View {
    let entry: DeveloperLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.25)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
