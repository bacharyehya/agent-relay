import AppCore
import SwiftUI

struct MessageRowView: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.actorID)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message.body)
                .font(.body)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
