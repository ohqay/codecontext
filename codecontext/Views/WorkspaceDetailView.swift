import SwiftUI

struct WorkspaceDetailView: View {
    let workspace: SDWorkspace
    @Binding var includeFileTree: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var output: String = ""
    @State private var totalTokens: Int = 0
    private let engine = WorkspaceEngine()

    var body: some View {
        VStack(spacing: 0) {
            OutputHeader(includeFileTree: $includeFileTree)
            Divider()
            OutputPreview(text: output)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 8) {
                    Image(systemName: "number.square")
                    Text("Tokens: \(totalTokens)").font(.callout.monospacedDigit())
                }
                .padding(6)
                .background(.quaternary, in: Capsule())
                Button("Copy") { NotificationCenter.default.post(name: .requestCopyOutput, object: nil) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestCopyOutput)) { _ in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestRefresh)) { _ in
            // TODO: Recompute
        }
        .task { await regenerateOutput() }
    }

    private func regenerateOutput() async {
        if let result = await engine.generate(for: workspace, modelContext: modelContext, includeTree: includeFileTree) {
            output = result.xml
            totalTokens = result.totalTokens
        }
    }
}

private struct OutputHeader: View {
    @Binding var includeFileTree: Bool
    var body: some View {
        HStack {
            Toggle("Include file tree", isOn: $includeFileTree)
            Spacer()
            Button("Copy XML") {
                NotificationCenter.default.post(name: .requestCopyOutput, object: nil)
            }
        }
        .padding(8)
    }
}

private struct OutputPreview: View {
    let text: String
    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(.thinMaterial)
    }
}

struct ContentPlaceholder<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
