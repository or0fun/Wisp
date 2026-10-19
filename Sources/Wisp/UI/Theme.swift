import SwiftUI

enum Palette {
    static let background = Color(red: 0.065, green: 0.075, blue: 0.10)
    static let surface = Color.white.opacity(0.045)
    static let accent = Color(red: 0.64, green: 0.58, blue: 1)
    static let secondary = Color.white.opacity(0.48)
    static func tint(_ name: String) -> Color {
        switch name { case "blue": return Color(red: 0.45, green: 0.7, blue: 1); case "green": return Color(red: 0.48, green: 0.84, blue: 0.67); case "orange": return Color(red: 1, green: 0.73, blue: 0.43); default: return accent }
    }
}
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 6).padding(.vertical, 4).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
    }
}
struct AppMark: View {
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: "command").font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.6, green: 0.45, blue: 1), Color(red: 0.32, green: 0.31, blue: 0.76)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.27))
    }
}
