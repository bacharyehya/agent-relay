import SwiftUI

struct ServiceStatusView: View {
    let state: AppModel.ServiceState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.headline)
                Text(state.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(state.tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(state.tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private extension AppModel.ServiceState {
    var subtitle: String {
        switch self {
        case .checking:
            return "Attempting to reach the local core service."
        case .healthy:
            return "The background service is responding."
        case .degraded:
            return "The app could not reach the background service."
        }
    }
}
