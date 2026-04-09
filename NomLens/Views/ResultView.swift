import SwiftUI
import SwiftData
import UIKit

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
    @State private var correctionTarget: CorrectionTarget?
    /// Maps result index → user-submitted corrected character.
    @State private var corrections: [Int: String] = [:]
    @State private var transliterationExpanded = false
    @State private var scriptFilter: ScriptFilter = .all

    enum ScriptFilter: String, CaseIterable {
        case all = "All"
        case han = "Han"
        case nom = "Nom"
    }

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transliteration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(fullTransliteration)
                            .font(.title3)
                            .lineLimit(transliterationExpanded ? nil : 2)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                transliterationExpanded.toggle()
                            }
                        } label: {
                            Text(transliterationExpanded ? "Show less" : "Show more")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(NomTheme.lacquer500)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                // Script filter
                Picker("Filter", selection: $scriptFilter) {
                    ForEach(ScriptFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Character grid
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(filteredResults), id: \.offset) { index, result in
                        CharacterCard(
                            result: result,
                            cropImage: index < cropImages.count ? cropImages[index] : nil,
                            correctedCharacter: corrections[index]
                        ) {
                            correctionTarget = CorrectionTarget(
                                index: index,
                                result: result,
                                cropImage: index < cropImages.count ? cropImages[index] : nil
                            )
                        }
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
                        .background(saved ? NomTheme.stone700 : NomTheme.lacquer500)
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
        .sheet(item: $correctionTarget) { target in
            CorrectionSheet(
                cropImage: target.cropImage,
                original: target.result
            ) { corrected in
                corrections[target.index] = corrected
                saveCorrection(target: target, corrected: corrected)
            }
        }
    }

    // MARK: - Correction target

    struct CorrectionTarget: Identifiable {
        let id = UUID()
        let index: Int
        let result: CharacterDecodeResult
        let cropImage: UIImage?
    }

    // MARK: - Helpers

    private var filteredResults: [(offset: Int, element: CharacterDecodeResult)] {
        results.enumerated().filter { _, result in
            switch scriptFilter {
            case .all: return true
            case .han: return result.type == .han
            case .nom: return result.type == .nom
            }
        }.map { (offset: $0.offset, element: $0.element) }
    }

    private var fullTransliteration: String {
        results.compactMap { $0.quocNgu }.joined(separator: " ")
    }

    private var fullMeaning: String {
        results.compactMap { $0.meaning }.joined(separator: "; ")
    }

    private func saveCorrection(target: CorrectionTarget, corrected: String) {
        let cropData = target.cropImage.flatMap { ImageUtilities.jpegData(from: $0) }
        let correction = CharacterCorrection(
            cropImageData: cropData,
            originalCharacter: target.result.character,
            correctedCharacter: corrected,
            originalConfidence: target.result.confidence.rawValue
        )
        modelContext.insert(correction)
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
    let correctedCharacter: String?
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Side-by-side: original crop image + decoded (or corrected) character
            HStack(spacing: 8) {
                if let crop = cropImage {
                    Image(uiImage: crop)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                let displayChar = correctedCharacter ?? result.character
                if let char = displayChar {
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

            // Pinyin stored in notes as "pinyin: rén"
            if let pinyin = result.notes?.hasPrefix("pinyin: ") == true
                ? String(result.notes!.dropFirst("pinyin: ".count)) : nil {
                Text(pinyin)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let meaning = result.meaning {
                Text(meaning)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 4) {
                scriptTypeBadge
                if correctedCharacter != nil {
                    Label("Corrected", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(NomTheme.lacquer500)
                } else {
                    confidenceBadge
                }
            }

            trainingBadge
        }
        .padding(10)
        .frame(minHeight: 140)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private var scriptTypeBadge: some View {
        switch result.type {
        case .han:
            Text("Han")
                .font(.system(size: 9).weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.12))
                .foregroundStyle(Color.blue)
                .clipShape(Capsule())
        case .nom:
            Text("Nom")
                .font(.system(size: 9).weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(NomTheme.lacquer500.opacity(0.12))
                .foregroundStyle(NomTheme.lacquer500)
                .clipShape(Capsule())
        case .unclear, .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trainingBadge: some View {
        let inSet = TrainingSet.contains(result.character)
        Text(inSet ? "v1 ✓" : "not in v1")
            .font(.system(size: 9).weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(inSet ? Color.blue.opacity(0.12) : Color.gray.opacity(0.10))
            .foregroundStyle(inSet ? Color.blue : Color.secondary)
            .clipShape(Capsule())
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
