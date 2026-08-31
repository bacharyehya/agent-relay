import Foundation

public struct RelayAgentProfile: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let role: String
    public let summary: String
    public let machine: String
    public let symbolName: String

    public init(
        id: String,
        displayName: String,
        role: String,
        summary: String,
        machine: String,
        symbolName: String
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.summary = summary
        self.machine = machine
        self.symbolName = symbolName
    }

    public static let main = RelayAgentProfile(
        id: "codex-main",
        displayName: "Main",
        role: "Coordinator",
        summary: "Synthesizes the room, keeps the conversation moving, and turns discussion into a clear next action.",
        machine: "M1 · local",
        symbolName: "scope"
    )

    public static let research = RelayAgentProfile(
        id: "codex-research",
        displayName: "Research",
        role: "Skeptical analyst",
        summary: "Pressure-tests claims, compares alternatives, and makes uncertainty visible before the group commits.",
        machine: "M1 · local",
        symbolName: "sparkle.magnifyingglass"
    )

    public static let m5 = RelayAgentProfile(
        id: "codex-m5",
        displayName: "M5",
        role: "Remote builder",
        summary: "Owns independent implementation work on the M5 and reports verified results back into the room.",
        machine: "M5 · Tailscale",
        symbolName: "hammer"
    )

    public static let known: [RelayAgentProfile] = [.main, .research, .m5]

    public static func profile(for actorID: String) -> RelayAgentProfile {
        known.first(where: { $0.id == actorID }) ?? RelayAgentProfile(
            id: actorID,
            displayName: actorID
                .replacingOccurrences(of: "codex-", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized,
            role: "Guest agent",
            summary: "A participant connected to this Agent Relay room.",
            machine: "Remote",
            symbolName: "sparkles"
        )
    }
}
