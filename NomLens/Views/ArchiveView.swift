import SwiftUI

/// Browses the public archive of contributed Han Nôm inscriptions.
struct ArchiveView: View {
    @State private var sources: [NLSource] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && sources.isEmpty {
                    ProgressView("Loading archive…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError, sources.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load archive", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(err)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(NomTheme.lacquer500)
                    }
                } else if sources.isEmpty {
                    ContentUnavailableView {
                        Label("Archive is empty", systemImage: "building.columns")
                    } description: {
                        Text("No inscriptions contributed yet.\nScan one and tap Contribute!")
                    }
                } else {
                    sourceList
                }
            }
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await load() }
    }

    // MARK: - List

    private var sourceList: some View {
        List {
            ForEach(sources) { source in
                NavigationLink {
                    SourceDetailView(source: source)
                } label: {
                    SourceRow(source: source)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            sources = try await SupabaseClient.shared.browseSources()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Source row

private struct SourceRow: View {
    let source: NLSource

    var body: some View {
        HStack(spacing: 14) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(NomTheme.lacquer500.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: source.sourceType.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(NomTheme.lacquer500)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(source.title ?? source.locationName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(source.sourceType.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let condition = source.condition {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        conditionBadge(condition)
                    }
                }

                HStack(spacing: 8) {
                    Label("\(source.characterCount)", systemImage: "character")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(source.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func conditionBadge(_ condition: NLSource.SourceCondition) -> some View {
        let color: Color = switch condition {
        case .excellent:      .green
        case .good:           .green
        case .weathered:      .yellow
        case .damaged:        .orange
        case .severelyDamaged: .red
        }
        Text(condition.label)
            .font(.system(size: 9).weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
