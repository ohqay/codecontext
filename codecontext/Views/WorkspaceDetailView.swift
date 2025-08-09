import SwiftUI

struct WorkspaceDetailView: View {
    let workspace: SDWorkspace
    @Binding var includeFileTree: Bool
    @Binding var selectedTokenCount: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationSystem.self) private var notificationSystem
    @State private var output: String = ""
    @State private var totalTokens: Int = 0
    @State private var engine: WorkspaceEngine?
    @State private var regenerationTask: Task<Void, Never>?
    @State private var lastSelectionJSON: String = ""
    @State private var isGenerating = false
    @State private var generationProgress: Double = 0.0
    @State private var progressMessage = ""
    @State private var selectedFileCount = 0

    var body: some View {
        VStack(spacing: 0) {
            OutputHeader(
                includeFileTree: $includeFileTree,
                isGenerating: isGenerating,
                selectedFileCount: selectedFileCount,
                selectedTokenCount: selectedTokenCount,
                onGenerate: scheduleRegeneration
            )
            Divider()
            
            if isGenerating {
                GenerationProgressView(
                    progress: generationProgress,
                    message: progressMessage,
                    onCancel: cancelGeneration
                )
            } else {
                OutputPreview(text: output)
            }
        }
        .toolbar { OutputToolbar() }
        .apply(OutputNotificationHandlers(
            output: output,
            onRefresh: { await regenerateOutput() }
        ))
        .apply(WorkspaceChangeHandlers(
            workspace: workspace,
            includeFileTree: includeFileTree,
            lastSelectionJSON: $lastSelectionJSON,
            onTreeToggle: scheduleRegeneration,
            onSelectionChange: updateSelectedFileCount
        ))
        .apply(LifecycleHandlers(
            workspace: workspace,
            engine: $engine,
            regenerationTask: $regenerationTask,
            lastSelectionJSON: $lastSelectionJSON,
            notificationSystem: notificationSystem,
            onLoad: updateSelectedFileCount
        ))
    }
    
    private func cancelGeneration() {
        regenerationTask?.cancel()
        isGenerating = false
    }

    private func regenerateOutput() async {
        isGenerating = true
        progressMessage = "Generating XML..."
        generationProgress = 0
        
        if let result = await engine?.generateWithProgress(
            for: workspace,
            modelContext: modelContext,
            includeTree: includeFileTree,
            onProgress: { current, total in
                Task { @MainActor in
                    generationProgress = Double(current) / Double(total) * 100
                    progressMessage = "Processing file \(current) of \(total)..."
                }
            }
        ) {
            output = result.xml
            totalTokens = result.totalTokens
        }
        
        isGenerating = false
    }
    
    private func updateSelectedFileCount() {
        if let data = workspace.selectionJSON.data(using: .utf8),
           let paths = try? JSONDecoder().decode(Set<String>.self, from: data) {
            selectedFileCount = paths.count
        } else {
            selectedFileCount = 0
        }
    }
    
    private func scheduleRegeneration() {
        // Cancel any existing regeneration task
        regenerationTask?.cancel()
        
        // Schedule new regeneration with debouncing
        regenerationTask = Task {
            // Debounce for 500ms
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Check if task was cancelled
            if !Task.isCancelled {
                await regenerateOutput()
            }
        }
    }
}

private struct OutputHeader: View {
    @Binding var includeFileTree: Bool
    let isGenerating: Bool
    let selectedFileCount: Int
    let selectedTokenCount: Int
    let onGenerate: () -> Void
    
    var body: some View {
        HStack {
            Toggle("Include file tree", isOn: $includeFileTree)
            
            Spacer()
            
            if selectedFileCount > 0 {
                HStack(spacing: 12) {
                    Text("\(selectedFileCount) files selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                        .frame(height: 14)
                    
                    Text("Tokens: \(selectedTokenCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            
            Button(action: onGenerate) {
                Label("Generate", systemImage: "doc.text")
            }
            .buttonStyle(.glass)
            .disabled(isGenerating || selectedFileCount == 0)
            .help(selectedFileCount == 0 ? "Select files to generate XML" : "Generate XML for selected files")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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

// MARK: - Progress View

private struct GenerationProgressView: View {
    let progress: Double
    let message: String
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress, total: 100)
                .progressViewStyle(.linear)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel", action: onCancel)
                .buttonStyle(.glass)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Toolbar

private struct OutputToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: copyOutput) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 16, weight: .regular))
            }
            .buttonStyle(.glass)
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
                // Only update count, don't auto-generate
                if newValue != lastSelectionJSON {
                    lastSelectionJSON = newValue
                    onSelectionChange()
                }
            }
    }
}

private struct LifecycleHandlers: ViewModifier {
    let workspace: SDWorkspace
    @Binding var engine: WorkspaceEngine?
    @Binding var regenerationTask: Task<Void, Never>?
    @Binding var lastSelectionJSON: String
    let notificationSystem: NotificationSystem
    let onLoad: () -> Void
    
    func body(content: Content) -> some View {
        content
            .task {
                // Initialize engine with notification system
                engine = WorkspaceEngine(notificationSystem: notificationSystem)
                lastSelectionJSON = workspace.selectionJSON
                
                // Don't auto-generate on load
                onLoad()
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

// MARK: - Content Placeholder

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
