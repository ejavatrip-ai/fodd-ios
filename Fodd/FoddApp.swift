import SwiftUI

@main
struct FoddApp: App {
    @UIApplicationDelegateAdaptor(FoddAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    init() {
        FoddAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store) }
    }
}
