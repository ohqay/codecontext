import SwiftUI

struct WelcomeView: View {
    @Binding var showingWelcome: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Codecontext")
                .font(.largeTitle.weight(.semibold))
            Text("Prepare and share codebases for LLMs with precise control.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Open Folder…") {
                    NotificationCenter.default.post(name: .requestOpenFromWelcome, object: nil)
                    showingWelcome = false
                }
                .keyboardShortcut(.defaultAction)
                Button("Close") { showingWelcome = false }
            }
        }
        .padding(32)
        .frame(minWidth: 520)
        .onReceive(NotificationCenter.default.publisher(for: .requestOpenFromWelcome)) { _ in }
    }
}


