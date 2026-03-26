import SwiftUI
import Combine
import SwiftData

// MARK: - Service container

/// Creates `ClaudeService` once at startup and surfaces any configuration error.
@MainActor
private final class ServiceContainer: ObservableObject {
    let viewModel: DecoderViewModel?
    let setupError: String?

    init() {
        do {
            let service = try ClaudeService()
            viewModel = DecoderViewModel(decoder: service)
            setupError = nil
        } catch {
            viewModel = nil
            setupError = "CLAUDE_API_KEY not configured.\nAdd it to Config.xcconfig and re-run."
        }
    }
}

// MARK: - Navigation routes

private enum Route: Hashable {
    case preprocessing(WrappedImage)
    case segmentationReview(WrappedImage)   // crops read from vm.segmentedCrops
    case results(WrappedImage)              // results read from vm.currentResults
}

/// `UIImage` is not `Hashable`. Wrap it with a stable UUID for NavigationStack.
private struct WrappedImage: Hashable {
    let id = UUID()
    let image: UIImage
    static func == (lhs: WrappedImage, rhs: WrappedImage) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Root view

struct ContentView: View {
    @StateObject private var container = ServiceContainer()
    @State private var showCamera = false
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            root
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                navPath.append(Route.preprocessing(WrappedImage(image: image)))
            }
        }
    }

    // MARK: - Root screen

    @ViewBuilder
    private var root: some View {
        if let vm = container.viewModel {
            ZStack(alignment: .bottom) {
                HistoryView()

                Button {
                    vm.cancel()
                    showCamera = true
                } label: {
                    Label("New Scan", systemImage: "camera.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(radius: 6, y: 3)
                }
                .padding(.bottom, 24)
            }
        } else {
            setupErrorView
        }
    }

    // MARK: - Navigation destinations

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .preprocessing(let wrapped):
            if let vm = container.viewModel {
                PreprocessingView(
                    sourceImage: wrapped.image,
                    vm: vm,
                    onSegmented: { _ in
                        navPath.append(Route.segmentationReview(wrapped))
                    },
                    onZeroDetected: {
                        navPath.removeLast()
                        showCamera = true
                    }
                )
            }

        case .segmentationReview(let wrapped):
            if let vm = container.viewModel {
                SegmentationReviewView(
                    sourceImage: wrapped.image,
                    crops: vm.segmentedCrops ?? [],
                    vm: vm,
                    onDone: { _ in
                        navPath.append(Route.results(wrapped))
                    }
                )
            }

        case .results(let wrapped):
            if let results = container.viewModel?.currentResults {
                ResultView(sourceImage: wrapped.image, results: results)
            }
        }
    }

    // MARK: - Error screen

    private var setupErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Configuration Required")
                .font(.title2.bold())
            Text(container.setupError ?? "Unknown error")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("NomLens")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DecodingSession.self, inMemory: true)
}
