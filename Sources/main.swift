import AppKit
import Carbon
import ServiceManagement

// MARK: - Input sources

struct InputSource {
    let id: String
    let name: String
    let ref: TISInputSource
}

enum InputSources {
    /// All enabled, selectable keyboard input sources (layouts and input method modes).
    static func all() -> [InputSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.compactMap { src in
            // The parent of a mode-enabled input method duplicates its modes; skip it.
            if string(src, kTISPropertyInputSourceType) == kTISTypeKeyboardInputMethodModeEnabled as String {
                return nil
            }
            guard let id = string(src, kTISPropertyInputSourceID),
                  let name = string(src, kTISPropertyLocalizedName) else { return nil }
            return InputSource(id: id, name: name, ref: src)
        }
    }

    static var currentID: String? {
        string(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID)
    }

    @discardableResult
    static func select(id: String) -> Bool {
        if currentID == id { return true }
        guard let src = all().first(where: { $0.id == id }) else { return false }
        return TISSelectInputSource(src.ref) == noErr
    }

    private static func string(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? String
    }
}

// MARK: - Rules

final class RuleStore {
    private let defaults = UserDefaults.standard
    private let rulesKey = "rules"
    private let defaultKey = "defaultSource"

    /// bundle ID -> input source ID
    var rules: [String: String] {
        get { defaults.dictionary(forKey: rulesKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: rulesKey) }
    }

    /// Input source for apps without a rule; nil means leave the input source alone.
    var defaultSource: String? {
        get { defaults.string(forKey: defaultKey) }
        set { defaults.set(newValue, forKey: defaultKey) }
    }

    func source(for bundleID: String) -> String? {
        rules[bundleID] ?? defaultSource
    }

    func setRule(_ bundleID: String, _ sourceID: String?) {
        var r = rules
        r[bundleID] = sourceID
        rules = r
    }
}

// MARK: - Menu helpers

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

func appName(for bundleID: String) -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    return bundleID
}

func appIcon(for bundleID: String) -> NSImage? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    icon.size = NSSize(width: 16, height: 16)
    return icon
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let store = RuleStore()
    private var lastBundleID: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "InputPrimary")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if let app = NSWorkspace.shared.frontmostApplication { handle(app) }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        handle(app)
    }

    private func handle(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return }
        lastBundleID = bundleID
        apply(bundleID)
    }

    private func apply(_ bundleID: String) {
        guard let target = store.source(for: bundleID) else { return }
        InputSources.select(id: target)
        // The system (or the app) may restore its own input source right after activation; re-assert once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard self?.lastBundleID == bundleID else { return }
            InputSources.select(id: target)
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let sources = InputSources.all()

        if let bundleID = lastBundleID {
            let item = NSMenuItem(title: "“\(appName(for: bundleID))” 使用", action: nil, keyEquivalent: "")
            item.image = appIcon(for: bundleID)
            item.submenu = sourceMenu(sources, selected: store.rules[bundleID], noneTitle: "跟随默认") { [weak self] id in
                self?.store.setRule(bundleID, id)
                self?.apply(bundleID)
            }
            menu.addItem(item)
        }

        let defaultItem = NSMenuItem(title: "其他应用默认使用", action: nil, keyEquivalent: "")
        defaultItem.submenu = sourceMenu(sources, selected: store.defaultSource, noneTitle: "不切换") { [weak self] id in
            self?.store.defaultSource = id
        }
        menu.addItem(defaultItem)

        let rules = store.rules.sorted { appName(for: $0.key).localizedStandardCompare(appName(for: $1.key)) == .orderedAscending }
        if !rules.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "已设置的应用", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for (bundleID, sourceID) in rules {
                let sourceName = sources.first(where: { $0.id == sourceID })?.name ?? sourceID
                let item = NSMenuItem(title: "\(appName(for: bundleID)) → \(sourceName)", action: nil, keyEquivalent: "")
                item.image = appIcon(for: bundleID)
                item.submenu = sourceMenu(sources, selected: sourceID, noneTitle: "删除规则") { [weak self] id in
                    self?.store.setRule(bundleID, id)
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let loginEnabled = SMAppService.mainApp.status == .enabled
        menu.addItem(ClosureMenuItem("登录时启动", checked: loginEnabled) {
            do {
                if loginEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
            } catch {
                NSAlert(error: error).runModal()
            }
        })
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func sourceMenu(_ sources: [InputSource], selected: String?, noneTitle: String,
                            onSelect: @escaping (String?) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(noneTitle, checked: selected == nil) { onSelect(nil) })
        menu.addItem(.separator())
        for source in sources {
            menu.addItem(ClosureMenuItem(source.name, checked: source.id == selected) { onSelect(source.id) })
        }
        return menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
