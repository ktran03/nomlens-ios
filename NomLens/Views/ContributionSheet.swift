import SwiftUI

/// Metadata form shown after a decode to contribute the scan to the public archive.
struct ContributionSheet: View {
    let sourceImage: UIImage
    let results: [CharacterDecodeResult]
    let fullTransliteration: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var sourceType: NLSource.SourceType = .other
    @State private var title = ""
    @State private var locationName = ""
    @State private var province = ""
    @State private var country = "Vietnam"
    @State private var condition: NLSource.SourceCondition = .good
    @State private var estimatedPeriod = ""
    @State private var isSubmitting = false
    @State private var submitError: String?

    private var canSubmit: Bool { !isSubmitting }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                locationSection
                conditionSection

                if let err = submitError {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Contribute to Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView().tint(NomTheme.lacquer500)
                    } else {
                        Button("Submit") { submit() }
                            .fontWeight(.semibold)
                            .foregroundStyle(canSubmit ? NomTheme.lacquer500 : Color.secondary)
                            .disabled(!canSubmit)
                    }
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    // MARK: - Form sections

    private var sourceSection: some View {
        Section("Source") {
            Picker("Type", selection: $sourceType) {
                ForEach(NLSource.SourceType.allCases, id: \.self) { t in
                    Label(t.label, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.navigationLink)

            TextField("Title (optional)", text: $title)
                .autocorrectionDisabled()

            TextField("Estimated period (e.g. 15th century)", text: $estimatedPeriod)
                .autocorrectionDisabled()
        }
    }

    private var locationSection: some View {
        Section {
            TextField("e.g. Temple of Literature, Hà Nội", text: $locationName)
                .autocorrectionDisabled()
            TextField("Province / Region (optional)", text: $province)
                .autocorrectionDisabled()
            TextField("Country", text: $country)
                .autocorrectionDisabled()
        } header: {
            Text("Location")
        }
    }

    private var conditionSection: some View {
        Section("Condition") {
            Picker("Condition", selection: $condition) {
                ForEach(NLSource.SourceCondition.allCases, id: \.self) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.navigationLink)
        }
    }

    // MARK: - Submit

    private func submit() {
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespaces)

        isSubmitting = true
        submitError  = nil
        let deviceId = SupabaseClient.deviceId

        Task {
            do {
                let client = SupabaseClient.shared

                // 1. Create the source record.
                let newSource = NewSource(
                    title: title.isEmpty ? nil : title,
                    sourceType: sourceType,
                    estimatedPeriod: estimatedPeriod.isEmpty ? nil : estimatedPeriod,
                    locationName: trimmedLocation.isEmpty ? "Unknown" : trimmedLocation,
                    province: province.isEmpty ? nil : province,
                    country: country.isEmpty ? "Vietnam" : country,
                    coordinates: nil,
                    condition: condition,
                    contributorDeviceId: deviceId
                )
                let source = try await client.createSource(newSource)

                // 2. Build inline decode results for the scan record.
                let decodeResults: [NLScan.DecodeResult] = results.enumerated().compactMap { i, r in
                    guard let char = r.character else { return nil }
                    return NLScan.DecodeResult(
                        index: i,
                        unicode: char,
                        quocNgu: r.quocNgu,
                        confidence: r.confidence == .none ? nil : r.confidence.rawValue,
                        scriptType: r.type?.rawValue
                    )
                }

                // 3. Create the scan record (imagePath filled in after upload).
                let newScan = NewScan(
                    sourceId: source.id,
                    contributorDeviceId: deviceId,
                    imagePath: nil,
                    thumbnailPath: nil,
                    characterCount: results.count,
                    transliteration: fullTransliteration.isEmpty ? nil : fullTransliteration,
                    decodeResults: decodeResults.isEmpty ? nil : decodeResults,
                    hasCorrections: false
                )
                let scan = try await client.createScan(newScan)

                // 4. Upload image using the real scan ID (best-effort — non-fatal).
                if let jpeg = ImageUtilities.jpegData(from: sourceImage) {
                    _ = try? await client.uploadScanImage(
                        jpeg, sourceId: source.id, scanId: scan.id
                    )
                }

                // 5. Bulk insert individual characters.
                let newChars: [NewCharacter] = results.enumerated().compactMap { i, r in
                    guard let char = r.character else { return nil }
                    let conf: NLCharacter.ConfidenceLevel? = switch r.confidence {
                    case .high:   .high
                    case .medium: .medium
                    case .low:    .low
                    case .none:   nil
                    }
                    let script: NLCharacter.ScriptType? = switch r.type {
                    case .han:  .han
                    case .nom:  .nom
                    default:    nil
                    }
                    return NewCharacter(
                        scanId: scan.id,
                        sourceId: source.id,
                        positionIndex: i,
                        unicodeChar: char,
                        quocNgu: r.quocNgu,
                        meaning: r.meaning,
                        confidence: conf,
                        scriptType: script,
                        isCorrected: false
                    )
                }
                try await client.insertCharacters(newChars)

                await MainActor.run {
                    isSubmitting = false
                    onDone()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submitError  = error.localizedDescription
                }
            }
        }
    }
}
