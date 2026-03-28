import SwiftUI

/// Detail sheet for a decoded character.
///
/// Tap a prediction to select it (highlighted blue). Tap "Back" to confirm
/// the selection and return — the card on the previous screen updates automatically.
/// The custom text field is for entering a character not in the prediction list.
struct CorrectionSheet: View {
    let cropImage: UIImage?
    let original: CharacterDecodeResult
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: String
    @State private var customInput: String = ""

    private let dict = NomDictionary.shared

    init(cropImage: UIImage?, original: CharacterDecodeResult, onSave: @escaping (String) -> Void) {
        self.cropImage = cropImage
        self.original  = original
        self.onSave    = onSave
        self._selected = State(initialValue: original.character ?? "")
    }

    private var candidates: [String] {
        var all: [String] = []
        if let c = original.character { all.append(c) }
        all.append(contentsOf: original.alternateReadings)
        return all
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // ── Crop image ────────────────────────────────────────────
                    if let crop = cropImage {
                        Image(uiImage: crop)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // ── Top predictions ───────────────────────────────────────
                    if !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top predictions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 90), spacing: 10)],
                                spacing: 10
                            ) {
                                ForEach(Array(candidates.enumerated()), id: \.offset) { _, char in
                                    candidateButton(char: char)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // ── Custom input ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter a different character")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        HStack {
                            TextField("Han Nôm character", text: $customInput)
                                .font(.system(size: 36))
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onChange(of: customInput) { _, val in
                                    if !val.isEmpty { selected = val }
                                }

                            Button("Use") {
                                let trimmed = customInput.trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty else { return }
                                selected = trimmed
                            }
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .disabled(customInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("Choose Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        let original = original.character ?? ""
                        if !selected.isEmpty, selected != original {
                            onSave(selected)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func candidateButton(char: String) -> some View {
        let isSelected = selected == char
        let entry = dict.lookup(char)

        Button {
            selected = char
            customInput = ""
        } label: {
            VStack(spacing: 4) {
                Text(char)
                    .font(.system(size: 40))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if let vn = entry?.vietnamese {
                    Text(vn)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                }

                if let meaning = entry?.definition {
                    Text(meaning)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(8)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
