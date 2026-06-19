import WidgetKit
import SwiftUI

// A lightweight launcher complication: tapping it opens the Doseify Watch app on
// the dose list, where the user records a dose. It carries no live data, so it
// needs no App Group / extra entitlements (showing the next dose would — that's a
// future opt-in). watchOS launches the containing app on tap; the `widgetURL`
// lets it deep-link to the logging screen.

private let doseSage = Color(red: 0.48, green: 0.62, blue: 0.53)

struct LogEntry: TimelineEntry {
    let date: Date
}

struct LogProvider: TimelineProvider {
    func placeholder(in context: Context) -> LogEntry { LogEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (LogEntry) -> Void) {
        completion(LogEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LogEntry>) -> Void) {
        completion(Timeline(entries: [LogEntry(date: .now)], policy: .never))
    }
}

struct LogComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "pill.fill").foregroundStyle(doseSage)
            }
        case .accessoryCorner:
            Image(systemName: "pill.fill")
                .foregroundStyle(doseSage)
                .widgetLabel("Log dose")
        case .accessoryInline:
            Label("Log dose", systemImage: "pill.fill")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "pill.fill").foregroundStyle(doseSage)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Doseify").font(.headline)
                    Text("Tap to log a dose").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        default:
            Image(systemName: "pill.fill").foregroundStyle(doseSage)
        }
    }
}

struct LogComplication: Widget {
    let kind = "DoseifyLogComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogProvider()) { _ in
            LogComplicationView()
                .widgetURL(URL(string: "doseify://log"))
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Log a dose")
        .description("Open Doseify to record a dose.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct DoseifyComplicationBundle: WidgetBundle {
    var body: some Widget {
        LogComplication()
    }
}
