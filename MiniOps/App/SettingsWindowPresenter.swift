import AppKit
import SwiftUI

@MainActor
final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              SettingsWindowPresenter.isSettingsWindow(window) else { return }

        let otherSettingsVisible = NSApp.windows.contains {
            $0 !== window && $0.isVisible && SettingsWindowPresenter.isSettingsWindow($0)
        }

        if !otherSettingsVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
enum SettingsWindowPresenter {
    static let windowTitle = "MiniOps 설정"
    private static let windowID = "settings"

    static func openOrFocus(openWindow: OpenWindowAction) {
        let existing = findSettingsWindow()

        dismissTransientWindows(keeping: existing)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = existing {
            focus(window)
            return
        }

        openWindow(id: windowID)
        scheduleFocus(attempt: 0)
    }

    static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.title == windowTitle
            || window.identifier?.rawValue == windowID
            || window.identifier?.rawValue.contains(windowID) == true
    }

    private static func dismissTransientWindows(keeping settingsWindow: NSWindow?) {
        for window in NSApp.windows {
            if window === settingsWindow { continue }
            guard window.isVisible else { continue }

            if isSettingsWindow(window) { continue }

            // MenuBarExtra 팝업이 설정 창 위에 남아 입력을 가로채는 경우 방지
            if window === NSApp.keyWindow || window.styleMask.contains(.nonactivatingPanel) {
                window.orderOut(nil)
            }
        }
    }

    private static func scheduleFocus(attempt: Int) {
        DispatchQueue.main.async {
            if let window = findSettingsWindow() {
                focus(window)
            } else if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    scheduleFocus(attempt: attempt + 1)
                }
            }
        }
    }

    private static func focus(_ window: NSWindow) {
        if window.delegate == nil {
            window.delegate = SettingsWindowDelegate.shared
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func findSettingsWindow() -> NSWindow? {
        NSApp.windows.first(where: isSettingsWindow)
    }
}
