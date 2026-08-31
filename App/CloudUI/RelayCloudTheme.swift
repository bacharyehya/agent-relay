import SwiftUI

enum CloudRelayTheme {
    static let canvas = Color(red: 0.035, green: 0.038, blue: 0.043)
    static let sidebar = Color(red: 0.055, green: 0.059, blue: 0.066)
    static let surface = Color(red: 0.075, green: 0.080, blue: 0.090)
    static let raised = Color(red: 0.105, green: 0.112, blue: 0.125)
    static let line = Color.white.opacity(0.09)
    static let ink = Color.white.opacity(0.94)
    static let muted = Color.white.opacity(0.57)
    static let faint = Color.white.opacity(0.34)
    static let humanBubble = Color.white.opacity(0.94)
    static let humanInk = Color.black.opacity(0.88)
    static let healthy = Color(red: 0.35, green: 0.82, blue: 0.54)
    static let warning = Color(red: 0.95, green: 0.68, blue: 0.27)
}

struct CloudRelayMark: View {
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color.black)
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }
}
