import AppKit
import SwiftUI

private final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var model: AppModel!
    private let hotKeys = HotKeyManager(globalSequencesEnabled: !CommandLine.arguments.contains("--preview"))
    private var statusItem: NSStatusItem!
    private var panel: CommandPanel!
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var setupTimer: Timer?
    private var permissionGuideShown = false
    private var previousApp: NSRunningApplication?
    private var keyboardMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.fangjun.personalai"
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: []); NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        do {
            let preview = CommandLine.arguments.contains("--preview")
            let directory: URL? = preview ? FileManager.default.temporaryDirectory.appendingPathComponent("Wisp-Preview", isDirectory: true) : nil
            model = AppModel(disk: try DiskStore(directory: directory))
            if preview { model.clipboard.paused = true }
        } catch {
            let alert = NSAlert(); alert.messageText = "无法启动 Wisp"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil); return
        }
        installMainMenu()
        createPanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Wisp")
        statusItem.button?.toolTip = "Wisp · 快捷动作与剪贴板"
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu; updateMenu(menu)
        model.onHide = { [weak self] in self?.hidePanel() }
        model.localOpener = { [weak self] url in
            guard NSWorkspace.shared.open(url) else { return false }
            self?.hidePanel(restoreFocus: false)
            return true
        }
        model.urlOpener = model.localOpener
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onPaste = { [weak self] in self?.pasteToPreviousApp() }
        model.onHandoff = { [weak self] _ in self?.handoffToDoubao() }
        model.onSave = { [weak self] settings in try self?.registerShortcuts(settings) }
        model.onSetup = { [weak self] page in self?.showSetup(page) }
        model.onRefreshPermissions = { [weak self] in self?.refreshSetup() }
        hotKeys.onMonitorChange = { [weak self] state in self?.model.setup.updateMonitor(state) }
        hotKeys.onBackgroundEvent = { [weak self] in self?.model.setup.receivedBackgroundEvent() }
        hotKeys.onTrigger = { [weak self] key, background in self?.model.setup.triggered(key, background: background) }
        model.onDidSave = { [weak self] old, updated in
            guard let self else { return }
            if old.launcherHotKey != updated.launcherHotKey || old.clipboardHotKey != updated.clipboardHotKey || old.workflowsHotKey != updated.workflowsHotKey || old.workflows != updated.workflows || old.keySequenceInterval != updated.keySequenceInterval { self.model.setup.configurationChanged() }
            self.refreshSetup()
            let newlyEnabled = (!self.model.setup.needsPermission(old) && self.model.setup.needsPermission(updated)) || (!old.hasKeySequences && updated.hasKeySequences) || (!old.pasteOnSelect && updated.pasteOnSelect) || (!old.doubaoPaste && updated.doubaoPaste)
            if newlyEnabled && !self.model.setup.accessibilityGranted && !self.permissionGuideShown {
                self.permissionGuideShown = true
                DispatchQueue.main.async { [weak self] in self?.showSetup(.permissions) }
            }
        }
        model.onRecording = { [weak self] recording in
            do { try self?.hotKeys.setRecording(recording) }
            catch { self?.model.showError(error) }
        }
        do { try registerShortcuts(model.settings) } catch { model.showError(error) }
        model.clipboard.start()
        installKeyboardMonitor()
        setupTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshSetup() } }
        RunLoop.main.add(setupTimer!, forMode: .common)
        if model.setup.needsFirstRun { showSetup(model.settings.hasKeySequences && !model.setup.accessibilityGranted ? .permissions : .shortcuts) }
        else { show(.actions) }
    }
    private func createPanel() {
        panel = CommandPanel(contentRect: NSRect(x: 0, y: 0, width: 1140, height: 620), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow; panel.delegate = self
        panel.contentView = NSHostingView(rootView: PanelView(model: model, clipboard: model.clipboard, setup: model.setup))
    }
    private func registerShortcuts(_ settings: Settings) throws {
        var bindings: [HotKeyManager.Binding] = [
            (settings.launcherHotKey, { [weak self] in self?.toggle(.actions) }),
            (settings.clipboardHotKey, { [weak self] in self?.toggle(.clipboard) }),
            (settings.workflowsHotKey, { [weak self] in self?.toggle(.workflows) })
        ]
        for workflow in settings.workflows where workflow.enabled {
            if let key = workflow.hotKey { bindings.append((key, { [weak self] in self?.show(.workflows, workflow: workflow.id) })) }
        }
        if CommandLine.arguments.contains("--preview") { bindings = bindings.filter { $0.0.isSequence } }
        try hotKeys.apply(bindings, interval: settings.keySequenceInterval)
    }
    private func toggle(_ mode: PanelMode) {
        if panel.isVisible && panel.isKeyWindow && model.mode == mode { hidePanel() }
        else { show(mode) }
    }
    private func show(_ mode: PanelMode, workflow: UUID? = nil) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        model.open(mode, workflow: workflow)
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let width = min(1140, frame.width - 32), height = min(620, frame.height - 48)
            panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2 + frame.height * 0.08, width: width, height: height), display: true)
        }
        NSApp.activate(); panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in self?.model.focusToken = UUID() }
    }
    private func hidePanel(restoreFocus: Bool = true) {
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate(options: []) }
    }
    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { panel.orderOut(nil) }
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow { try? hotKeys.setRecording(false) }
    }
    private func pasteToPreviousApp() {
        let target = previousApp
        hidePanel()
        guard AXIsProcessTrusted() else { model.status = "已复制；自动粘贴需要辅助功能授权"; showSetup(.permissions); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let target, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { self?.model.status = "已复制；目标应用焦点已变化，请手动粘贴"; return }
            Self.sendPaste()
        }
    }
    private static func sendPaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState), let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true), let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand; up.flags = .maskCommand; down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    private func handoffToDoubao() {
        let settings = model.settings
        let path = (settings.doubaoAppPath as NSString).expandingTildeInPath
        if !path.isEmpty {
            guard FileManager.default.fileExists(atPath: path) else { model.showError(AppError.message("豆包应用路径不存在，请在设置中重新选择。")); return }
            hidePanel(restoreFocus: false)
            let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { [weak self] app, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error { self.model.showError(error); self.panel.makeKeyAndOrderFront(nil); return }
                    self.model.status = "内容已复制，请在豆包输入框按 ⌘V 后发送"
                    guard settings.doubaoPaste, AXIsProcessTrusted(), let app else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                        Self.sendPaste(); self?.model.status = "已向豆包应用粘贴，请检查输入框后发送"
                    }
                }
            }
        } else {
            guard let url = URL(string: settings.doubaoURL), ["https", "http", "doubao"].contains(url.scheme ?? "") else { model.showError(AppError.message("豆包链接无效，请检查设置。")); return }
            hidePanel(restoreFocus: false)
            if NSWorkspace.shared.open(url) { model.status = "内容已复制，请在豆包输入框按 ⌘V 后发送" }
            else { model.showError(AppError.message("无法打开豆包链接。")); panel.makeKeyAndOrderFront(nil) }
        }
    }
    @objc private func showSettings() {
        openSettings(nil)
    }
    private func openSettings(_ page: SettingsPage?) {
        try? hotKeys.setRecording(false)
        hidePanel(restoreFocus: false)
        setupWindow?.orderOut(nil)
        if let page { model.requestedSettingsPage = page }
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            settingsWindow?.title = "Wisp 设置"; settingsWindow?.minSize = NSSize(width: 940, height: 680)
            settingsWindow?.isReleasedWhenClosed = false; settingsWindow?.delegate = self; settingsWindow?.center()
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(model: model))
        }
        NSApp.activate(); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private func refreshSetup() { model.setup.refresh(); hotKeys.refreshGlobalMonitor() }
    @objc private func openSetup() { showSetup(.shortcuts) }
    private func showSetup(_ page: SetupPage) {
        try? hotKeys.setRecording(false)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = NSWorkspace.shared.frontmostApplication }
        hidePanel(restoreFocus: false); settingsWindow?.orderOut(nil)
        model.setup.page = page; model.setup.presented(); refreshSetup()
        if setupWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Wisp 配置引导"; window.minSize = NSSize(width: 760, height: 670); window.isReleasedWhenClosed = false; window.center()
            window.contentView = NSHostingView(rootView: SetupGuideView(model: model, setup: model.setup, openSettings: { [weak self] page in self?.openSettings(page) }, testShortcut: { [weak self] in self?.beginBackgroundTest() }, close: { [weak self] completed in
                guard let self else { return }
                if completed { self.model.setup.finish() }
                self.setupWindow?.orderOut(nil); self.show(.actions)
            }))
            setupWindow = window
        }
        NSApp.activate(); setupWindow?.makeKeyAndOrderFront(nil)
    }
    private func beginBackgroundTest() {
        guard !CommandLine.arguments.contains("--preview") else { return }
        refreshSetup()
        let key = model.settings.launcherHotKey
        guard !key.isSequence || (model.setup.accessibilityGranted && !model.setup.secureInput && model.setup.monitor == .listening) else { return }
        model.setup.beginTest(key)
        setupWindow?.orderOut(nil); settingsWindow?.orderOut(nil); panel.orderOut(nil)
        let target = previousApp?.isTerminated == false && previousApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier ? previousApp : NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        if let target, target.activate(options: []) { return }
        NSApp.hide(nil)
    }
    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                switch event.charactersIgnoringModifiers {
                case "1": self.model.switchMode(.actions); return nil
                case "2": self.model.switchMode(.clipboard); return nil
                case "3": self.model.switchMode(.workflows); return nil
                case ",": self.showSettings(); return nil
                case "p" where self.model.mode == .clipboard:
                    if let clip = self.model.selectedClip { self.model.clipboard.togglePin(clip.id) }; return nil
                default: break
                }
                if event.keyCode == 51 && self.model.mode == .clipboard {
                    if let clip = self.model.selectedClip { self.model.clipboard.delete(clip.id); self.model.selection = 0 }; return nil
                }
            }
            if event.keyCode == 53 { self.hidePanel(); return nil }
            return event
        }
    }
    func menuWillOpen(_ menu: NSMenu) { updateMenu(menu) }
    private func updateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        addMenuItem(menu, "快捷动作    \(model.settings.launcherHotKey.display)", #selector(openActions))
        addMenuItem(menu, "剪贴板历史    \(model.settings.clipboardHotKey.display)", #selector(openClipboard))
        addMenuItem(menu, "工作流程    \(model.settings.workflowsHotKey.display)", #selector(openWorkflows))
        menu.addItem(.separator())
        addMenuItem(menu, model.clipboard.paused ? "恢复剪贴板记录" : "暂停剪贴板记录", #selector(toggleClipboard))
        let status = NSMenuItem(title: model.status, action: nil, keyEquivalent: ""); status.isEnabled = false; menu.addItem(status)
        menu.addItem(.separator())
        addMenuItem(menu, "设置…", #selector(showSettings))
        addMenuItem(menu, "配置引导与后台诊断…", #selector(openSetup))
        addMenuItem(menu, "退出 Wisp", #selector(quit))
    }
    private func addMenuItem(_ menu: NSMenu, _ title: String, _ action: Selector) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    @objc private func openActions() { show(.actions) }
    @objc private func openClipboard() { show(.clipboard) }
    @objc private func openWorkflows() { show(.workflows) }
    @objc private func toggleClipboard() { model.clipboard.paused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(); appItem.submenu = appMenu; main.addItem(appItem)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ","); settings.target = self; appMenu.addItem(settings)
        let setup = NSMenuItem(title: "配置引导…", action: #selector(openSetup), keyEquivalent: ""); setup.target = self; appMenu.addItem(setup)
        appMenu.addItem(NSMenuItem(title: "退出 Wisp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "编辑"); edit.submenu = editMenu; main.addItem(edit)
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        NSApp.mainMenu = main
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let setupWindow, setupWindow.isVisible { setupWindow.makeKeyAndOrderFront(nil) }
        else if panel.isVisible { panel.makeKeyAndOrderFront(nil); model.focusToken = UUID() }
        else if let settingsWindow, settingsWindow.isVisible { settingsWindow.makeKeyAndOrderFront(nil) }
        else { show(.actions) }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { setupTimer?.invalidate(); model?.cancel(); model?.stopLocalSearch(); hotKeys.stop(); if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) } }
}
