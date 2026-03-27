import SwiftUI
import UIKit

/// Sheet that lets the user submit a corrected label for a decoded character.
///
/// The corrected value is returned via `onSave` — the caller decides where to
/// persist it. This keeps the view free of SwiftData and straightforward to test.
struct CorrectionSheet: View {
    let cropImage: UIImage?
    let original: CharacterDecodeResult
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // Original crop + decoded character for reference
                HStack(spacing: 20) {
                    if let crop = cropImage {
                        Image(uiImage: crop)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decoded as")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        if let char = original.character {
                            Text(char)
                                .font(.system(size: 52))
                        } else {
                            Text("Unknown")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)

                // Correction input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Correct character")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal)

                    TextField("Han Nôm character", text: $input)
                        .font(.system(size: 40))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Correct Character")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = input.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
