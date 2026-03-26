import SwiftUI

/// Root view — placeholder until CameraView and navigation are wired up in M6.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "character.magnify")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("NomLens")
                .font(.largeTitle.bold())
            Text("M1 — Foundation complete")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
