import SwiftUI

@main
struct CFSTApp: App {
    @StateObject private var store: AppStore
    @StateObject private var runner = SpeedTestRunner()
    @StateObject private var mapping: MappingService

    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _mapping = StateObject(wrappedValue: MappingService(store: store))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                SpeedTestView()
                    .tabItem { Label("测速", systemImage: "speedometer") }
                DomainsView()
                    .tabItem { Label("域名", systemImage: "globe") }
                SettingsView()
                    .tabItem { Label("设置", systemImage: "key") }
            }
            .environmentObject(store)
            .environmentObject(runner)
            .environmentObject(mapping)
        }
    }
}
