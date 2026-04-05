import SwiftUI

/// Mission statement, how-it-works pipeline, and model stats.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    aboutHero
                    missionSection
                    howItWorksSection
                    modelStatsSection
                    audienceSection
                    footerSection
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Hero

    private var aboutHero: some View {
        ZStack(alignment: .bottom) {
            NomTheme.stone950
                .ignoresSafeArea(edges: .top)

            Text("字")
                .font(.system(size: 220, weight: .black, design: .serif))
                .foregroundStyle(Color.white.opacity(0.04))
                .offset(x: -60, y: 16)
                .allowsHitTesting(false)

            VStack(spacing: 10) {
                Spacer().frame(height: 72)

                Text("NomLens")
                    .font(.system(size: 46, weight: .bold, design: .serif))
                    .foregroundStyle(.white)

                Text("漢喃 · Chữ Nôm · Classical Vietnamese")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.bottom, 28)
            }
        }
        .frame(minHeight: 260)
    }

    // MARK: - Mission

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionEyebrow("Mission")

            Text("Why NomLens exists")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(NomTheme.stone900)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 14) {
                missionParagraph("For nearly a thousand years, Han Nôm was the soul of Vietnamese culture — the script in which ancestors recorded history, poetry, law, medicine, and philosophy. It appears on ancient stone steles, temple inscriptions, wooden couplets, imperial manuscripts, and fragile paper documents.")

                missionParagraph("Today, that memory is in mortal danger. Every year, physical inscriptions erode under rain, wind, and pollution. Manuscripts crumble. The last generation of living scholars who can fluently read Han Nôm is rapidly shrinking — perhaps no more than a hundred people in the world still possess deep, native-level mastery of the script.")

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(NomTheme.lacquer500.opacity(0.06))
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(NomTheme.lacquer500)
                            .frame(width: 3)
                            .clipShape(Capsule())
                        Text("\"Once a script dies, the history it carried dies with it. Lose the writing, and you lose the culture.\"")
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(NomTheme.lacquer600)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.vertical, 4)

                missionParagraph("NomLens was created to break this cycle of loss. It is not just another OCR tool — it is cultural rescue infrastructure. A mobile platform designed so that anyone with a smartphone can become a participant in the preservation of Vietnam's classical heritage.")

                missionParagraph("We are in a narrow window where the last expert readers, the surviving physical artifacts, and modern AI technology still overlap. NomLens aims to seize that window — to capture as much Han Nôm as possible while it can still be read and understood by humans, then preserve it digitally for future generations.")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .background(Color(.systemBackground))
    }

    private func missionParagraph(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(NomTheme.stone600)
            .lineSpacing(5)
    }

    // MARK: - How it works

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            VStack(alignment: .leading, spacing: 24) {
                sectionEyebrow("Pipeline")

                Text("How NomLens works")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(NomTheme.stone900)

                Text("Five steps from raw photo to structured decode. Steps 1–4 run entirely on-device.")
                    .font(.subheadline)
                    .foregroundStyle(NomTheme.stone500)

                VStack(spacing: 0) {
                    pipelineStep(
                        number: "1",
                        icon: "camera.fill",
                        title: "Photograph",
                        body: "Point your camera at any Han Nôm source — a stone stele, temple inscription, manuscript page, or printed text. NomLens accepts photos from your library too."
                    )
                    stepConnector
                    pipelineStep(
                        number: "2",
                        icon: "slider.horizontal.3",
                        title: "Preprocess",
                        body: "Core Image filters run on-device in milliseconds: adaptive thresholding corrects uneven lighting on weathered stone, noise reduction cleans aged manuscript ink, and perspective correction fixes keystoning."
                    )
                    stepConnector
                    pipelineStep(
                        number: "3",
                        icon: "squareshape.split.2x2",
                        title: "Segment & Sort",
                        body: "Apple's Vision framework locates individual characters. NomLens clusters them into columns and sorts right-to-left, top-to-bottom — the correct Han Nôm reading order."
                    )
                    stepConnector
                    pipelineStep(
                        number: "4",
                        icon: "cpu",
                        title: "Classify On-Device",
                        body: "Each character crop is passed to an on-device Core ML model (EfficientNet-B0, 10.6 MB). High-confidence results are instant. Low-confidence characters can escalate to Claude Vision API for expert fallback."
                    )
                    stepConnector
                    pipelineStep(
                        number: "5",
                        icon: "list.bullet.rectangle",
                        title: "Results",
                        body: "A structured grid returns each character with its Unicode form, Quốc ngữ transliteration, English meaning, and a confidence badge. Tap any cell for full decode details and to make corrections."
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(NomTheme.parchment50)
    }

    private func pipelineStep(number: String, icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Step badge
            ZStack {
                Circle()
                    .fill(NomTheme.lacquer500)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("0\(number)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NomTheme.lacquer500)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NomTheme.stone800)
                }
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(NomTheme.stone600)
                    .lineSpacing(4)
            }
            .padding(.bottom, 8)
        }
    }

    private var stepConnector: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 19) // center under 40pt circle
            Rectangle()
                .fill(NomTheme.lacquer500.opacity(0.25))
                .frame(width: 2, height: 24)
            Spacer()
        }
    }

    // MARK: - Model stats

    private var modelStatsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 24) {
                sectionEyebrow("Model")

                Text("By the numbers")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(NomTheme.stone900)

                Text("EfficientNet-B0 with temperature-scaled calibration. Trained on HWDB handwriting + Han Nôm font renders.")
                    .font(.subheadline)
                    .foregroundStyle(NomTheme.stone500)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    statCard(value: "97.6%",  label: "Validation accuracy")
                    statCard(value: "99.3%",  label: "Precision ≥90% confidence")
                    statCard(value: "<10ms",  label: "Inference on Neural Engine")
                    statCard(value: "10.6 MB", label: "Model size")
                    statCard(value: "972",    label: "Character classes (v1)")
                    statCard(value: "296K+",  label: "Training images")
                    statCard(value: "0.0034", label: "Calibration error (ECE)")
                    statCard(value: "1.4%",   label: "Routes to cloud fallback")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(Color(.systemBackground))
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(NomTheme.lacquer500)
            Text(label)
                .font(.caption)
                .foregroundStyle(NomTheme.stone500)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NomTheme.stone50)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(NomTheme.stone200, lineWidth: 0.5))
    }

    // MARK: - Audience

    private var audienceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                sectionEyebrow("Who It's For")

                audienceCard(
                    icon: "building.columns.fill",
                    title: "Field Users",
                    subtitle: "Works where the inscriptions are",
                    body: "Remote temples, rural steles, archaeological sites with no cell signal. NomLens runs entirely on-device. No internet required after the initial model download."
                )
                audienceCard(
                    icon: "scroll.fill",
                    title: "Scholars",
                    subtitle: "Accuracy you can cite",
                    body: "97.6% validation accuracy on the Han layer. Temperature-calibrated confidence scores (ECE 0.0034). Full decode provenance: character, Unicode codepoint, model version."
                )
                audienceCard(
                    icon: "wand.and.stars",
                    title: "Cultural Stewards",
                    subtitle: "Every correction matters",
                    body: "When you correct a misread character, that data can feed back into the next model version — making NomLens more accurate for every future user who points a camera at the same inscription."
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(NomTheme.parchment50)
    }

    private func audienceCard(icon: String, title: String, subtitle: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(NomTheme.lacquer500.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(NomTheme.lacquer500)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NomTheme.stone800)
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NomTheme.lacquer600)
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(NomTheme.stone600)
                    .lineSpacing(3)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(NomTheme.stone200, lineWidth: 0.5))
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Divider()
            VStack(spacing: 6) {
                Text("NomLens")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(NomTheme.stone700)
                Text("漢喃 · Chữ Nôm · Classical Vietnamese")
                    .font(.caption)
                    .foregroundStyle(NomTheme.stone400)
                Text("Decoding Han Nôm script for scholars, researchers,\nand anyone who wants to read what time is erasing.")
                    .font(.caption2)
                    .foregroundStyle(NomTheme.stone400)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Shared helpers

    private func sectionEyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(2.5)
            .textCase(.uppercase)
            .foregroundStyle(NomTheme.lacquer500)
            .padding(.bottom, 4)
    }
}

#Preview {
    AboutView()
}
