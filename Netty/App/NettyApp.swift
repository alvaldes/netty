import NettyKit
import SwiftUI

@main
struct NettyApp: App {
    var body: some Scene {
        MenuBarExtra("Netty", systemImage: "circle.fill") {
            Button("Quit Netty") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
