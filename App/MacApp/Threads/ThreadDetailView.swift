import SwiftUI

struct ThreadDetailView: View {
    let context: AppThreadContext?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(context?.thread.title ?? "Select a thread")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let context {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(context.messages) { message in
                            MessageRowView(message: message)
                        }
                    }

                    if !context.handoffs.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Handoffs")
                                .font(.headline)
                            ForEach(context.handoffs) { handoff in
                                Text("[\(handoff.status.rawValue)] \(handoff.title)")
                                    .font(.subheadline)
                            }
                        }
                    }
                } else {
                    Text("Select a thread to see recent messages and handoffs.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}
