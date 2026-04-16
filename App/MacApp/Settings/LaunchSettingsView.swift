import SwiftUI

struct LaunchSettingsView: View {
    let controller: ServiceController

    var body: some View {
        Toggle(
            "Launch at login",
            isOn: Binding(
                get: { controller.launchAtLoginEnabled },
                set: { enabled in
                    Task {
                        try? await controller.setLaunchAtLoginEnabled(enabled)
                    }
                }
            )
        )
        .toggleStyle(.switch)
    }
}
