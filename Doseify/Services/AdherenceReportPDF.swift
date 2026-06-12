import Foundation
import UIKit

/// Renders a one-page adherence report PDF for sharing/printing (SPEC §2.8).
/// Pure presentation — reads dose data, writes a temp file, no persistence.
enum AdherenceReportPDF {

    /// Build the report and return a temp-file URL, or nil on failure.
    static func generate(doses: [DoseEvent], medications: [Medication], now: Date = Date()) -> URL? {
        let pageW: CGFloat = 612, pageH: CGFloat = 792   // US Letter @ 72dpi
        let margin: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))

        let df = DateFormatter(); df.dateStyle = .medium
        let stamp = ISO8601DateFormatter().string(from: now).prefix(10)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Doseify-Adherence-\(stamp).pdf")

        let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
        let h2: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
        let muted: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.secondaryLabel
        ]

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = margin

                func draw(_ s: String, _ attrs: [NSAttributedString.Key: Any], indent: CGFloat = 0, gap: CGFloat = 6) {
                    let str = NSAttributedString(string: s, attributes: attrs)
                    let h = str.boundingRect(with: CGSize(width: pageW - margin * 2 - indent, height: .greatestFiniteMagnitude),
                                             options: .usesLineFragmentOrigin, context: nil).height
                    str.draw(with: CGRect(x: margin + indent, y: y, width: pageW - margin * 2 - indent, height: h),
                             options: .usesLineFragmentOrigin, context: nil)
                    y += h + gap
                }

                draw("Doseify — Adherence Report", title)
                draw("Generated \(df.string(from: now))", muted, gap: 16)

                let windows: [(String, AdherenceCalculator.Stats)] = [
                    ("Last 7 days",  AdherenceCalculator.rolling7Day(for: doses, now: now)),
                    ("Last 30 days", AdherenceCalculator.rolling30Day(for: doses, now: now)),
                    ("Last 90 days", AdherenceCalculator.rolling90Day(for: doses, now: now)),
                    ("All time",     AdherenceCalculator.allTime(for: doses, now: now)),
                ]
                draw("Overall", h2)
                for (label, s) in windows {
                    draw("\(label): \(Int(s.adherencePercent))% adherence · "
                         + "\(s.totalTaken) taken, \(s.totalMissed) missed, \(s.totalSkipped) skipped · "
                         + "avg on-time \(Int(s.averageOnTimeScore))%", body, indent: 8)
                }
                let all = AdherenceCalculator.allTime(for: doses, now: now)
                draw("Current streak \(all.currentStreak) days · longest \(all.longestStreak) days", muted, gap: 16)

                draw("By medication (last 30 days)", h2)
                let active = medications.filter { $0.isActive }.sorted { $0.name < $1.name }
                if active.isEmpty {
                    draw("No active medications.", muted, indent: 8)
                }
                for med in active {
                    let medDoses = doses.filter { $0.medication?.id == med.id }
                    let s = AdherenceCalculator.rolling30Day(for: medDoses, now: now)
                    draw("\(med.name): \(Int(s.adherencePercent))% · \(s.totalTaken)/\(max(s.totalScheduled - s.totalSkipped, 0)) taken",
                         body, indent: 8)
                }

                y = pageH - margin - 14
                draw("Generated on this device. Not a medical record — confirm details with your care team.",
                     muted)
            }
            return url
        } catch {
            return nil
        }
    }
}
