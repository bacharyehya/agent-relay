import AppCore
import SwiftUI

struct HandoffCardView: View {
    let handoff: Handoff
    let onAccept: () -> Void
    let onBlock: () -> Void
    let onRespond: (String) -> Void
    let onResolve: () -> Void

    @State private var responseBody = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(handoff.title)
                    .font(.headline)
                Spacer()
                Text(handoff.status.rawValue.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(handoff.summary)
                .font(.subheadline)

            Text(handoff.ask)
                .font(.body)

            if let resolution = handoff.resolution, !resolution.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resolution")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(resolution)
                        .font(.body)
                }
            }

            switch handoff.status {
            case .open:
                HStack {
                    Button("Accept", action: onAccept)
                    Button("Block", action: onBlock)
                }
                respondComposer
            case .accepted:
                HStack {
                    Button("Block", action: onBlock)
                }
                respondComposer
            case .blocked:
                Button("Accept", action: onAccept)
            case .responded:
                Button("Resolve", action: onResolve)
            case .resolved, .canceled:
                EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var respondComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Reply with what changed", text: $responseBody, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            Button("Respond") {
                let body = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else {
                    return
                }
                onRespond(body)
                responseBody = ""
            }
        }
    }
}
