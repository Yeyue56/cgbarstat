import CoreGraphics
import Foundation

public enum HoverTiming {
    public static let showDelay: TimeInterval = 0.18
    public static let hideDelay: TimeInterval = 0.28
    public static let panelOverlapPoints: CGFloat = 1
}

public enum HoverEvent: Equatable, Sendable {
    case pointerEnteredItem(Date)
    case pointerExitedItem(Date)
    case pointerEnteredPanel(Date)
    case pointerExitedPanel(Date)
    case clickItem
    case clickOutside
    case tick(Date)
}

public enum HoverPhase: Equatable, Sendable {
    case idle
    case pendingShow(since: Date)
    case preview
    case pendingHide(since: Date)
    case pinned

    public var showsPanel: Bool {
        switch self {
        case .preview, .pendingHide, .pinned:
            return true
        case .idle, .pendingShow:
            return false
        }
    }
}

public enum HoverReducer {
    public static func reduce(_ phase: HoverPhase, _ event: HoverEvent) -> HoverPhase {
        switch event {
        case .clickItem:
            return .pinned
        case .clickOutside:
            return .idle
        case .pointerEnteredItem(let date):
            switch phase {
            case .idle:
                return .pendingShow(since: date)
            case .pendingHide:
                return .preview
            case .pendingShow, .preview, .pinned:
                return phase
            }
        case .pointerExitedItem(let date):
            switch phase {
            case .pendingShow:
                return .idle
            case .preview:
                return .pendingHide(since: date)
            case .idle, .pendingHide, .pinned:
                return phase
            }
        case .pointerEnteredPanel:
            switch phase {
            case .pendingHide:
                return .preview
            case .idle, .pendingShow, .preview, .pinned:
                return phase
            }
        case .pointerExitedPanel(let date):
            switch phase {
            case .preview:
                return .pendingHide(since: date)
            case .idle, .pendingShow, .pendingHide, .pinned:
                return phase
            }
        case .tick(let date):
            switch phase {
            case .pendingShow(let since):
                if date >= since.addingTimeInterval(HoverTiming.showDelay) {
                    return .preview
                }
                return phase
            case .pendingHide(let since):
                if date >= since.addingTimeInterval(HoverTiming.hideDelay) {
                    return .idle
                }
                return phase
            case .idle, .preview, .pinned:
                return phase
            }
        }
    }
}

public enum Meter: String, CaseIterable, Equatable, Sendable, Codable {
    case cursorModels
    case otherModels
    case grokBot
}

public enum MeterOrder {
    /// 菜单栏从左到右阅读的顺序。
    public static let visualOrder: [Meter] = [.cursorModels, .otherModels, .grokBot]
    /// NSStatusItem 后创建的出现在更左侧，因此按视觉顺序的反方向创建。
    public static let creationOrder: [Meter] = [.grokBot, .otherModels, .cursorModels]
}

public enum MeterFocus {
    /// 某个状态项进入显示面板的相位时，其他项立即回到 idle。
    public static func apply(phases: [Meter: HoverPhase], meter: Meter, event: HoverEvent) -> [Meter: HoverPhase] {
        var next = phases
        let reduced = HoverReducer.reduce(phases[meter] ?? .idle, event)
        next[meter] = reduced
        if reduced.showsPanel {
            for other in Meter.allCases where other != meter {
                next[other] = .idle
            }
        }
        return next
    }
}
