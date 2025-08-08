import SwiftUI

/// Overlay container for notifications that appear on top of the main interface
struct NotificationOverlay: View {
    @Environment(NotificationSystem.self) private var notificationSystem
    
    var body: some View {
        VStack {
            // Top notifications area
            if let notification = notificationSystem.currentNotification {
                HStack {
                    Spacer()
                    
                    ExclusionNotificationView(
                        notification: notification,
                        onInclude: {
                            let urls = notificationSystem.includeExcludedFiles()
                            if !urls.isEmpty {
                                NotificationCenter.default.post(
                                    name: .includeExcludedFiles,
                                    object: urls
                                )
                            }
                        },
                        onDismiss: {
                            notificationSystem.dismissNotification()
                        }
                    )
                    .frame(maxWidth: 400)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.3), value: notification.id)
                    
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
            }
            
            Spacer()
        }
        .allowsHitTesting(notificationSystem.currentNotification != nil)
    }
}

// MARK: - Environment Key

private struct NotificationSystemKey: EnvironmentKey {
    static let defaultValue = NotificationSystem()
}

extension EnvironmentValues {
    var notificationSystem: NotificationSystem {
        get { self[NotificationSystemKey.self] }
        set { self[NotificationSystemKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    func notificationSystem(_ system: NotificationSystem) -> some View {
        environment(\.notificationSystem, system)
    }
}