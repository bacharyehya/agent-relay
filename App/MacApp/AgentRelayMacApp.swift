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
            .task {
                await model.refresh()
            }
        }
    }

    private func detailText(for selection: SidebarSelection?) -> String {
        switch selection ?? .inbox {
        case .inbox:
            return "Select Inbox, Recents, or a Project"
        case .recents:
            return "Recent collaboration activity will appear here."
        case .projects:
            return "Project workspaces will appear here."
        case .agents:
            return "Connected agents will appear here."
        case .settings:
            return "Service and notification settings will appear here."
        }
    }
}
