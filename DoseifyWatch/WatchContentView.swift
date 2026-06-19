import SwiftUI

struct WatchContentView: View {
    @ObservedObject private var sync = WatchConnectivityService.shared

    var body: some View {
        NavigationStack {
            Group {
                if sync.doses.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sync.doses) { dose in
                            DoseRow(dose: dose) { sync.logDose(dose) }
                        }
                    }
                }
            }
            .navigationTitle("Doseify")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.48, green: 0.62, blue: 0.53))
            Text("All caught up")
                .font(.headline)
            Text("No doses due right now.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .containerBackground(.background, for: .navigation)
    }
}

private struct DoseRow: View {
    let dose: WatchDose
    let onTake: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: dose.colorHex))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(dose.medName).font(.body).lineLimit(1)
                Text(dose.scheduledTime, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onTake) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.48, green: 0.62, blue: 0.53))
        }
        .swipeActions(edge: .trailing) {
            Button(action: onTake) { Label("Take", systemImage: "checkmark") }
                .tint(Color(red: 0.48, green: 0.62, blue: 0.53))
        }
    }
}

private extension Color {
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v & 0xFF0000) >> 16) / 255
        let g = Double((v & 0x00FF00) >> 8) / 255
        let b = Double(v & 0x0000FF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
