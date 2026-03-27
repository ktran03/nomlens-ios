import SwiftUI
import SwiftData

/// Displays the decoded Han Nôm characters as a grid of cards,
/// with a "Save" button to persist the session to SwiftData history.
struct ResultView: View {
    let sourceImage: UIImage
    let results: [CharacterDecodeResult]
    /// Original crop images in the same order as `results`.
    let cropImages: [UIImage]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var saved: Bool

    init(sourceImage: UIImage, results: [CharacterDecodeResult], cropImages: [UIImage]) {
        self.sourceImage = sourceImage
        self.results = results
        self.cropImages = cropImages
        self._saved = State(initialValue: false)
    }

    /// Reconstruct a `ResultView` from a persisted `DecodingSession` (already saved).
    init(session: DecodingSession) {
        self.sourceImage = session.sourceImageData.flatMap { UIImage(data: $0) } ?? UIImage()
        self.results = {
            guard let data = session.characterResultsJSON,
                  let decoded = try? JSONDecoder().decode([CharacterDecodeResult].self, from: data)
            else { return [] }
            return decoded
        }()
        self.cropImages = []
        self._saved = State(initialValue: true)
    }

    // MARK: - Layout

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Transliteration header
                if !fullTransliteration.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transliteration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(fullTransliteration)
                            .font(.title3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                // Character grid
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                        CharacterCard(
                            result: result,
                            cropImage: index < cropImages.count ? cropImages[index] : nil
                        )
                    }
                }
                .padding(.horizontal)

                // Save button
                Button(action: save) {
                    Label(saved ? "Saved" : "Save to History",
                          systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(saved ? Color.green : Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(saved)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top)
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private var fullTransliteration: String {
        results.compactMap { $0.quocNgu }.joined(separator: " ")
    }

    private var fullMeaning: String {
        results.compactMap { $0.meaning }.joined(separator: "; ")
    }

    private func save() {
        let jpeg = ImageUtilities.jpegData(from: sourceImage)
        let json = try? JSONEncoder().encode(results)

        let session = DecodingSession(
            sourceImageData: jpeg,
            fullTransliteration: fullTransliteration,
            fullMeaning: fullMeaning,
            characterCount: results.count,
            characterResultsJSON: json
        )
        modelContext.insert(session)
        saved = true
    }
}

// MARK: - CharacterCard

private struct CharacterCard: View {
    let result: CharacterDecodeResult
    let cropImage: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            // Side-by-side: original crop image + decoded character
            HStack(spacing: 8) {
                if let crop = cropImage {
                    Image(uiImage: crop)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if let char = result.character {
                    Text(char)
                        .font(.system(size: 42))
                        .minimumScaleFactor(0.5)
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                }
            }

            if let qn = result.quocNgu {
                Text(qn)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }

            if let meaning = result.meaning {
                Text(meaning)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            confidenceBadge
        }
        .padding(10)
        .frame(minHeight: 140)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var confidenceBadge: some View {
        let (label, color): (String, Color) = switch result.confidence {
        case .high:   ("High",   .green)
        case .medium: ("Medium", .orange)
        case .low:    ("Low",    .red)
        case .none:   ("—",      .secondary)
        }
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
