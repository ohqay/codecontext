import SwiftUI

/// A lightweight toast notification component for brief feedback messages
struct ToastView: View {
    let message: String
    let icon: String
    let backgroundColor: Color
    
    init(
        message: String,
        icon: String = "checkmark.circle.fill",
        backgroundColor: Color = .accentColor
    ) {
        self.message = message
        self.icon = icon
        self.backgroundColor = backgroundColor
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .medium))
            
            Text(message)
                .foregroundStyle(.white)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            backgroundColor.opacity(0.9),
            in: Capsule()
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .glassEffect()
    }
}

/// Toast manager for displaying brief feedback messages
@MainActor
@Observable
final class ToastManager {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let icon: String
        let backgroundColor: Color
        let duration: TimeInterval
        
        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.id == rhs.id
        }
        
        init(
            message: String,
            icon: String = "checkmark.circle.fill",
            backgroundColor: Color = .accentColor,
            duration: TimeInterval = 2.0
        ) {
            self.message = message
            self.icon = icon
            self.backgroundColor = backgroundColor
            self.duration = duration
        }
    }
    
    private(set) var currentToast: Toast?
    private(set) var shouldBounce: Bool = false
    private var hideTask: Task<Void, Never>?
    
    /// Shows a success toast
    func showSuccess(_ message: String, duration: TimeInterval = 2.0) {
        showToast(Toast(
            message: message,
            icon: "checkmark.circle.fill",
            backgroundColor: .accentColor,
            duration: duration
        ))
    }
    
    /// Shows an error toast
    func showError(_ message: String, duration: TimeInterval = 3.0) {
        showToast(Toast(
            message: message,
            icon: "exclamationmark.circle.fill",
            backgroundColor: .red,
            duration: duration
        ))
    }
    
    /// Shows an info toast
    func showInfo(_ message: String, duration: TimeInterval = 2.0) {
        showToast(Toast(
            message: message,
            icon: "info.circle.fill",
            backgroundColor: .blue,
            duration: duration
        ))
    }
    
    private func showToast(_ toast: Toast) {
        // Cancel any existing hide task
        hideTask?.cancel()
        
        // Check if we're replacing a toast with the same message (indicates bounce)
        let shouldTriggerBounce = currentToast != nil && 
                                  currentToast?.message == toast.message &&
                                  currentToast?.icon == toast.icon &&
                                  currentToast?.backgroundColor == toast.backgroundColor
        
        // Set bounce state before updating toast
        shouldBounce = shouldTriggerBounce
        
        // Directly replace the current toast
        currentToast = toast
        
        // Reset bounce state after a brief moment
        if shouldTriggerBounce {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                shouldBounce = false
            }
        }
        
        // Schedule auto-hide
        hideTask = Task {
            try? await Task.sleep(for: .seconds(toast.duration))
            
            if !Task.isCancelled {
                currentToast = nil
            }
        }
    }
    
    /// Manually dismisses the current toast
    func dismiss() {
        hideTask?.cancel()
        currentToast = nil
    }
}

/// Overlay container for displaying toasts
struct ToastOverlay: View {
    @Environment(ToastManager.self) private var toastManager
    @State private var isVisible = false
    @State private var displayedToast: ToastManager.Toast?
    @State private var isExiting = false
    @State private var bounceScale: CGFloat = 1.0
    
    var body: some View {
        VStack {
            Spacer()
            
            if let toast = displayedToast {
                ToastView(
                    message: toast.message,
                    icon: toast.icon,
                    backgroundColor: toast.backgroundColor
                )
                .id(toast.id) // Force recreation on each new toast
                .scaleEffect((isVisible ? 1.0 : 0.65) * bounceScale)
                .opacity(isVisible ? 1.0 : 0.0)
                .offset(y: isVisible ? 0 : (isExiting ? -10 : 20))
            }
        }
        .padding(.bottom, 20)
        .allowsHitTesting(false) // Allow touches to pass through
        .onChange(of: toastManager.shouldBounce) { _, shouldBounce in
            if shouldBounce && isVisible {
                // Scale-up with easeOut (decelerates at end, preserving momentum)
                withAnimation(.easeOut(duration: 0.2)) {  // Slightly faster: 0.25 → 0.2
                    bounceScale = 1.05  // More subtle bounce
                }
                
                // Scale-down starts before scale-up fully completes for smooth transition
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))  // Adjusted timing: 180 → 150
                    withAnimation(.easeIn(duration: 0.25)) {  // Slightly faster: 0.3 → 0.25
                        bounceScale = 1.0
                    }
                }
            }
        }
        .onChange(of: toastManager.currentToast) { oldToast, newToast in
            if let newToast = newToast {
                if oldToast != nil {
                    // Check if this is a bounce situation (same message content)
                    let isBounce = oldToast?.message == newToast.message &&
                                   oldToast?.icon == newToast.icon &&
                                   oldToast?.backgroundColor == newToast.backgroundColor
                    
                    if !isBounce {
                        // Different toast - update displayed toast without exit animation
                        displayedToast = newToast
                        isExiting = false
                        // Keep isVisible = true for smooth transition
                    }
                    // If it's a bounce, don't update displayedToast - keep the same view
                } else {
                    // New toast appearing from nothing
                    displayedToast = newToast
                    isExiting = false
                    isVisible = false
                    
                    // Bouncy entrance animation
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.62, blendDuration: 0)) {
                        isVisible = true
                    }
                }
            } else if oldToast != nil && newToast == nil && isVisible {
                // Toast being dismissed - animate out
                isExiting = true
                withAnimation(.spring(response: 0.32, dampingFraction: 0.7, blendDuration: 0)) {
                    isVisible = false
                }
                
                // Clear displayed toast after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    displayedToast = nil
                    isExiting = false
                }
            }
        }
        .onAppear {
            // Handle initial toast if one exists
            if let currentToast = toastManager.currentToast, displayedToast == nil {
                displayedToast = currentToast
                isVisible = false
                
                // Bouncy entrance animation
                withAnimation(.spring(response: 0.36, dampingFraction: 0.62, blendDuration: 0)) {
                    isVisible = true
                }
            }
        }
    }
}

// MARK: - Environment Key

private struct ToastManagerKey: EnvironmentKey {
    static let defaultValue = ToastManager()
}

extension EnvironmentValues {
    var toastManager: ToastManager {
        get { self[ToastManagerKey.self] }
        set { self[ToastManagerKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    func toastManager(_ manager: ToastManager) -> some View {
        environment(\.toastManager, manager)
    }
}

// MARK: - Preview Support

#if DEBUG
    #Preview {
        VStack(spacing: 20) {
            ToastView(message: "Context copied")
            ToastView(message: "Error occurred", icon: "exclamationmark.circle.fill", backgroundColor: .red)
            ToastView(message: "Info message", icon: "info.circle.fill", backgroundColor: .blue)
        }
        .padding()
        .background(.thinMaterial)
    }
#endif
