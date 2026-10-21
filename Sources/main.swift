// ClickPaste for macOS — a menu bar app that types the clipboard as keystrokes.
//
// Useful for VMs, remote consoles (VNC, iDRAC/iLO, Proxmox, etc.) and any other
// window where normal paste doesn't work.
//
// Left-click the menu bar icon, then click the target window: the clipboard is typed into it.
// Right-click the icon for options. The hotkey (⌃⌥V) types into whatever window is focused.
// Press Esc while it's typing to stop.

import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Settings

enum Settings {
    static let d = UserDefaults.standard

    static var keyDelayMs: Int {
        get { d.object(forKey: "keyDelayMs") as? Int ?? 10 }
        set { d.set(newValue, forKey: "keyDelayMs") }
    }
    static var startDelayMs: Int {
        get { d.object(forKey: "startDelayMs") as? Int ?? 500 }
        set { d.set(newValue, forKey: "startDelayMs") }
    }
    static var hotkeyEnabled: Bool {
        get { d.object(forKey: "hotkeyEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "hotkeyEnabled") }
    }
    static var useScancodes: Bool {
        get { d.object(forKey: "useScancodes") as? Bool ?? true }
        set { d.set(newValue, forKey: "useScancodes") }
    }
}

// MARK: - Keyboard layout map (character -> virtual keycode + modifiers)

struct KeyStroke {
    let code: CGKeyCode
    let shift: Bool
    let option: Bool
}

enum KeyMap {
    /// Builds a reverse map from the *current* keyboard layout so typed keys are real keypresses,
    /// which VMs and remote consoles understand (they ignore unicode-only events).
    static func build() -> [UInt32: KeyStroke] {
        var map: [UInt32: KeyStroke] = [:]
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return map
        }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data

        // Carbon modifier state is (modifiers >> 8) & 0xFF: shift = 0x02, option = 0x08.
        let combos: [(UInt32, Bool, Bool)] = [(0, false, false), (0x02, true, false), (0x08, false, true), (0x0A, true, true)]

        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            for (mods, shift, option) in combos {
                for code in 0..<128 {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), mods,
                                                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                                &deadKeyState, chars.count, &length, &chars)
                    guard status == noErr, length == 1 else { continue }
                    let scalar = UInt32(chars[0])
                    if scalar < 0x20 || scalar == 0x7F { continue } // control chars handled separately
                    if map[scalar] == nil {
                        map[scalar] = KeyStroke(code: CGKeyCode(code), shift: shift, option: option)
                    }
                }
            }
        }
        map[0x0A] = KeyStroke(code: CGKeyCode(kVK_Return), shift: false, option: false) // \n
        map[0x0D] = KeyStroke(code: CGKeyCode(kVK_Return), shift: false, option: false) // \r
        map[0x09] = KeyStroke(code: CGKeyCode(kVK_Tab), shift: false, option: false)    // \t
        return map
    }
}

// MARK: - Typist

final class Typist {
    private let lock = NSLock()
    private var _cancelled = false
    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }

    private let source = CGEventSource(stateID: .hidSystemState)

    func type(_ text: String, keyDelayMs: Int, useScancodes: Bool) {
        cancelled = false
        let map = useScancodes ? KeyMap.build() : [:]
        let keyDelay = useconds_t(max(0, keyDelayMs) * 1000)
        var previous: UInt32 = 0

        for scalar in text.unicodeScalars {
            if cancelled { break }
            let v = scalar.value
            defer { previous = v }
            if v == 0x0A && previous == 0x0D { continue } // treat \r\n as a single Enter

            if let stroke = map[v] {
                press(stroke)
            } else if v == 0x0A || v == 0x0D {
                press(KeyStroke(code: CGKeyCode(kVK_Return), shift: false, option: false))
            } else if v == 0x09 {
                press(KeyStroke(code: CGKeyCode(kVK_Tab), shift: false, option: false))
            } else {
                typeUnicode(String(scalar))
            }
            if keyDelay > 0 { usleep(keyDelay) }
        }
        releaseModifiers()
    }

    private func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    private func press(_ k: KeyStroke) {
        var flags: CGEventFlags = []
        // Press real modifier keys so VMs that track modifier state see them.
        if k.shift {
            flags.insert(.maskShift)
            post(CGKeyCode(kVK_Shift), down: true, flags: flags)
        }
        if k.option {
            flags.insert(.maskAlternate)
            post(CGKeyCode(kVK_Option), down: true, flags: flags)
        }
        post(k.code, down: true, flags: flags)
        usleep(2000)
        post(k.code, down: false, flags: flags)
        if k.option {
            flags.remove(.maskAlternate)
            post(CGKeyCode(kVK_Option), down: false, flags: flags)
        }
        if k.shift {
            flags.remove(.maskShift)
            post(CGKeyCode(kVK_Shift), down: false, flags: flags)
        }
    }

    private func typeUnicode(_ s: String) {
        let utf16 = Array(s.utf16)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            e.flags = []
            e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            e.post(tap: .cghidEventTap)
        }
    }

    private func releaseModifiers() {
        post(CGKeyCode(kVK_Shift), down: false, flags: [])
        post(CGKeyCode(kVK_Option), down: false, flags: [])
    }
}

// MARK: - Global hotkey (Carbon, no extra permission needed)

final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    static var onPress: (() -> Void)?

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x434C5053) /* 'CLPS' */, id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let typist = Typist()
    private let hotKey = HotKey()

    private var clickMonitor: Any?
    private var escMonitorGlobal: Any?
    private var escMonitorLocal: Any?
    private var isTyping = false
    private var isArmed = false

    private let keyDelayOptions = [0, 5, 10, 20, 50, 100]
    private let startDelayOptions = [250, 500, 1000, 2000, 3000]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ClickPaste — click, then click the target window"
        }
        setIcon("doc.on.clipboard")
        menu.delegate = self

        HotKey.onPress = { [weak self] in self?.hotkeyPressed() }
        applyHotkey()

        // Esc cancels typing (global monitor needs Accessibility, which we need anyway).
        escMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == UInt16(kVK_Escape) { self?.cancelAll() }
        }
        escMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == UInt16(kVK_Escape) { self?.cancelAll() }
            return e
        }

        ensureAccessibility(prompt: true)
    }

    // MARK: Icon

    private func setIcon(_ symbol: String) {
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "ClickPaste")
        img?.isTemplate = true
        statusItem.button?.image = img
    }

    private func refreshIcon() {
        if isTyping { setIcon("keyboard") }
        else if isArmed { setIcon("scope") }
        else { setIcon("doc.on.clipboard") }
    }

    // MARK: Click handling

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        let isRight = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRight {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if isTyping || isArmed {
            cancelAll()
        } else {
            arm()
        }
    }

    private func arm() {
        guard ensureAccessibility(prompt: true) else { return }
        guard clipboardText() != nil else { NSSound.beep(); return }
        isArmed = true
        refreshIcon()
        // Watch for the next click anywhere else. The click still goes through, focusing the target window.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.disarm()
            self.typeClipboard(afterMs: max(Settings.startDelayMs, 250), waitForModifiers: false)
        }
    }

    private func disarm() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        isArmed = false
        refreshIcon()
    }

    private func cancelAll() {
        if isArmed { disarm() }
        if isTyping { typist.cancelled = true }
    }

    private func hotkeyPressed() {
        guard !isTyping else { typist.cancelled = true; return }
        guard ensureAccessibility(prompt: true) else { return }
        if isArmed { disarm() }
        typeClipboard(afterMs: Settings.startDelayMs, waitForModifiers: true)
    }

    // MARK: Typing

    private func clipboardText() -> String? {
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return nil }
        return s
    }

    private func typeClipboard(afterMs delayMs: Int, waitForModifiers: Bool) {
        guard let text = clipboardText() else { NSSound.beep(); return }

        if text.count > 2000 {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Type \(text.count) characters?"
            alert.informativeText = "The clipboard is long. Press Esc at any time to stop typing.\n\nAfter you click Type, switch to the target window within 3 seconds."
            alert.addButton(withTitle: "Type")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            startTyping(text, afterMs: 3000, waitForModifiers: false)
            return
        }
        startTyping(text, afterMs: delayMs, waitForModifiers: waitForModifiers)
    }

    private func startTyping(_ text: String, afterMs delayMs: Int, waitForModifiers: Bool) {
        isTyping = true
        typist.cancelled = false
        refreshIcon()
        let keyDelay = Settings.keyDelayMs
        let scancodes = Settings.useScancodes

        DispatchQueue.global(qos: .userInitiated).async { [typist] in
            if waitForModifiers {
                // Wait (up to 3s) until the user lets go of the hotkey modifiers so they don't mix into the typing.
                let mods: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
                let deadline = Date().addingTimeInterval(3)
                while !CGEventSource.flagsState(.combinedSessionState).intersection(mods).isEmpty, Date() < deadline {
                    usleep(20_000)
                }
            }
            usleep(useconds_t(delayMs * 1000))
            if !typist.cancelled {
                typist.type(text, keyDelayMs: keyDelay, useScancodes: scancodes)
            }
            DispatchQueue.main.async {
                self.isTyping = false
                self.refreshIcon()
            }
        }
    }

    // MARK: Permissions

    @discardableResult
    private func ensureAccessibility(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Hotkey

    private func applyHotkey() {
        if Settings.hotkeyEnabled {
            hotKey.register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey))
        } else {
            hotKey.unregister()
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let preview: String
        if let t = clipboardText() {
            let oneLine = t.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\t", with: "⇥")
            preview = "Clipboard: " + (oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine) + "  (\(t.count) chars)"
        } else {
            preview = "Clipboard: (no text)"
        }
        let previewItem = NSMenuItem(title: preview, action: nil, keyEquivalent: "")
        previewItem.isEnabled = false
        menu.addItem(previewItem)
        menu.addItem(.separator())

        if isTyping {
            menu.addItem(item("Stop Typing (Esc)", #selector(menuStop)))
        } else {
            menu.addItem(item("Click Target Window to Type…", #selector(menuArm)))
            menu.addItem(item("Type Into Focused Window in 3s", #selector(menuTypeIn3)))
        }
        menu.addItem(.separator())

        let keyDelayMenu = NSMenu()
        for ms in keyDelayOptions {
            let i = item(ms == 0 ? "None" : "\(ms) ms", #selector(setKeyDelay(_:)))
            i.tag = ms
            i.state = Settings.keyDelayMs == ms ? .on : .off
            keyDelayMenu.addItem(i)
        }
        let kd = NSMenuItem(title: "Delay Between Keys", action: nil, keyEquivalent: "")
        kd.submenu = keyDelayMenu
        menu.addItem(kd)

        let startDelayMenu = NSMenu()
        for ms in startDelayOptions {
            let i = item(ms < 1000 ? "\(ms) ms" : "\(ms / 1000) s", #selector(setStartDelay(_:)))
            i.tag = ms
            i.state = Settings.startDelayMs == ms ? .on : .off
            startDelayMenu.addItem(i)
        }
        let sd = NSMenuItem(title: "Delay Before Typing", action: nil, keyEquivalent: "")
        sd.submenu = startDelayMenu
        menu.addItem(sd)

        let scan = item("Send Real Keypresses (for VMs/Remote)", #selector(toggleScancodes))
        scan.state = Settings.useScancodes ? .on : .off
        scan.toolTip = "On: types using real key codes for your keyboard layout (works in VMs, VNC, remote consoles).\nOff: sends unicode text events (only works in native Mac apps)."
        menu.addItem(scan)

        let hk = item("Hotkey ⌃⌥V Types Clipboard", #selector(toggleHotkey))
        hk.state = Settings.hotkeyEnabled ? .on : .off
        menu.addItem(hk)

        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        if !ensureAccessibility(prompt: false) {
            menu.addItem(item("⚠️ Grant Accessibility Permission…", #selector(openAccessibility)))
        }
        menu.addItem(item("Quit ClickPaste", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func menuArm() { arm() }
    @objc private func menuStop() { cancelAll() }
    @objc private func menuTypeIn3() {
        guard ensureAccessibility(prompt: true) else { return }
        typeClipboard(afterMs: 3000, waitForModifiers: false)
    }
    @objc private func setKeyDelay(_ sender: NSMenuItem) { Settings.keyDelayMs = sender.tag }
    @objc private func setStartDelay(_ sender: NSMenuItem) { Settings.startDelayMs = sender.tag }
    @objc private func toggleScancodes() { Settings.useScancodes.toggle() }
    @objc private func toggleHotkey() {
        Settings.hotkeyEnabled.toggle()
        applyHotkey()
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Couldn't change Launch at Login"
            a.informativeText = "\(error.localizedDescription)\n\nTip: move ClickPaste.app into /Applications first."
            a.runModal()
        }
    }
    @objc private func openAccessibility() {
        ensureAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
