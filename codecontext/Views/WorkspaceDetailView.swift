import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceDetailView: View {
    let workspace: SDWorkspace
    @Binding var includeFileTree: Bool
    @Binding var selectedTokenCount: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationSystem.self) private var notificationSystem
    @State private var output: String = ""
    @State private var totalTokens: Int = 0
    @State private var streamingEngine: StreamingContextEngine?
    @State private var regenerationTask: Task<Void, Never>?
    @State private var lastSelectionJSON: String = ""
    @State private var selectedFileCount = 0
    @State private var allFiles: [FileInfo] = []

    var body: some View {
        ZStack {
            // Background layer with extension effect
            Color.clear
                .background(.thinMaterial)
                .backgroundExtensionEffect()

            VStack(spacing: 0) {
                OutputHeader(
                    includeFileTree: $includeFileTree,
                    selectedFileCount: selectedFileCount,
                    selectedTokenCount: selectedTokenCount
                )
                Divider()

                OutputPreview(text: output)
            }
        }
        .toolbar { OutputToolbar() }
        .apply(
            OutputNotificationHandlers(
                output: output,
                onRefresh: { await regenerateOutput() }
            )
        )
        .apply(
            WorkspaceChangeHandlers(
                workspace: workspace,
                includeFileTree: includeFileTree,
                lastSelectionJSON: $lastSelectionJSON,
                onTreeToggle: scheduleRegeneration,
                onSelectionChange: updateSelectedFileCount
            )
        )
        .apply(
            LifecycleHandlers(
                workspace: workspace,
                engine: $streamingEngine,
                regenerationTask: $regenerationTask,
                lastSelectionJSON: $lastSelectionJSON,
                notificationSystem: notificationSystem,
                onLoad: updateSelectedFileCount,
                loadAllFiles: loadAllFiles,
                regenerateOutput: regenerateOutput
            ))
    }

    private func regenerateOutput() async {
        let startTime = Date()

        // Don't regenerate if a task is already running
        // Note: We can't check isCancelled reliably, so we'll just proceed

        // Get selected paths from workspace
        let selectedPaths: Set<String>
        if let data = workspace.selectionJSON.data(using: .utf8),
           let paths = try? JSONDecoder().decode(Set<String>.self, from: data)
        {
            selectedPaths = paths
        } else {
            selectedPaths = []
        }

        // Generate empty codebase if no files selected but tree is enabled
        if selectedPaths.isEmpty {
            if includeFileTree {
                output = "<codebase>\n  <fileTree>\n  </fileTree>\n</codebase>\n"
            } else {
                output = "<codebase>\n</codebase>\n"
            }
            totalTokens = 0
            let duration = Date().timeIntervalSince(startTime)
            print("[Generation Complete - Empty] Time: \(String(format: "%.3fs", duration))")
            return
        }

        // Get root URL from workspace
        guard let rootURL = resolveURL(from: workspace) else {
            print("[Generation Failed] Could not resolve workspace URL")
            return
        }

        guard let engine = streamingEngine else {
            print("[Generation Failed] Streaming engine not initialized")
            return
        }

        do {
            print("[Generation Started] Selected files: \(selectedPaths.count)")

            let result = try await engine.generateContext(
                rootURL: rootURL,
                selectedPaths: selectedPaths,
                allFiles: allFiles,
                includeTree: includeFileTree
            )

            output = result.xml
            totalTokens = result.tokenCount
            selectedTokenCount = result.tokenCount

            let totalDuration = Date().timeIntervalSince(startTime)
            print("[Generation Complete] Files: \(result.filesProcessed), Tokens: \(result.tokenCount)")
            print("  - Engine processing time: \(String(format: "%.3fs", result.generationTime))")
            print("  - Total end-to-end time: \(String(format: "%.3fs", totalDuration))")

            if totalDuration - result.generationTime > 0.5 {
                print("  - Overhead time: \(String(format: "%.3fs", totalDuration - result.generationTime)) (includes file loading, UI updates)")
            }
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("[Generation Failed] Error after \(String(format: "%.3fs", duration)): \(error)")
            output = "Error generating context: \(error.localizedDescription)"
        }
    }

    private func updateSelectedFileCount() {
        if let data = workspace.selectionJSON.data(using: .utf8),
           let paths = try? JSONDecoder().decode(Set<String>.self, from: data)
        {
            selectedFileCount = paths.count
        } else {
            selectedFileCount = 0
        }
    }

    private func scheduleRegeneration() {
        // Cancel any existing regeneration task
        regenerationTask?.cancel()

        // Schedule new regeneration with longer debouncing for large selections
        regenerationTask = Task {
            // Debounce for 500ms to allow selection operations to complete
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Check if task was cancelled
            if !Task.isCancelled {
                await regenerateOutput()
            }
        }
    }

    private func resolveURL(from workspace: SDWorkspace) -> URL? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: workspace.bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return url
        } catch {
            return nil
        }
    }

    private func loadAllFiles() async {
        guard let root = resolveURL(from: workspace) else { return }

        let scanner = FileScanner()
        let rules = IgnoreRules(
            respectGitIgnore: workspace.respectGitIgnore,
            respectDotIgnore: workspace.respectDotIgnore,
            showHiddenFiles: workspace.showHiddenFiles,
            excludeNodeModules: workspace.excludeNodeModules,
            excludeGit: workspace.excludeGit,
            excludeBuild: workspace.excludeBuild,
            excludeDist: workspace.excludeDist,
            excludeNext: workspace.excludeNext,
            excludeVenv: workspace.excludeVenv,
            excludeDSStore: workspace.excludeDSStore,
            excludeDerivedData: workspace.excludeDerivedData,
            customPatterns: workspace.customIgnore.split(separator: "\n").map(String.init),
            rootPath: root.path
        )

        let options = FileScanner.Options(
            ignoreRules: rules,
            enableExclusionDetection: true,
            allowOverrides: []
        )

        let scanResult = scanner.scanWithExclusions(root: root, options: options)
        allFiles = scanResult.includedFiles
    }
}

private struct OutputHeader: View {
    @Binding var includeFileTree: Bool
    let selectedFileCount: Int
    let selectedTokenCount: Int

    var body: some View {
        HStack {
            Toggle("Include file tree", isOn: $includeFileTree)

            Spacer()

            if selectedFileCount > 0 {
                HStack(spacing: 12) {
                    Text("\(selectedFileCount) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .frame(height: 14)

                    Text("\(formatTokenCount(selectedTokenCount)) tokens")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select files to generate context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count < 1000 {
            return "\(count)"
        } else if count < 1_000_000 {
            return String(format: "%.1fk", Double(count) / 1000)
        } else {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
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

// MARK: - Toolbar

private struct OutputToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            GlassButton(
                systemImage: "doc.on.doc",
                action: copyOutput
            )
            .help("Copy XML Output")
        }
    }

    private func copyOutput() {
        NotificationCenter.default.post(name: .requestCopyOutput, object: nil)
    }
}

// MARK: - View Modifiers

private struct OutputNotificationHandlers: ViewModifier {
    let output: String
    let onRefresh: () async -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .requestCopyOutput)) { _ in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestRefresh)) { _ in
                Task { await onRefresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fileSystemChanged)) { _ in
                Task { await onRefresh() }
            }
    }
}

private struct WorkspaceChangeHandlers: ViewModifier {
    let workspace: SDWorkspace
    let includeFileTree: Bool
    @Binding var lastSelectionJSON: String
    let onTreeToggle: () -> Void
    let onSelectionChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: includeFileTree) { _, _ in
                onTreeToggle()
            }
            .onChange(of: workspace.selectionJSON) { _, newValue in
                // Auto-generate when selection changes
                if newValue != lastSelectionJSON {
                    lastSelectionJSON = newValue
                    onSelectionChange()
                    onTreeToggle() // Trigger regeneration
                }
            }
    }
}

private struct LifecycleHandlers: ViewModifier {
    let workspace: SDWorkspace
    @Binding var engine: StreamingContextEngine?
    @Binding var regenerationTask: Task<Void, Never>?
    @Binding var lastSelectionJSON: String
    let notificationSystem: NotificationSystem
    let onLoad: () -> Void
    let loadAllFiles: () async -> Void
    let regenerateOutput: () async -> Void

    func body(content: Content) -> some View {
        content
            .task {
                // Initialize streaming engine
                engine = await StreamingContextEngine()
                lastSelectionJSON = workspace.selectionJSON

                // Load all files for the workspace
                await loadAllFiles()

                // Update counts and generate initial output
                onLoad()
                await regenerateOutput()
            }
            .onDisappear {
                // Cancel any pending regeneration when view disappears
                regenerationTask?.cancel()
                regenerationTask = nil
            }
    }
}

// MARK: - Helper Extension

private extension View {
    func apply<T: ViewModifier>(_ modifier: T) -> some View {
        self.modifier(modifier)
    }
}
