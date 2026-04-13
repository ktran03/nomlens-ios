import SwiftUI
import MapKit

/// Detail view for a single archived source, showing metadata and its scans.
struct SourceDetailView: View {
    let source: NLSource

    @State private var detail: NLSource?
    @State private var isLoadingScans = false

    private var display: NLSource { detail ?? source }

    var body: some View {
        List {
            infoSection
            mapSection
            scansSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(display.title ?? display.locationName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }

    // MARK: - Info section

    private var infoSection: some View {
        Section {
            LabeledContent("Type") {
                Label(display.sourceType.label, systemImage: display.sourceType.icon)
                    .foregroundStyle(NomTheme.lacquer500)
            }

            LabeledContent("Location", value: display.locationName)

            if let province = display.province {
                LabeledContent("Province", value: province)
            }

            LabeledContent("Country", value: display.country)

            if let condition = display.condition {
                LabeledContent("Condition") { conditionBadge(condition) }
            }

            if let period = display.estimatedPeriod {
                LabeledContent("Period", value: period)
            }

            HStack {
                Label("\(display.characterCount) characters", systemImage: "character")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if display.verified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            LabeledContent("Contributed") {
                Text(display.createdAt.formatted(.dateTime.month(.wide).day().year()))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Map section

    @ViewBuilder
    private var mapSection: some View {
        // Map is shown only when coordinates are present.
        // (Coordinates are stored as PostGIS geometry server-side;
        //  the REST API doesn't return them directly yet — placeholder for future.)
        EmptyView()
    }

    // MARK: - Scans section

    @ViewBuilder
    private var scansSection: some View {
        if isLoadingScans {
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        } else if let scans = display.scans, !scans.isEmpty {
            Section("Scans (\(scans.count))") {
                ForEach(scans) { scan in
                    ScanRow(scan: scan)
                }
            }
        }
    }

    // MARK: - Condition badge

    @ViewBuilder
    private func conditionBadge(_ condition: NLSource.SourceCondition) -> some View {
        let color: Color = switch condition {
        case .excellent:       .green
        case .good:            .green
        case .weathered:       .yellow
        case .damaged:         .orange
        case .severelyDamaged: .red
        }
        Text(condition.label)
            .font(.system(size: 11).weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Load detail

    private func loadDetail() async {
        guard display.scans == nil else { return }
        isLoadingScans = true
        if let loaded = try? await SupabaseClient.shared.sourceDetail(id: source.id) {
            detail = loaded
        }
        isLoadingScans = false
    }
}

// MARK: - Scan row

private struct ScanRow: View {
    let scan: NLScan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("\(scan.characterCount) characters", systemImage: "character")
                    .font(.body.weight(.medium))
                Spacer()
                Text(scan.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let t = scan.transliteration, !t.isEmpty {
                Text(t)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
