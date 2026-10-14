import AppKit
import StipendCore
import SwiftUI

struct UsagePanelView: View {
    let meter: Meter
    let display: UsageDisplay
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch display {
            case .signedOut:
                Text("未检测到本机 Cursor 登录")
            case .unavailable:
                Text("用量暂时无法更新")
            case .ready(let snapshot):
                ready(snapshot)
            }
        }
        .padding(14)
        .frame(width: meter == .grokBot ? 220 : 320, alignment: .leading)
    }

    @ViewBuilder
    private func ready(_ snapshot: UsageSnapshot) -> some View {
        switch meter {
        case .cursorModels:
            pool(PoolPanelCopy.make(pool: snapshot.cursorModels, isStale: snapshot.cursorStale))
        case .otherModels:
            pool(PoolPanelCopy.make(pool: snapshot.otherModels, isStale: snapshot.cursorStale))
        case .grokBot:
            grok(GrokPanelCopy.make(usage: snapshot.grokBot, now: now, isStale: snapshot.grokStale))
        }
    }

    private func pool(_ model: PoolPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.percentText).font(.title.monospacedDigit())
                Spacer()
                Text(model.periodTokensText).font(.title2.monospacedDigit())
            }
            HStack {
                Text(model.todayShareText)
                Spacer()
                Text(model.todayTokensText).monospacedDigit()
            }
            .font(.body)
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ModelNameLabel(name: row.name)
                    ProgressBar(fraction: row.fraction)
                    Text(row.percentText).frame(width: 44, alignment: .trailing)
                    Text(row.tokensText).frame(width: 56, alignment: .trailing)
                }
                .font(.callout.monospacedDigit())
            }
            if let stale = model.staleText {
                Text(stale).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func grok(_ model: GrokPanelModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.percentText).font(.title.monospacedDigit())
            if let allowance = model.allowanceText {
                Text(allowance).font(.body)
            }
            if let reset = model.resetText {
                Text(reset).font(.body)
            }
            if let stale = model.staleText {
                Text(stale).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 名称超出 110pt 时尾部省略。只有这时悬停才显示全文。
/// 用量面板不会激活应用，SwiftUI `.help` 依赖的系统 tooltip 不会出现，因此全文由单独的小面板显示。
private struct ModelNameLabel: View {
    var name: String

    var body: some View {
        TruncatingNameLabel(name: name)
            .frame(maxWidth: TruncatingNameLabel.maxWidth, alignment: .leading)
    }
}

private struct TruncatingNameLabel: NSViewRepresentable {
    var name: String
    static let maxWidth: CGFloat = 110

    func makeNSView(context: Context) -> TruncatingNameField {
        TruncatingNameField(labelWithString: name)
    }

    func updateNSView(_ field: TruncatingNameField, context: Context) {
        field.stringValue = name
        field.font = Self.font
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.alignment = .left
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        field.refreshTooltip()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TruncatingNameField, context: Context) -> CGSize? {
        nsView.font = Self.font
        let intrinsic = nsView.intrinsicContentSize
        let offered = proposal.width ?? Self.maxWidth
        let width = min(max(intrinsic.width, 0), min(offered, Self.maxWidth))
        return CGSize(width: width, height: max(intrinsic.height, 1))
    }

    static func dismantleNSView(_ nsView: TruncatingNameField, coordinator: ()) {
        NameTooltipController.shared.hide(owner: nsView)
    }

    private static var font: NSFont {
        let base = NSFont.preferredFont(forTextStyle: .callout)
        return NSFont.monospacedDigitSystemFont(ofSize: base.pointSize, weight: .regular)
    }
}

/// 按字段实际宽度判断是否省略。跟踪区使用 activeAlways：用量面板不是 key window，默认跟踪区收不到进入事件。
private final class TruncatingNameField: NSTextField {
    private var wantsTooltip = false
    private var tracking: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if let tracking {
                removeTrackingArea(tracking)
                self.tracking = nil
            }
            NameTooltipController.shared.hide(owner: self)
            return
        }
        installTracking()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        installTracking()
    }

    override func layout() {
        super.layout()
        applyTooltip()
    }

    override func mouseEntered(with event: NSEvent) {
        wantsTooltip = true
        applyTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        wantsTooltip = false
        applyTooltip()
    }

    func refreshTooltip() {
        applyTooltip()
    }

    private func installTracking() {
        guard window != nil, tracking == nil else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    private func applyTooltip() {
        if wantsTooltip, isNameTruncated {
            NameTooltipController.shared.show(stringValue, from: self, owner: self)
        } else {
            NameTooltipController.shared.hide(owner: self)
        }
    }

    private var isNameTruncated: Bool {
        guard bounds.width > 1, let font else { return false }
        let full = (stringValue as NSString).size(withAttributes: [.font: font]).width
        return full > bounds.width + 1
    }
}

/// 全文提示不走系统 tooltip。它不接收鼠标，避免挡住用量面板的悬停跟踪。
@MainActor
final class NameTooltipController {
    static let shared = NameTooltipController()

    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private weak var owner: AnyObject?

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 22),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.alignment = .left
        let background = NSView()
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        background.addSubview(label)
        panel.contentView = background
    }

    func show(_ text: String, from anchor: NSView, owner: AnyObject) {
        guard !text.isEmpty, anchor.window != nil else { return }
        self.owner = owner
        let font = (anchor as? NSTextField)?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        label.stringValue = text
        label.font = font
        label.textColor = .labelColor
        panel.contentView?.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        panel.contentView?.layer?.borderColor = NSColor.separatorColor.cgColor
        let singleLine = (text as NSString).size(withAttributes: [.font: font])
        let textWidth = min(360, ceil(singleLine.width))
        label.preferredMaxLayoutWidth = textWidth
        let textHeight = ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 800)).height ?? singleLine.height)
        let size = NSSize(width: textWidth + 16, height: textHeight + 8)
        label.frame = NSRect(x: 8, y: 4, width: textWidth, height: textHeight)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        guard let window = anchor.window else { return }
        let anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var origin = NSPoint(x: anchorRect.minX, y: anchorRect.maxY + 4)
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if origin.y + size.height > visible.maxY {
            origin.y = anchorRect.minY - size.height - 4
        }
        if origin.x + size.width > visible.maxX {
            origin.x = visible.maxX - size.width
        }
        if origin.x < visible.minX { origin.x = visible.minX }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide(owner: AnyObject) {
        guard self.owner === owner else { return }
        hide()
    }

    func hide() {
        owner = nil
        panel.orderOut(nil)
    }
}

private struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.accentColor)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}
