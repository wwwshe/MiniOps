import AppKit
import SwiftUI

@MainActor
enum SettingsWindowPresenter {
    private static let windowTitle = "MiniOps 설정"
    private static let windowID = "settings"

    static func openOrFocus(openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = findSettingsWindow() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        openWindow(id: windowID)
    }

    private static func findSettingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window.title == windowTitle
                || window.identifier?.rawValue == windowID
                || window.identifier?.rawValue.contains(windowID) == true
        }
    }
}
