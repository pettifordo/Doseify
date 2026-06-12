import SwiftUI
import SwiftData

struct AdherenceView: View {
    @Query(sort: \DoseEvent.effectiveScheduledTime) private var allDoses: [DoseEvent]
    @Query private var medications: [Medication]

    @State private var reportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statsGrid
                    heatmapSection
                    perMedSection
                    streakSection
                }
                .padding()
                .padding(.bottom, 32)
            }
            .background(Color.doseBackground)
            .navigationTitle("Adherence")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let reportURL {
                        ShareLink(item: reportURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task(id: allDoses.count) {
                reportURL = AdherenceReportPDF.generate(doses: allDoses, medications: medications)
            }
        }
    }

    // MARK: - Calendar heat-map (last 5 weeks)

    private var heatmapSection: some View {
        let days = AdherenceCalculator.dailyBreakdown(for: allDoses, days: 35)
        let leadingBlanks = days.first.map {
            Calendar.current.component(.weekday, from: $0.day) - 1   // Sun-first
        } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Last 5 weeks")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3).fill(Color.clear).frame(height: 22)
                }
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cellColor(day))
                        .frame(height: 22)
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.5, 0.99, 1.0], id: \.self) { f in
                    RoundedRectangle(cornerRadius: 2).fill(heatColor(f)).frame(width: 14, height: 14)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func cellColor(_ d: AdherenceCalculator.DayAdherence) -> Color {
        guard let f = d.fraction else { return Color.secondary.opacity(0.12) }
        return heatColor(f)
    }

    private func heatColor(_ f: Double) -> Color {
        switch f {
        case 1.0...:      return Color.doseSage
        case 0.67..<1.0:  return Color.doseSage.opacity(0.6)
        case 0.34..<0.67: return .orange
        default:          return .red.opacity(0.7)
        }
    }

    // MARK: - Per-medication breakdown (30 days)

    private var perMedSection: some View {
        let active = medications.filter { $0.isActive }.sorted { $0.name < $1.name }
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("By medication · 30 days")
            if active.isEmpty {
                Text("No active medications yet.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(active) { med in
                    let medDoses = allDoses.filter { $0.medication?.id == med.id }
                    let s = AdherenceCalculator.rolling30Day(for: medDoses)
                    HStack(spacing: 12) {
                        Circle().fill(Color.fromHex(med.colorHex)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(med.name).font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(Int(s.adherencePercent))%")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(tint(s.adherencePercent))
                            }
                            ProgressView(value: s.adherencePercent / 100).tint(tint(s.adherencePercent))
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func tint(_ pct: Double) -> Color {
        pct >= 90 ? Color.doseSage : pct >= 70 ? .orange : .red
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsGrid: some View {
        let w7  = AdherenceCalculator.rolling7Day(for: allDoses)
        let w30 = AdherenceCalculator.rolling30Day(for: allDoses)
        let w90 = AdherenceCalculator.rolling90Day(for: allDoses)
        let all = AdherenceCalculator.allTime(for: allDoses)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "7 days",   adherence: w7.adherencePercent,  score: w7.averageOnTimeScore)
            StatCard(title: "30 days",  adherence: w30.adherencePercent, score: w30.averageOnTimeScore)
            StatCard(title: "90 days",  adherence: w90.adherencePercent, score: w90.averageOnTimeScore)
            StatCard(title: "All time", adherence: all.adherencePercent, score: all.averageOnTimeScore)
        }
    }

    private var streakSection: some View {
        let stats = AdherenceCalculator.allTime(for: allDoses)
        return VStack(spacing: 12) {
            HStack {
                streakBox(label: "Current streak", value: stats.currentStreak, icon: "flame.fill", color: .orange)
                streakBox(label: "Longest streak", value: stats.longestStreak, icon: "trophy.fill", color: Color.doseSage)
            }
        }
    }

    private func streakBox(label: String, value: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text("\(value)").font(.title.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

struct StatCard: View {
    let title: String
    let adherence: Double
    let score: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(Int(adherence))%").font(.title2.bold())
            ProgressView(value: adherence / 100)
                .tint(tintColor(adherence))
            Text("avg score \(Int(score))%").font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private func tintColor(_ pct: Double) -> Color {
        pct >= 90 ? Color.doseSage : pct >= 70 ? .orange : .red
    }
}
