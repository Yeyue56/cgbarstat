import AppKit
import StipendCore
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private var entries: [Meter: StatusEntry] = [:]
    private let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let hosting = NSHostingView(rootView: UsagePanelView(meter: .cursorModels, display: .signedOut, now: Date()))
    private var outsideMonitor: Any?
    private var tickWork: DispatchWorkItem?
    private var visibleMeter: Meter?

    init(model: AppModel) {
        self.model = model
        super.init()
        configurePanel()
        for meter in MeterOrder.creationOrder {
            entries[meter] = makeEntry(meter)
        }
        model.onChange = { [weak self] in self?.sync() }
        sync()
    }

    private func configurePanel() {
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        effect.addTrackingArea(NSTrackingArea(
            rect: effect.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        panel.contentView = effect
    }

    private func makeEntry(_ meter: Meter) -> StatusEntry {
        let item = NSStatusBar.system.statusItem(withLength: 42)
        let button = item.button
        button?.title = ""
        let view = TwoLineStatusView(frame: button?.bounds ?? NSRect(x: 0, y: 0, width: 42, height: 22))
        view.autoresizingMask = [.width, .height]
        view.onEntered = { [weak self] in self?.model.send(meter, .pointerEnteredItem(Date())) }
        view.onExited = { [weak self] in self?.model.send(meter, .pointerExitedItem(Date())) }
        view.onClick = { [weak self] in self?.model.send(meter, .clickItem) }
        button?.addSubview(view)
        return StatusEntry(meter: meter, item: item, view: view)
    }

    private func sync() {
        let labels = model.labels()
        for (index, meter) in MeterOrder.visualOrder.enumerated() {
            guard let entry = entries[meter] else { continue }
            entry.view.abbreviation = labels[index].abbreviation
            entry.view.percentText = labels[index].percentText
            entry.item.button?.setAccessibilityLabel(labels[index].accessibilityText)
            entry.view.needsDisplay = true
        }
        let shown = MeterOrder.visualOrder.first { model.phases[$0]?.showsPanel == true }
        if let shown, let entry = entries[shown], let button = entry.item.button {
            hosting.rootView = UsagePanelView(meter: shown, display: model.display, now: Date())
            position(panel, relativeTo: button)
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            installOutsideMonitor()
            if visibleMeter != shown {
                visibleMeter = shown
                Task { await model.refresh(reason: .panelOpened) }
            }
            scheduleTick(for: shown)
        } else if panel.isVisible {
            panel.orderOut(nil)
            removeOutsideMonitor()
            visibleMeter = nil
        }
        // pendingShow 还不显示面板，但仍要排 tick，否则 0.18 秒后不会进入 preview。
        if shown == nil {
            let waiting = MeterOrder.visualOrder.first { meter in
                if case .pendingShow = model.phases[meter] { return true }
                return false
            }
            if let waiting {
                scheduleTick(for: waiting)
            }
        }
    }

    private func scheduleTick(for meter: Meter) {
        tickWork?.cancel()
        let delay: TimeInterval?
        switch model.phases[meter] {
        case .pendingShow(let since):
            delay = HoverTiming.showDelay - Date().timeIntervalSince(since)
        case .pendingHide(let since):
            delay = HoverTiming.hideDelay - Date().timeIntervalSince(since)
        default:
            delay = nil
        }
        guard let delay else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.model.send(meter, .tick(Date()))
        }
        tickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0), execute: work)
    }

    private func position(_ panel: NSPanel, relativeTo button: NSStatusBarButton) {
        let fit = hosting.fittingSize
        let size = NSSize(width: max(fit.width, 220), height: max(fit.height, 80))
        guard let window = button.window else { return }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(
            x: buttonRect.midX - size.width / 2,
            y: buttonRect.minY - size.height + HoverTiming.panelOverlapPoints
        )
        let visible = window.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if origin.x < visible.minX { origin.x = visible.minX }
        if origin.x + size.width > visible.maxX { origin.x = visible.maxX - size.width }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleGlobalClick()
            }
        }
    }

    private func removeOutsideMonitor() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
    }

    private func handleGlobalClick() {
        let mouse = NSEvent.mouseLocation
        for entry in entries.values {
            if let button = entry.item.button, let window = button.window {
                let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
                if rect.contains(mouse) { return }
            }
        }
        if panel.isVisible, panel.frame.contains(mouse) { return }
        if let visibleMeter {
            model.send(visibleMeter, .clickOutside)
        }
    }

    /// NSTrackingArea 按选择子回调 owner。此类不是 NSResponder，不能使用 override。
    /// 选择子必须是 mouseEntered: / mouseExited:，否则进入和离开面板的事件不会进入 MeterFocus。
    @objc(mouseEntered:)
    func mouseEntered(with event: NSEvent) {
        guard let visibleMeter else { return }
        model.send(visibleMeter, .pointerEnteredPanel(Date()))
    }

    @objc(mouseExited:)
    func mouseExited(with event: NSEvent) {
        guard let visibleMeter else { return }
        model.send(visibleMeter, .pointerExitedPanel(Date()))
    }
}

private struct StatusEntry {
    var meter: Meter
    var item: NSStatusItem
    var view: TwoLineStatusView
}

/// 上行简拼，下行百分比。按钮 title 保持空白，避免和自定义视图并排。
private final class TwoLineStatusView: NSView {
    var abbreviation = "CM"
    var percentText = "—"
    var onEntered: () -> Void = {}
    var onExited: () -> Void = {}
    var onClick: () -> Void = {}

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let abbreviationFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let color = NSColor.labelColor
        let abbreviationAttributes: [NSAttributedString.Key: Any] = [.font: abbreviationFont, .foregroundColor: color]
        let percentAttributes: [NSAttributedString.Key: Any] = [.font: percentFont, .foregroundColor: color]
        let abbreviationSize = (abbreviation as NSString).size(withAttributes: abbreviationAttributes)
        let percentSize = (percentText as NSString).size(withAttributes: percentAttributes)
        let total = abbreviationSize.height + percentSize.height
        var y = (bounds.height - total) / 2
        let percentRect = NSRect(x: (bounds.width - percentSize.width) / 2, y: y, width: percentSize.width, height: percentSize.height)
        (percentText as NSString).draw(in: percentRect, withAttributes: percentAttributes)
        y += percentSize.height
        let abbreviationRect = NSRect(x: (bounds.width - abbreviationSize.width) / 2, y: y, width: abbreviationSize.width, height: abbreviationSize.height)
        (abbreviation as NSString).draw(in: abbreviationRect, withAttributes: abbreviationAttributes)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onEntered() }
    override func mouseExited(with event: NSEvent) { onExited() }

    /// 接下按下事件，避免 NSStatusBarButton 的跟踪把 mouseUp 吃掉，导致单击无法钉住。
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick() }
}
