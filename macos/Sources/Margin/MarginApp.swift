import SwiftUI
import AppKit

@main
struct MarginApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Margin", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .defaultSize(width: 1320, height: 860)

        Window("Graphing Calculator", id: "calculator") {
            CalculatorView()
        }
        .defaultSize(width: 560, height: 660)

        Window("Reference", id: "reference") {
            ReferenceView()
        }
        .defaultSize(width: 420, height: 580)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the app is started with `swift run` instead of from an app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
