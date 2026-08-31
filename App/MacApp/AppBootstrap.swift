import AppCore
import Foundation
import RelayCloudUI
import SwiftUI

public struct AgentRelayRootView: View {
    @State private var model: AppModel
    @AppStorage("AgentRelay.AppMode") private var appMode = "cloud"

    @MainActor
    public init() {
        _model = State(initialValue: AppBootstrap.makeAppModel())
    }

    public var body: some View {
        Group {
            if appMode == "cloud" {
                RelayCloudRootView(allowsLocalAgentHosting: true)
            } else {
                localWorkspace
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Relay mode", selection: $appMode) {
                    Text("Cloud").tag("cloud")
                    Text("This Mac").tag("local")
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .help("Cloud syncs every enrolled device. This Mac keeps the original local board available as a fallback.")
            }
        }
    }

    private var localWorkspace: some View {
        @Bindable var bindableModel = model

        return NavigationSplitView {
            SidebarView(
                selection: $bindableModel.selection,
                serviceState: model.serviceState,
                mentionCount: model.mentions.count
            )
            .navigationSplitViewColumnWidth(min: 184, ideal: 210, max: 238)
        } detail: {
            switch model.selection ?? .room {
            case .room:
                ThreadDetailView(
                    client: model.client,
                    threadID: "thread-general",
                    seedContext: nil,
                    serviceState: model.serviceState,
                    agentStatuses: model.agentStatuses
                )
            case .mentions:
                MentionsView(messages: model.mentions) {
                    model.selection = .room
                }
            case .recents:
                RecentsView(client: model.client)
            case .search:
                SearchView(client: model.client)
            case .agents:
                AgentListView(statuses: model.agentStatuses)
            case .settings:
                RelaySettingsView(state: model.serviceState)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(RelayPalette.canvas)
        .preferredColorScheme(.dark)
        .tint(RelayPalette.ink)
        .task {
            while !Task.isCancelled {
                await model.refresh()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
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
