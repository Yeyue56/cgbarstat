import Foundation

public protocol SnapshotPersisting: Sendable {
    func load() -> UsageSnapshot?
    func save(_ snapshot: UsageSnapshot)
}

/**
 * 持久化上一份用量快照。
 * UserDefaults 读写是线程安全的；快照没有令牌，因此标记为非检查 Sendable。
 */
public struct UserDefaultsSnapshotStore: SnapshotPersisting, @unchecked Sendable {
    public static let key = "cgbarstat.lastSnapshot"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Self.key),
              var snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else {
            return nil
        }
        snapshot.cursorStale = true
        snapshot.grokStale = true
        return snapshot
    }

    public func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
