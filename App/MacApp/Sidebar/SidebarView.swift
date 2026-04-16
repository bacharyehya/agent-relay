import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection?

    var body: some View {
        List(SidebarSelection.allCases, selection: $selection) { item in
            Label(item.title, systemImage: item.symbolName)
                .tag(item)
        }
        .navigationTitle("AgentRelay")
        .listStyle(.sidebar)
    }
}

private extension SidebarSelection {
    var title: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .recents:
            return "Recents"
        case .projects:
            return "Projects"
        case .agents:
            return "Agents"
        case .settings:
            return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .inbox:
            return "tray.full"
        case .recents:
            return "clock.arrow.circlepath"
        case .projects:
            return "square.grid.2x2"
        case .agents:
            return "person.2"
        case .settings:
            return "slider.horizontal.3"
        }
    }
}
