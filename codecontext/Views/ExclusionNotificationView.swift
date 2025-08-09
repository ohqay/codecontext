import SwiftUI

/// Non-intrusive notification view for file exclusions
struct ExclusionNotificationView: View {
    let notification: NotificationSystem.ExclusionNotification
    let onInclude: () -> Void
    let onDismiss: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and controls
            HStack {
                // Status icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(.headline)
                    Text(notification.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    Button("Include") {
                        onInclude()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            
            // Expandable details
            if isExpanded {
                Divider()
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(notification.exclusions, id: \.url) { exclusion in
                            ExclusionDetailRow(exclusion: exclusion)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            
            // Always show expand/collapse toggle if there are exclusions
            if !notification.exclusions.isEmpty {
                Button(action: { isExpanded.toggle() }) {
                    HStack {
                        Text(isExpanded ? "Show less" : "Show details (\(notification.exclusions.count))")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

/// Individual exclusion detail row
private struct ExclusionDetailRow: View {
    let exclusion: ExclusionDetector.ExclusionResult
    
    var body: some View {
        HStack {
            // File type icon
            Image(systemName: exclusion.exclusionType.iconName)
                .foregroundStyle(exclusion.exclusionType.iconColor)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(exclusion.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                
                Text(exclusion.exclusionType.displayReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !exclusion.canOverride {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Extensions

private extension ExclusionDetector.ExclusionType {
    var iconName: String {
        switch self {
        case .binary:
            return "doc.plaintext"
        case .tooLarge:
            return "doc.badge.plus"
        case .sensitiveFile(let reason):
            switch reason {
            case .dotenvFile:
                return "gearshape.fill"
            case .apiKeyPattern, .secretPattern:
                return "key.fill"
            case .privateKey:
                return "lock.shield.fill"
            }
        }
    }
    
    var iconColor: Color {
        switch self {
        case .binary:
            return .blue
        case .tooLarge:
            return .orange
        case .sensitiveFile:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Preview with few exclusions
        ExclusionNotificationView(
            notification: NotificationSystem.ExclusionNotification(
                exclusions: [
                    ExclusionDetector.ExclusionResult(
                        url: URL(filePath: "/path/to/image.png"),
                        exclusionType: .binary
                    ),
                    ExclusionDetector.ExclusionResult(
                        url: URL(filePath: "/path/to/.env"),
                        exclusionType: .sensitiveFile(reason: .dotenvFile)
                    )
                ]
            ),
            onInclude: {},
            onDismiss: {}
        )
        
        // Preview with many exclusions
        ExclusionNotificationView(
            notification: NotificationSystem.ExclusionNotification(
                exclusions: Array(0..<8).map { i in
                    ExclusionDetector.ExclusionResult(
                        url: URL(filePath: "/path/to/file\(i).bin"),
                        exclusionType: .binary
                    )
                }
            ),
            onInclude: {},
            onDismiss: {}
        )
    }
    .padding()
    .frame(width: 400)
}