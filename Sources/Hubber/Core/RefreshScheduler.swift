import Foundation

/// Adaptive refresh scheduler.
///
/// Loop: `refresh()` → compute `interval(for: context())` → `sleep(interval)` → repeat.
/// `reset()` cancels the current in-flight sleep and re-enters at `refresh()`.
@MainActor
final class RefreshScheduler {
    private let idle: any MachineIdleProviding
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var task: Task<Void, Never>?
    private var contextProvider: (@MainActor () -> RefreshContext)?
    private var refreshAction: (@MainActor () async -> Void)?

    init(
        idle: any MachineIdleProviding = SystemIdleProvider(),
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.idle = idle
        self.sleep = sleep
    }

    func start(
        context: @escaping @MainActor () -> RefreshContext,
        refresh: @escaping @MainActor () async -> Void
    ) {
        contextProvider = context
        refreshAction = refresh
        scheduleLoop()
    }

    /// Cancel the current wait, refresh now, and reschedule from completion.
    func reset() {
        task?.cancel()
        scheduleLoop()
    }

    func stop() {
        task?.cancel()
        task = nil
        contextProvider = nil
        refreshAction = nil
    }

    // MARK: - Private

    private func scheduleLoop() {
        task?.cancel()
        guard let context = contextProvider, let refresh = refreshAction else { return }
        let idle = idle
        let sleep = sleep
        task = Task {
            while !Task.isCancelled {
                await refresh()
                guard !Task.isCancelled else { break }

                var ctx = context()
                ctx.isMachineIdle = idle.isIdle
                let interval = RefreshCadence.interval(for: ctx)

                do {
                    try await sleep(interval)
                } catch {
                    break
                }
            }
        }
    }
}
