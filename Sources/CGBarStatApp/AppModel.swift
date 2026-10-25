import Foundation
import Observation
import CGBarStatCore

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
        let token: String
        switch session {
        case .notSignedIn:
            setDisplay(DisplayUpdate.signedOut())
            return
        case .sealed:
            setDisplay(.encryptedLogin)
            return
        case .token(let value):
            token = value
        }
        let refreshToken = try? reader.readRefreshToken()
        let sessionUserId = try? reader.readSessionUserId()
        let accessToken = CursorToken.sessionToken(from: token)
        let usableRefresh = refreshToken.map { CursorToken.sessionToken(from: $0) }
        do {
            let prepared = try await client.fetchPrepared(
                accessToken: accessToken,
                refreshToken: usableRefresh,
                sessionUserId: sessionUserId,
                now: now,
                calendar: .current
            )
            // 本地拆出来的 JWT 不是服务端新发的令牌，不能写回 Cursor 原来的键。
            if prepared.accessToken != accessToken || prepared.refreshToken != usableRefresh {
                try? reader.updateTokens(accessToken: prepared.accessToken, refreshToken: prepared.refreshToken)
            }
            lastSuccess = prepared.snapshot.fetchedAt
            let merged = DisplayUpdate.merged(previous: currentSnapshot ?? store.load(), incoming: prepared.snapshot)
            setDisplay(DisplayUpdate.success(merged))
            store.save(merged)
        } catch UsageClientError.loginExpired {
            // 两个令牌都被拒绝。保留旧百分比会一直显示「数据已过期」，但刷新不会成功。
            setDisplay(.loginExpired)
        } catch {
            setDisplay(DisplayUpdate.keepingLastSnapshot(current: display, cached: store.load()))
        }
    }

    private var currentSnapshot: UsageSnapshot? {
        if case .ready(let snapshot) = display { return snapshot }
        return nil
    }

    private func setDisplay(_ newValue: UsageDisplay) {
        display = newValue
        onChange()
    }
}
