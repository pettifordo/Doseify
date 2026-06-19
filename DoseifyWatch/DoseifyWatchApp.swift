import SwiftUI

@main
struct DoseifyWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .onAppear { WatchConnectivityService.shared.start() }
                // The complication opens the app via doseify://log; the dose list
                // is already the root, so just make sure the session is live.
                .onOpenURL { _ in WatchConnectivityService.shared.start() }
        }
    }
}
