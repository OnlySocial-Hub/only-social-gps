import AppKit
import SwiftUI

extension AppModel {
    static let shared = AppModel()
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!
    private(set) var mainWindow: NSWindow?
    private var configured = false
    private var quitting = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        AppModel.shared.start()
        LocalBridge.shared.start() // loopback endpoint for the iPhone-Bot proxy connector
        // SwiftUI creates the window a beat after launch; configure it when it shows up.
        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey(_:)), name: NSWindow.didResignKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        DispatchQueue.main.async { self.configureMainWindowIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.configureMainWindowIfNeeded() }
        if !Env.isSnapshot { NSApp.activate(ignoringOtherApps: true) }
    }

    private func findMainWindow() -> NSWindow? {
        NSApp.windows.first { w in
            w.styleMask.contains(.titled) && !(w is NSPanel) && w.identifier?.rawValue.contains("main") == true
        } ?? NSApp.windows.first { w in
            w.styleMask.contains(.titled) && !(w is NSPanel) && w.contentView != nil && w.frame.width >= 600
        }
    }

    @MainActor func configureMainWindowIfNeeded() {
        guard !configured, let w = findMainWindow() else { return }
        configured = true
        mainWindow = w
        w.tabbingMode = .disallowed
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.styleMask.insert(.fullSizeContentView)
        w.isMovableByWindowBackground = true
        w.minSize = NSSize(width: 1000, height: 700)
        w.backgroundColor = NSColor(hex: 0x0E1118)
        w.isReleasedWhenClosed = false
        w.identifier = NSUserInterfaceItemIdentifier("OSGPS.main")
        if Env.isSnapshot {
            w.setContentSize(NSSize(width: 1280, height: 820))
            w.center()
            w.makeKeyAndOrderFront(nil)
            Snapshot.schedule(window: w)
        } else {
            w.setFrameAutosaveName("OSGPS.main")
            if w.frame.width < 1000 || w.frame.height < 700 {
                w.setContentSize(NSSize(width: 1280, height: 820))
                w.center()
            }
            w.makeKeyAndOrderFront(nil)
        }
        AppModel.shared.windowActive = true
    }

    @objc private func windowBecameKey(_ n: Notification) {
        configureMainWindowIfNeeded()
        if (n.object as? NSWindow) === mainWindow { AppModel.shared.windowActive = true }
    }
    @objc private func windowResignedKey(_ n: Notification) {
        if (n.object as? NSWindow) === mainWindow { AppModel.shared.windowActive = false }
    }
    @objc private func occlusionChanged(_ n: Notification) {
        guard let w = n.object as? NSWindow, w === mainWindow else { return }
        AppModel.shared.windowVisible = w.occlusionState.contains(.visible)
    }

    // MARK: Window helpers

    @MainActor func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSApplication.arrangeInFront(_:)), to: nil, from: nil)
        }
    }

    @MainActor func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let w = mainWindow { w.makeKeyAndOrderFront(nil); return false }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Quit (DESIGN.md §9.2)

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        if quitting { return .terminateLater }
        if model.anyHeld && !Env.isSnapshot {
            let n = model.heldCount
            let alert = NSAlert()
            alert.messageText = "Quitting returns \(n) phone\(n == 1 ? "" : "s") to \(n == 1 ? "its" : "their") real GPS."
            alert.informativeText = "Only Social GPS holds each phone's location only while it runs. Hide the window to keep them pinned."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Hide Window")
            let quit = alert.addButton(withTitle: "Quit and Release")
            quit.hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            if let w = mainWindow, w.isVisible {
                NSApp.activate(ignoringOtherApps: true)
            }
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                hideMainWindow()
                return .terminateCancel
            case .alertSecondButtonReturn:
                break
            default:
                return .terminateCancel
            }
        }
        quitting = true
        model.saveNow()
        Task { @MainActor in
            await model.shutdownEngine()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Utilities

    @MainActor func openLogFolder() {
        try? FileManager.default.createDirectory(at: Persistence.logDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Persistence.logDir)
    }

    @MainActor func showEngineLog() {
        let url = Persistence.engineLogURL
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) } else { openLogFolder() }
    }

    @MainActor func choosePython(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        panel.message = "Choose a python3 interpreter that has pymobiledevice3 installed"
        panel.prompt = "Use this Python"
        panel.begin { resp in
            if resp == .OK, let url = panel.url { completion(url.path) }
        }
    }
}
