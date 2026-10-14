import Foundation
import Observation
import StipendCore

@MainActor
@Observable
final class AppModel {
    private(set) var display: UsageDisplay
    private(set) var phases: [Meter: HoverPhase]
    var onChange: () -> Void = {}

    private var lastSuccess: Date?
    private let store: any SnapshotPersisting
    private let reader: CursorSessionReader
    private let client: PeriodUsageClient

    init(store: any SnapshotPersisting, reader: CursorSessionReader, client: PeriodUsageClient) {
        self.store = store
        self.reader = reader
        self.client = client
        phases = Dictionary(uniqueKeysWithValues: Meter.allCases.map { ($0, HoverPhase.idle) })
        if let cached = store.load() {
            display = .ready(cached)
        } else {
            display = .signedOut
        }
    }

    func labels() -> [StatusItemLabel] {
        DisplayUpdate.labels(for: display)
    }

    func send(_ meter: Meter, _ event: HoverEvent) {
        phases = MeterFocus.apply(phases: phases, meter: meter, event: event)
        onChange()
    }

    func refresh(reason: RefreshReason) async {
        let now = Date()
        guard RefreshPolicy.shouldRefresh(lastSuccess: lastSuccess, now: now, reason: reason) else { return }
        let session: SessionReadResult
        do {
            session = try reader.read()
        } catch {
            return
        }
        guard case .token(let token) = session else {
            setDisplay(DisplayUpdate.signedOut())
            return
        }
        do {
            let snapshot = try await client.fetch(token: token, now: now, calendar: .current)
            lastSuccess = snapshot.fetchedAt
            let merged = merge(snapshot)
            setDisplay(DisplayUpdate.success(merged))
            store.save(merged)
        } catch UsageClientError.unauthorized {
            setDisplay(DisplayUpdate.signedOut())
        } catch {
            if case .ready(var previous) = display {
                previous.cursorStale = true
                previous.grokStale = true
                setDisplay(.ready(previous))
            }
        }
    }

    /// Grok 这次没有读到时，沿用上一份 Grok，避免一次 Sand 失败把 GB 打成无数据。
    private func merge(_ incoming: UsageSnapshot) -> UsageSnapshot {
        guard case .ready(let previous) = display else { return incoming }
        if incoming.grokStale {
            var copy = incoming
            copy.grokBot = previous.grokBot
            copy.grokStale = true
            return copy
        }
        return incoming
    }

    private func setDisplay(_ newValue: UsageDisplay) {
        display = newValue
        onChange()
    }
}
