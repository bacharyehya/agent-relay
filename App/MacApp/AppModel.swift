import Observation
import SwiftUI

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
    var serviceState: ServiceState = .checking
    var selection: SidebarSelection? = .inbox

    init(client: any AppAPIClientProtocol) {
        self.client = client
    }

    func refresh() async {
        do {
            let health = try await client.fetchHealth()
            serviceState = health.status == "ok" ? .healthy : .degraded
        } catch {
            serviceState = .degraded
        }
    }
}

enum SidebarSelection: String, CaseIterable, Identifiable {
    case inbox
    case recents
    case search
    case projects
    case agents
    case settings

    var id: String { rawValue }
}
