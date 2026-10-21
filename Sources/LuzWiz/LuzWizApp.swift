import SwiftUI

@main
struct LuzWizApp: App {
    @State private var store = LampStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
        } label: {
            Image(systemName: store.isOn ? "lightbulb.fill" : "lightbulb")
        }
        .menuBarExtraStyle(.window)
    }
}
