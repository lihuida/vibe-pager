import SwiftUI

enum Palette {
    static let accent = Color(red: 62 / 255, green: 62 / 255, blue: 1)
    static let canvas = Color(red: 246 / 255, green: 247 / 255, blue: 252 / 255)
    static let card = Color.white
    static let ink = Color(red: 28 / 255, green: 28 / 255, blue: 46 / 255)
    static let muted = Color(red: 110 / 255, green: 112 / 255, blue: 138 / 255)
    static let line = Color(red: 226 / 255, green: 228 / 255, blue: 240 / 255)
    static let banner = Color(red: 255 / 255, green: 244 / 255, blue: 230 / 255)
    static let ok = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
}

struct AccentButtonStyle: ButtonStyle {
    var disabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Palette.accent.opacity(disabled ? 0.4 : (configuration.isPressed ? 0.82 : 1))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.canvas.opacity(configuration.isPressed ? 0.7 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Palette.line, lineWidth: 1)
            )
    }
}
