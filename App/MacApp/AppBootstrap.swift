import AppCore
import Foundation
import SwiftUI

public struct AgentRelayRootView: View {
    @State private var model: AppModel

    @MainActor
    public init() {
        _model = State(initialValue: AppBootstrap.makeAppModel())
    }

    public var body: some View {
        @Bindable var bindableModel = model

        NavigationSplitView {
            SidebarView(selection: $bindableModel.selection)
        } detail: {
            switch model.selection ?? .projects {
            case .inbox:
                InboxView(client: model.client)
            case .recents:
                RecentsView(client: model.client)
            case .search:
                SearchView(client: model.client)
            case .projects:
                ProjectsWorkspaceView(client: model.client)
            case .agents:
                AgentListView()
            case .settings:
                VStack(alignment: .leading, spacing: 16) {
                    ServiceStatusView(state: model.serviceState)
                    Text("Agent Relay keeps the board and its ChatGPT-backed agents on this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task {
            await model.refresh()
        }
    }
}

enum AppBootstrap {
    @MainActor
    static func makeAppModel() -> AppModel {
        do {
            return AppModel(client: try AppAPIClient.live())
        } catch {
            return AppModel(client: BootstrapFailureAppAPIClient(underlyingError: error))
        }
    }
}

private struct BootstrapFailureAppAPIClient: AppAPIClientProtocol {
    let underlyingError: Error

    func fetchHealth() async throws -> AppHealth {
        throw underlyingError
    }

    func fetchInbox(actorID: String) async throws -> [Handoff] {
        throw underlyingError
    }

    func fetchRecents() async throws -> [AppRecentItem] {
        throw underlyingError
    }

    func search(query: String) async throws -> [AppSearchResult] {
        throw underlyingError
    }

    func fetchProjects() async throws -> [Project] {
        throw underlyingError
    }

    func fetchProjectThreads(projectID: String) async throws -> [AppCore.Thread] {
        throw underlyingError
    }

    func fetchThreadContext(threadID: String, mode: String) async throws -> AppThreadContext {
        throw underlyingError
    }

    func fetchThreadMessages(threadID: String, limit: Int, before: MessageCursor?) async throws -> [Message] {
        throw underlyingError
    }

    func postMessage(threadID: String, request: AppPostMessageRequest) async throws -> Message {
        throw underlyingError
    }

    func createHandoff(_ request: AppCreateHandoffRequest) async throws -> Handoff {
        throw underlyingError
    }

    func updateHandoff(id: String, status: HandoffStatus, resolution: String?) async throws -> Handoff {
        throw underlyingError
    }
}
