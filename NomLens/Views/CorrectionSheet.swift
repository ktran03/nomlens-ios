import SwiftUI

/// Detail sheet for a decoded character.
///
/// Shows the top model predictions as tappable buttons — tap one to accept it
/// immediately. A text field below allows entering a fully custom correction.
struct CorrectionSheet: View {
    let cropImage: UIImage?
    let original: CharacterDecodeResult
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customInput: String = ""

    private let dict = NomDictionary.shared

    // Top prediction + up to 4 alternates, all in one list.
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
                                ForEach(Array(candidates.enumerated()), id: \.offset) { idx, char in
                                    candidateButton(char: char, isTop: idx == 0)
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

                            Button {
                                let trimmed = customInput.trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty else { return }
                                onSave(trimmed)
                                dismiss()
                            } label: {
                                Text("Use")
                                    .font(.body.weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
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
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func candidateButton(char: String, isTop: Bool) -> some View {
        let entry = dict.lookup(char)
        Button {
            onSave(char)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Text(char)
                    .font(.system(size: 40))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if let vn = entry?.vietnamese {
                    Text(vn)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if let meaning = entry?.definition {
                    Text(meaning)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .padding(8)
            .background(isTop ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isTop ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
