import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var keyInput: String = ""
    @State private var showKey = false
    @State private var isSaved = false
    @State private var isSet = APIKeyStore.isSet

    var body: some View {
        NavigationStack {
            List {
                claudeKeySection
                aboutKeySection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Claude key section

    private var claudeKeySection: some View {
        Section {
            // Status row
            HStack {
                Label(isSet ? "API Key Set" : "No API Key", systemImage: isSet ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(isSet ? NomTheme.lacquer500 : .secondary)
                Spacer()
                if isSet {
                    Button("Clear", role: .destructive) {
                        APIKeyStore.delete()
                        isSet = false
                        keyInput = ""
                        isSaved = false
                    }
                    .font(.subheadline)
                }
            }

            // Key input
            HStack(spacing: 10) {
                Group {
                    if showKey {
                        TextField("sk-ant-api03-…", text: $keyInput)
                    } else {
                        SecureField("sk-ant-api03-…", text: $keyInput)
                    }
                }
                .font(.system(.footnote, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: keyInput) { _, _ in isSaved = false }

                Button {
                    showKey.toggle()
                } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Save button
            Button {
                let trimmed = keyInput.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                APIKeyStore.save(trimmed)
                isSet = true
                isSaved = true
                showKey = false
            } label: {
                HStack {
                    Spacer()
                    if isSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                    } else {
                        Text("Save Key")
                    }
                    Spacer()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(isSaved ? NomTheme.lacquer500 : .white)
            }
            .listRowBackground(isSaved ? NomTheme.lacquer500.opacity(0.1) : NomTheme.lacquer500)
            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || isSaved)

        } header: {
            Text("Claude API Key")
        } footer: {
            Text("Used for cloud fallback on low-confidence characters. The app works fully offline without a key — on-device classification only.")
        }
    }

    // MARK: - About key section

    private var aboutKeySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("What is the Claude API key for?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NomTheme.stone800)

                Text("NomLens classifies Han Nôm characters on-device with 97.6% accuracy. When the on-device model is uncertain (confidence below 60%), it can escalate to Claude — Anthropic's AI — for a second opinion.")
                    .font(.footnote)
                    .foregroundStyle(NomTheme.stone600)
                    .lineSpacing(3)

                Text("Without a key, the app still works — uncertain characters are flagged with a low-confidence badge instead of being sent to Claude.")
                    .font(.footnote)
                    .foregroundStyle(NomTheme.stone600)
                    .lineSpacing(3)

                Text("Get a free key at console.anthropic.com")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(NomTheme.lacquer500)
                    .padding(.top, 2)
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
        }
    }
}

#Preview {
    SettingsView()
}
