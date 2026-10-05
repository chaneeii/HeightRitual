import Foundation

@MainActor
protocol ScheduledTask {
    func cancel()
}

/// Countdown, filming time, auto play and notices run on this, so tests can drive time by hand.
@MainActor
protocol Scheduling {
    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledTask
}

@MainActor
final class TaskScheduler: Scheduling {
    private struct Handle: ScheduledTask {
        let task: Task<Void, Never>
        func cancel() { task.cancel() }
    }

    func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledTask {
        Handle(task: Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        })
    }
}
