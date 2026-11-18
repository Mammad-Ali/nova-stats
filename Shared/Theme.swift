import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

// same palette as Nova
enum Nova {
    static let sun = Color(hex: 0xFFC61A)
    static let down = Color(hex: 0x818CF8)
    static let up = Color(hex: 0xE879F9)
    static let alt = Color(hex: 0x60A5FA)
    static let green = Color(hex: 0x4ADE80)
    static let amber = Color(hex: 0xFBBF24)
    static let red = Color(hex: 0xFB7185)

    static let textHi = Color(hex: 0xF5F6FA)
    static let textMid = Color(hex: 0xF5F6FA, alpha: 0.7)
    static let textLo = Color(hex: 0xF5F6FA, alpha: 0.4)

    static let heading = LinearGradient(
        colors: [Color(hex: 0x4F46E5), Color(hex: 0x9333EA), Color(hex: 0xDB2777)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func heat(_ t: Double?) -> Color {
        guard let t else { return textLo }
        return t < 60 ? green : t < 80 ? amber : red
    }
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.09)))
    }
}

extension View {
    func glass(_ radius: CGFloat = 22) -> some View {
        modifier(GlassCard(radius: radius))
    }
}
