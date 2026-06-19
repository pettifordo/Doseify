import SwiftUI

@main
struct DoseifyWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .onAppear { WatchConnectivityService.shared.start() }
        }
    }
}
