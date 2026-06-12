import SwiftUI

extension Color {
    // SPEC §5: sage, peach, slate palette
    static let doseSage  = Color(red: 0.48, green: 0.62, blue: 0.53)
    static let dosePeach = Color(red: 0.95, green: 0.76, blue: 0.65)
    static let doseSlate = Color(red: 0.44, green: 0.50, blue: 0.56)
    static let doseBackground = Color(UIColor.systemGroupedBackground)

    static func fromHex(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 6 { h = "FF" + h }
        var value: UInt64 = 0
        Scanner(string: h).scanHexInt64(&value)
        return Color(
            red:   Double((value & 0xff0000) >> 16) / 255,
            green: Double((value & 0x00ff00) >>  8) / 255,
            blue:  Double( value & 0x0000ff       ) / 255
        )
    }
}
