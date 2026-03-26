import SwiftUI
import SwiftData

/// Lists past `DecodingSession` records from SwiftData, most recent first.
struct HistoryView: View {
    @Query(sort: \DecodingSession.createdAt, order: .reverse)
    private var sessions: [DecodingSession]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Decoded sessions will appear here.")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        SessionRow(session: session)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !sessions.isEmpty {
                EditButton()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sessions[index])
        }
    }
}

// MARK: - SessionRow

private struct SessionRow: View {
    let session: DecodingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(session.characterCount) characters")
                    .font(.headline)
                Spacer()
                Text(session.createdAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !session.fullTransliteration.isEmpty {
                Text(session.fullTransliteration)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }

            if !session.fullMeaning.isEmpty {
                Text(session.fullMeaning)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
