import Foundation

@MainActor enum CaptureLifecycle {
    // A new stream must await the old startup AND its final stop. Cancelling
    // a Task alone cannot cancel ScreenCaptureKit's in-flight start operation.
    static func finish(previous: Task<Void, Never>?, startup: Task<Void, Never>?,
                       stop: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Task {
            await previous?.value
            await startup?.value
            await stop()
        }
    }
}
