import SwiftUI
import SwiftData

struct HomeView: View {
    let onScan: () -> Void

    @Query(sort: \DecodingSession.createdAt, order: .reverse)
    private var sessions: [DecodingSession]
    @Environment(\.modelContext) private var modelContext

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                scanButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, 36)

                if sessions.isEmpty {
                    emptyState
                } else {
                    historySection
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            // Watermark
            Text("字")
                .font(.system(size: 200, weight: .black))
                .foregroundStyle(Color.accentColor.opacity(0.05))
                .offset(y: -10)

            VStack(spacing: 6) {
                Text("NomLens")
                    .font(.system(size: 42, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                Text("Han Nôm Character Decoder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 48)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Scan button

    private var scanButton: some View {
        Button(action: onScan) {
            HStack(spacing: 10) {
                Image(systemName: "camera.fill")
                Text("New Scan")
            }
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
        }
    }

    // MARK: - History section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scans")
                    .font(.title3.bold())
                Spacer()
                Text("\(sessions.count) scan\(sessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(sessions) { session in
                    NavigationLink {
                        ResultView(session: session)
                    } label: {
                        SessionCard(session: session)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            modelContext.delete(session)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 120, height: 120)
                VStack(spacing: 4) {
                    Text("𡨸")
                        .font(.system(size: 48))
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                }
            }

            VStack(spacing: 8) {
                Text("No scans yet")
                    .font(.title2.bold())
                Text("Point your camera at any Han Nôm text\nto decode historical Vietnamese script.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Session card

private struct SessionCard: View {
    let session: DecodingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            Group {
                if let data = session.sourceImageData,
                   let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.tertiarySystemBackground)
                        .overlay {
                            Image(systemName: "doc.text")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(height: 110)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 12
                )
            )
            .clipped()

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(session.characterCount) chars")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(session.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !session.fullTransliteration.isEmpty {
                    Text(session.fullTransliteration)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(8)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
