import SwiftUI

struct WatchContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "pill.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.48, green: 0.62, blue: 0.53))
            Text("Doseify")
                .font(.headline)
            Text("Open the iPhone app to log doses.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.background, for: .navigation)
    }
}
