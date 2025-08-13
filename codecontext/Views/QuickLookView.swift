import QuickLookUI
import SwiftUI

// Quick Look preview for file content
struct QuickLookView: View {
    let fileNode: FileNode
    @Environment(\.dismiss) private var dismiss
    @State private var fileContent: String = ""
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .font(.title2)
                Text(fileNode.name)
                    .font(.title3)
                    .lineLimit(1)
                Spacer()
                Text("\(fileNode.tokenCount) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            Divider()

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PerformantTextView(text: fileContent)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(width: 800, height: 600)
        .background(.regularMaterial)
        .task {
            await loadFileContent()
        }
        .onKeyPress(.space) {
            dismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func loadFileContent() async {
        defer { isLoading = false }

        guard let data = try? Data(contentsOf: fileNode.url),
              let content = String(data: data, encoding: .utf8)
        else {
            fileContent = "Unable to load file content"
            return
        }

        // Apply syntax highlighting if possible
        fileContent = applySyntaxHighlighting(to: content, language: LanguageMap.languageHint(for: fileNode.url))
    }

    private func applySyntaxHighlighting(to content: String, language _: String) -> String {
        // For now, return plain text
        // In a production app, you'd use a syntax highlighting library
        return content
    }
}

// Alternative implementation using QLPreviewPanel for native Quick Look
struct NativeQuickLookView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()

        // Use Quick Look panel
        DispatchQueue.main.async {
            if QLPreviewPanel.sharedPreviewPanelExists() {
                let panel = QLPreviewPanel.shared()
                panel?.makeKeyAndOrderFront(nil)
                panel?.reloadData()
            }
        }

        return view
    }

    func updateNSView(_: NSView, context _: Context) {
        // No updates needed
    }

    static func showQuickLook(for _: URL) {
        let panel = QLPreviewPanel.shared()
        panel?.makeKeyAndOrderFront(nil)
        panel?.reloadData()
    }
}
