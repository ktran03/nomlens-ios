import SwiftUI

/// Shows the selected image and lets the user choose a preprocessing preset
/// before running Vision segmentation.
struct PreprocessingView: View {
    let sourceImage: UIImage
    @ObservedObject var vm: DecoderViewModel

    let onSegmented: ([CharacterCrop]) -> Void
    let onZeroDetected: () -> Void

    @State private var preset: Preset = .default
    @State private var showZeroAlert = false

    // MARK: - Presets

    enum Preset: String, CaseIterable, Identifiable {
        case `default`  = "Default"
        case stele      = "Stele"
        case manuscript = "Manuscript"
        case cleanPrint = "Clean Print"
        var id: String { rawValue }

        var settings: PreprocessingSettings {
            switch self {
            case .default:    return PreprocessingSettings()
            case .stele:      return .stele
            case .manuscript: return .manuscript
            case .cleanPrint: return .cleanPrint
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preset")
                        .font(.headline)
                        .padding(.horizontal)

                    Picker("Preset", selection: $preset) {
                        ForEach(Preset.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Text(preset.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Button(action: segment) {
                    Group {
                        if vm.isWorking {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text(workingLabel)
                            }
                        } else {
                            Text("Segment Image")
                        }
                    }
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.isWorking ? Color.accentColor.opacity(0.7) : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(vm.isWorking)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top)
        }
        .navigationTitle("Preprocessing")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: vm.isSegmented) { _, segmented in
            if segmented, let crops = vm.segmentedCrops {
                onSegmented(crops)
            }
        }
        .onChange(of: vm.isZeroDetected) { _, zero in
            if zero { showZeroAlert = true }
        }
        .alert("No Characters Found", isPresented: $showZeroAlert) {
            Button("Try Another Preset") { vm.cancel() }
            Button("Continue Anyway", role: .destructive) { onZeroDetected() }
        } message: {
            Text("Vision could not detect any characters. Try a different preset or adjust lighting.")
        }
    }

    private var workingLabel: String {
        switch vm.state {
        case .preprocessing: return "Preprocessing…"
        case .segmenting:    return "Segmenting…"
        default:             return "Working…"
        }
    }

    private func segment() {
        vm.settings = preset.settings
        vm.segmentOnly(image: sourceImage)
    }
}

private extension PreprocessingView.Preset {
    var description: String {
        switch self {
        case .default:    return "Balanced settings for most images."
        case .stele:      return "High contrast + adaptive threshold for weathered stone carvings."
        case .manuscript: return "Moderate contrast boost for aged paper manuscripts."
        case .cleanPrint: return "Minimal processing for modern or clean printed text."
        }
    }
}
