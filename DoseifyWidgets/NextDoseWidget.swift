import WidgetKit
import SwiftUI

struct NextDoseEntry: TimelineEntry {
    let date: Date
    let medicationName: String
    let nextDoseTime: Date?
}

struct NextDoseProvider: TimelineProvider {

    func placeholder(in context: Context) -> NextDoseEntry {
        NextDoseEntry(date: Date(), medicationName: "Ibrutinib", nextDoseTime: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (NextDoseEntry) -> Void) {
        completion(NextDoseEntry(date: Date(), medicationName: "Ibrutinib", nextDoseTime: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDoseEntry>) -> Void) {
        // Full SwiftData access from widget requires App Group — wired up in phase 4.
        let entry = NextDoseEntry(date: Date(), medicationName: "–", nextDoseTime: nil)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct NextDoseWidgetView: View {
    let entry: NextDoseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Doseify", systemImage: "pill.fill")
                .font(.caption2.bold())
                .foregroundStyle(Color(red: 0.48, green: 0.62, blue: 0.53))

            if let next = entry.nextDoseTime {
                Text(entry.medicationName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(next, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("All done today")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(red: 0.48, green: 0.62, blue: 0.53))
            }
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }
}

struct NextDoseWidget: Widget {
    let kind = "NextDoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextDoseProvider()) { entry in
            NextDoseWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("Shows your next upcoming dose.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
