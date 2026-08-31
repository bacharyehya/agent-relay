import AppKit
import AppCore
import SwiftUI

enum RelayPalette {
    static let canvas = Color(red: 0.025, green: 0.025, blue: 0.028)
    static let sidebar = Color(red: 0.045, green: 0.045, blue: 0.052)
    static let surface = Color.white.opacity(0.055)
    static let surfaceRaised = Color.white.opacity(0.085)
    static let hairline = Color.white.opacity(0.12)
    static let muted = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let ink = Color.white
    static let humanBubble = Color.white
    static let humanInk = Color.black
    static let healthy = Color(red: 0.62, green: 0.98, blue: 0.70)
    static let warning = Color(red: 1.00, green: 0.78, blue: 0.38)
    static let danger = Color(red: 1.00, green: 0.42, blue: 0.42)
}

struct RelayAppMark: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct RelayAgentAvatar: View {
    let actorID: String
    var size: CGFloat = 34
    var inverted = false

    private var profile: RelayAgentProfile {
        RelayAgentProfile.profile(for: actorID)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .fill(inverted ? Color.black : Color.white)

            Image(systemName: profile.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(inverted ? Color.white : Color.black)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .stroke(Color.white.opacity(inverted ? 0.16 : 0.35), lineWidth: 1)
        }
    }
}

extension AgentRuntimeStatus.Phase {
    var relayLabel: String {
        switch self {
        case .starting: "Starting"
        case .ready: "Ready"
        case .working: "Thinking"
        case .retrying: "Recovering"
        case .unavailable: "Offline"
        }
    }

    var relayColor: Color {
        switch self {
        case .ready: RelayPalette.healthy
        case .working, .starting: RelayPalette.ink
        case .retrying: RelayPalette.warning
        case .unavailable: RelayPalette.danger
        }
    }
}
