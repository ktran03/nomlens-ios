import SwiftUI
import SwiftData

struct HomeView: View {
    let onScan: () -> Void

    @Query(sort: \DecodingSession.createdAt, order: .reverse)
    private var sessions: [DecodingSession]
    @Environment(\.modelContext) private var modelContext

    @State private var showAbout = false
    @State private var showSettings = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                scanButtonSection
                missionQuoteSection
                if sessions.isEmpty {
                    emptyState
                } else {
                    historySection
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Dark background
            NomTheme.stone950
                .ignoresSafeArea(edges: .top)

            // Decorative large character
            Text("漢")
                .font(.system(size: 260, weight: .black, design: .serif))
                .foregroundStyle(Color.white.opacity(0.03))
                .offset(x: 70, y: 20)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80) // top safe area breathing room

                // Eyebrow
                Text("Han Nôm Decoder · iOS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(NomTheme.lacquer400)
                    .padding(.bottom, 12)

                // Main headline
                VStack(alignment: .leading, spacing: 4) {
                    Text("Read what")
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text("time is erasing.")
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(NomTheme.lacquer400)
                }
                .padding(.bottom, 20)

                // Descriptor
                Text("NomLens decodes Han Nôm script from photos of stone steles, temple inscriptions, and ancient manuscripts — on your iPhone, offline.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineSpacing(4)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 340)
    }

    // MARK: - Scan button

    private var scanButtonSection: some View {
        VStack(spacing: 0) {
            // Gradient bridge from dark to light
            LinearGradient(
                colors: [NomTheme.stone900, Color(.systemBackground)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 32)

            Button(action: onScan) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                    Text("New Scan")
                }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(NomTheme.lacquer500)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: NomTheme.lacquer500.opacity(0.4), radius: 12, y: 4)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Mission pull quote

    private var missionQuoteSection: some View {
        VStack(spacing: 0) {
            Divider()
            ZStack {
                NomTheme.parchment50
                    .ignoresSafeArea()

                // Decorative background character
                Text("喃")
                    .font(.system(size: 160, weight: .black, design: .serif))
                    .foregroundStyle(NomTheme.lacquer500.opacity(0.04))
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    Text("\"Once a script dies,")
                    + Text("\nthe history it carried")
                    + Text("\ndies with it.\"")
                }
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(NomTheme.stone700)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.vertical, 32)
            }
            Divider()
        }
    }

    // MARK: - History section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scans")
                    .font(.title3.bold())
                    .foregroundStyle(NomTheme.stone800)
                Spacer()
                Text("\(sessions.count) scan\(sessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 24)

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
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 32)

            ZStack {
                Circle()
                    .fill(NomTheme.lacquer500.opacity(0.08))
                    .frame(width: 120, height: 120)
                VStack(spacing: 4) {
                    Text("𡨸")
                        .font(.system(size: 48))
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 18))
                        .foregroundStyle(NomTheme.lacquer500)
                }
            }

            VStack(spacing: 8) {
                Text("No scans yet")
                    .font(.title2.bold())
                    .foregroundStyle(NomTheme.stone800)
                Text("Point your camera at any Han Nôm text\nto decode historical Vietnamese script.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 40)
        }
        .padding(.horizontal, 40)
        .background(Color(.systemBackground))
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
                        .foregroundStyle(NomTheme.stone700)
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(NomTheme.stone200, lineWidth: 0.5)
        )
    }
}
