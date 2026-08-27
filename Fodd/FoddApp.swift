import SwiftUI

@main
struct FoddApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store) }
    }
}
