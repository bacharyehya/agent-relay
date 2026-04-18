import SwiftUI

struct HandoffComposerView: View {
    let onCreate: (String, String, String, String) -> Void

    @State private var title = ""
    @State private var summary = ""
    @State private var ask = ""
    @State private var assignedTo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Handoff")
                .font(.headline)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Summary", text: $summary, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)

            TextField("Ask", text: $ask, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            TextField("Assigned To", text: $assignedTo)
                .textFieldStyle(.roundedBorder)

            Button("Create Handoff") {
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedAsk = ask.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedAssignedTo = assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTitle.isEmpty, !trimmedSummary.isEmpty, !trimmedAsk.isEmpty, !trimmedAssignedTo.isEmpty else {
                    return
                }

                onCreate(trimmedTitle, trimmedSummary, trimmedAsk, trimmedAssignedTo)
                title = ""
                summary = ""
                ask = ""
                assignedTo = ""
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}
