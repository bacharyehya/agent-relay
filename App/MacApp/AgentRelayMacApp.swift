import SwiftUI

@main
struct AgentRelayMacApp: App {
    @State private var model = PreviewData.makeAppModel()

    var body: some Scene {
        WindowGroup {
            @Bindable var bindableModel = model

            NavigationSplitView {
                SidebarView(selection: $bindableModel.selection)
            } detail: {
                switch model.selection ?? .inbox {
                case .inbox:
                    InboxView(client: model.client)
                case .recents:
                    RecentsView(client: model.client)
                case .search:
                    SearchView(client: model.client)
                case .projects:
                    ProjectDetailView(client: model.client, projectID: "project-api")
                case .agents:
                    AgentListView()
                case .settings:
                    VStack(alignment: .leading, spacing: 16) {
                        ServiceStatusView(state: model.serviceState)
                        Text(detailText(for: model.selection))
                            .font(.title3)
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

    private func detailText(for selection: SidebarSelection?) -> String {
        switch selection ?? .inbox {
        case .inbox:
            return "Inbox handoffs will appear here."
        case .recents:
            return "Recent collaboration activity will appear here."
        case .search:
            return "Search across handoffs and messages."
        case .projects:
            return "Project workspaces will appear here."
        case .agents:
            return "Connected agents will appear here."
        case .settings:
            return "Service and notification settings will appear here."
        }
    }
}
