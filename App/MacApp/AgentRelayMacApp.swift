import RelayCloudUI
import SwiftUI

@main
struct AgentRelayMacApp: App {
    var body: some Scene {
        WindowGroup {
            RelayCloudRootView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
    }
}
