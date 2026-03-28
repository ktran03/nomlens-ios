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
    @State private var errorMessage: String? = nil

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

                SegmentButton(isWorking: vm.isWorking, label: workingLabel) {
                    segment()
                }
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
        .onChange(of: vm.failureMessage) { _, msg in
            if let msg { errorMessage = msg }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil; vm.cancel() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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

// MARK: - Segment button

/// Custom tappable view — avoids `Button` so iOS cannot apply its own
/// disabled/pressed tinting that washes out the label.
private struct SegmentButton: View {
    let isWorking: Bool
    let label: String
    let action: () -> Void

    @State private var glowing = false

    var body: some View {
        HStack(spacing: 10) {
            if isWorking {
                ProgressView().tint(.white)
            }
            Text(isWorking ? label : "Segment Image")
        }
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding()
        .background(isWorking ? Color.red : Color.accentColor)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: glowing ? .red.opacity(0.7) : .clear, radius: glowing ? 18 : 0)
        .onTapGesture { if !isWorking { action() } }
        .onChange(of: isWorking) { _, working in
            if working {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    glowing = false
                }
            }
        }
    }
}
