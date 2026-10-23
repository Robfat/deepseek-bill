import AppKit
import CoreGraphics
import SwiftUI
import Combine

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = UsageModel()
    var statusItem: NSStatusItem!
    var panel: KeyPanel!
    var hosting: NSHostingView<DashboardView>!
    var effect: NSVisualEffectView!
    var cancellables = Set<AnyCancellable>()
    var timer: Timer?
    var isPositioning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPanel()
        observeModel()

        model.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.model.refresh()
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "¥--"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // MARK: - 窗口

    private func setupPanel() {
        let root = DashboardView(model: model)
        hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 700)
        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize
        let height = min(780, max(620, fitted.height))
        let contentSize = NSSize(width: 380, height: height)

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        container.addSubview(effect)

        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)

        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: contentSize),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)
        panel.contentView = container
        // 桌面层：只在桌面上显示，会被普通应用窗口盖住，不置顶。
        panel.isFloatingPanel = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.delegate = self

        applyMaterial()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyMaterial()
        }
    }

    /// 毛玻璃；系统开启「降低透明度」时退回实色底。
    private func applyMaterial() {
        guard effect != nil else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect.isHidden = reduce
        panel.contentView?.layer?.backgroundColor = reduce
            ? NSColor.windowBackgroundColor.cgColor
            : NSColor.clear.cgColor
    }

    private func observeModel() {
        model.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusTitle() }
            }
            .store(in: &cancellables)

        model.$lastUpdated
            .compactMap { $0 }
            .first()
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !self.panel.isVisible { self.showPanel() }
                }
            }
            .store(in: &cancellables)
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        positionPanel()
        panel.alphaValue = 0
        // 桌面层窗口：只显示在桌面，不抢焦点、不盖住其他应用
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
        }
    }

    private func positionPanel() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let size = panel.frame.size
        var origin = NSPoint(x: screen.maxX - size.width - 16,
                             y: screen.maxY - size.height - 8)

        if let saved = UserDefaults.standard.string(forKey: "panelOrigin") {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                origin = NSPoint(x: parts[0], y: parts[1])
            }
        } else if let button = statusItem.button, let win = button.window {
            let rect = win.convertToScreen(button.convert(button.bounds, to: nil))
            if rect.width > 0, rect.midX > screen.midX {
                origin = NSPoint(x: rect.midX - size.width / 2,
                                 y: rect.minY - size.height - 6)
            }
        }

        origin.x = max(screen.minX + 8, min(origin.x, screen.maxX - size.width - 8))
        origin.y = max(screen.minY + 8, min(origin.y, screen.maxY - size.height - 8))

        isPositioning = true
        panel.setFrameOrigin(origin)
        isPositioning = false
    }

    func windowDidMove(_ notification: Notification) {
        guard !isPositioning, panel.isVisible else { return }
        let o = panel.frame.origin
        UserDefaults.standard.set("\(o.x),\(o.y)", forKey: "panelOrigin")
    }

    // MARK: - 右键菜单

    private func showMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: panel.isVisible ? "关闭面板" : "打开面板",
                                action: #selector(menuToggle), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let refresh = NSMenuItem(title: "立即刷新", action: #selector(menuRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let platform = NSMenuItem(title: "打开平台用量页", action: #selector(menuPlatform), keyEquivalent: "")
        platform.target = self
        menu.addItem(platform)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        if let button = statusItem.button {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: button.bounds.height + 4),
                       in: button)
        }
    }

    @objc private func menuToggle() { togglePanel() }
    @objc private func menuRefresh() { model.refresh() }
    @objc private func menuPlatform() {
        if let url = URL(string: "https://platform.deepseek.com/usage") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func updateStatusTitle() {
        statusItem.button?.title = model.balanceText
    }
}
