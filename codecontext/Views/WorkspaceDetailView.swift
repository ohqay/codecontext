import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceDetailView: View {
    let workspace: SDWorkspace
    @Binding var includeFileTree: Bool
    @Binding var includeInstructions: Bool
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
    @State private var previousSelectedPaths: Set<String> = []
    @State private var lastGeneratedXML: String = ""

    var body: some View {
        ZStack {
            // Background layer with extension effect
            Color.clear
                .background(.thinMaterial)
                .backgroundExtensionEffect()

            VStack(spacing: 20) {
                // User Instructions Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Instructions")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    UserInstructionsEditor(
                        text: Binding(
                            get: { workspace.userInstructions },
                            set: { workspace.userInstructions = $0 }
                        )
                    )
                    .frame(minHeight: 100, maxHeight: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Context Output Section
                VStack(alignment: .leading, spacing: 8) {
                    OutputHeader(
                        includeFileTree: $includeFileTree,
                        includeInstructions: $includeInstructions,
                        selectedFileCount: selectedFileCount,
                        selectedTokenCount: selectedTokenCount
                    )

                    OutputPreview(text: output)
                        .frame(maxHeight: .infinity)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
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
                includeInstructions: includeInstructions,
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

        // Get selected paths from workspace
        let selectedPaths: Set<String>
        if let data = workspace.selectionJSON.data(using: .utf8),
           let paths = try? JSONDecoder().decode(Set<String>.self, from: data)
        {
            selectedPaths = paths
        } else {
            selectedPaths = []
        }

        // Generate codebase with file tree even if no files selected
        if selectedPaths.isEmpty {
            guard let rootURL = resolveURL(from: workspace) else {
                print("[Generation Failed] Could not resolve workspace URL")
                return
            }

            guard let engine = streamingEngine else {
                print("[Generation Failed] Streaming engine not initialized")
                return
            }

            do {
                let result = try await engine.updateContext(
                    currentXML: "<codebase>\n</codebase>\n",
                    addedPaths: [],
                    removedPaths: [],
                    allFiles: allFiles,
                    includeTree: includeFileTree,
                    rootURL: rootURL,
                    userInstructions: includeInstructions ? workspace.userInstructions : ""
                )

                output = result.xml
                totalTokens = result.tokenCount
                selectedTokenCount = result.tokenCount
                lastGeneratedXML = result.xml
                previousSelectedPaths = []

                let duration = Date().timeIntervalSince(startTime)
                print("[Generation Complete - Empty with Tree] Time: \(String(format: "%.3fs", duration))")
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                print("[Generation Failed] Error after \(String(format: "%.3fs", duration)): \(error)")
                output = "Error generating context: \(error.localizedDescription)"
            }
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
            // Calculate what changed
            let addedPaths = selectedPaths.subtracting(previousSelectedPaths)
            let removedPaths = previousSelectedPaths.subtracting(selectedPaths)

            // Always use incremental updates - even first generation is just adding all files to empty context
            let currentXML = lastGeneratedXML.isEmpty ? "<codebase>\n</codebase>\n" : lastGeneratedXML

            print("[Incremental Update] Added: \(addedPaths.count), Removed: \(removedPaths.count)")
            if !addedPaths.isEmpty {
                print("  - Adding paths: \(Array(addedPaths).prefix(5))\(addedPaths.count > 5 ? "..." : "")")
            }
            if !removedPaths.isEmpty {
                print("  - Removing paths: \(Array(removedPaths).prefix(5))\(removedPaths.count > 5 ? "..." : "")")
            }

            let result = try await engine.updateContext(
                currentXML: currentXML,
                addedPaths: addedPaths,
                removedPaths: removedPaths,
                allFiles: allFiles,
                includeTree: includeFileTree,
                rootURL: rootURL,
                userInstructions: includeInstructions ? workspace.userInstructions : ""
            )

            output = result.xml
            totalTokens = result.tokenCount
            selectedTokenCount = result.tokenCount
            lastGeneratedXML = result.xml
            previousSelectedPaths = selectedPaths

            let totalDuration = Date().timeIntervalSince(startTime)
            print("[Incremental Update Complete] Duration: \(String(format: "%.3fs", totalDuration))")
            print("  - Files processed: \(result.filesProcessed), Total tokens: \(result.tokenCount)")

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
    @Binding var includeInstructions: Bool
    let selectedFileCount: Int
    let selectedTokenCount: Int

    var body: some View {
        HStack {
            Toggle("Include file tree", isOn: $includeFileTree)
            
            Toggle("Include instructions", isOn: $includeInstructions)

            Spacer()

            if selectedFileCount > 0 {
                HStack(spacing: 12) {
                    Text("\(selectedFileCount) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .frame(height: 14)

                    Text("\(AppConfiguration.formatTokenCount(selectedTokenCount)) tokens")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select files to generate context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct OutputPreview: View {
    let text: String

    var body: some View {
        PerformantTextView(text: text)
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
    let includeInstructions: Bool
    @Binding var lastSelectionJSON: String
    let onTreeToggle: () -> Void
    let onSelectionChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: includeFileTree) { _, _ in
                onTreeToggle()
            }
            .onChange(of: includeInstructions) { _, _ in
                onTreeToggle()
            }
            .onChange(of: workspace.userInstructions) { _, _ in
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
