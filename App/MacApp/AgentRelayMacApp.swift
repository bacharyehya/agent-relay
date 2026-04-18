import SwiftUI

@main
struct AgentRelayMacApp: App {
    @State private var model = AppBootstrap.makeAppModel()

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
                    ProjectsWorkspaceView(client: model.client)
                case .agents:
                    AgentListView()
                case .settings:
                    VStack(alignment: .leading, spacing: 16) {
                        ServiceStatusView(state: model.serviceState)
                        Text("The macOS shell now talks to the real local core service. During development, start `swift run CoreService` until the bundled helper is implemented.")
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
}
