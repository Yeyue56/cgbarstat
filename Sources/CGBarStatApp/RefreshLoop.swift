import AppKit
import Foundation
import CGBarStatCore

@MainActor
final class RefreshLoop {
    private let model: AppModel
    private var loop: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        loop = Task { [weak self] in
            guard let self else { return }
            await self.model.refresh(reason: .launch)
            while !Task.isCancelled {
                let wait = RefreshPolicy.timerInterval(for: self.model.display)
                try? await Task.sleep(for: .seconds(wait))
                await self.model.refresh(reason: .timer)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.model.refresh(reason: .wake)
            }
        }
    }
}
