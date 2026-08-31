import Observation
import SwiftUI
import AppCore

@MainActor
@Observable
final class AppModel {
    enum ServiceState: String, Equatable {
        case checking
        case healthy
        case degraded

        var title: String {
            switch self {
            case .checking:
                return "Checking service"
            case .healthy:
                return "Service healthy"
            case .degraded:
                return "Service degraded"
            }
        }

        var symbolName: String {
            switch self {
            case .checking:
                return "clock"
            case .healthy:
                return "checkmark.circle.fill"
            case .degraded:
                return "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .checking:
                return .orange
            case .healthy:
                return .green
            case .degraded:
                return .red
            }
        }
    }

    let client: any AppAPIClientProtocol
    private let runtimeStatusReader: AgentRuntimeStatusReader
    var serviceState: ServiceState = .checking
    var agentStatuses: [AgentRuntimeStatus] = []
    var mentions: [Message] = []
    var selection: SidebarSelection? = .room

    init(
        client: any AppAPIClientProtocol,
        runtimeStatusReader: AgentRuntimeStatusReader = AgentRuntimeStatusReader()
    ) {
        self.client = client
        self.runtimeStatusReader = runtimeStatusReader
    }

    func refresh() async {
        agentStatuses = runtimeStatusReader.load()
        if let refreshedMentions = try? await client.fetchMentions(actorID: "bash", limit: 100) {
            mentions = refreshedMentions
        }
        do {
            let health = try await client.fetchHealth()
            serviceState = health.status == "ok" ? .healthy : .degraded
        } catch {
            serviceState = .degraded
        }
    }
}

enum SidebarSelection: String, CaseIterable, Identifiable {
    case room
    case mentions
    case recents
    case search
    case agents
    case settings

    var id: String { rawValue }
}
