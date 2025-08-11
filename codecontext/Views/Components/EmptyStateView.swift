import SwiftUI

// MARK: - Empty State View

/// A reusable empty state view for displaying placeholder content with an optional action
public struct EmptyStateView: View {
    let icon: String?
    let iconSize: CGFloat
    let title: String?
    let subtitle: String?
    let action: (() -> Void)?
    let actionTitle: String?
    let actionHint: String?
    let isActionProminent: Bool

    public init(
        icon: String? = nil,
        iconSize: CGFloat = 36,
        title: String? = nil,
        subtitle: String? = nil,
        action: (() -> Void)? = nil,
        actionTitle: String? = nil,
        actionHint: String? = nil,
        isActionProminent: Bool = false
    ) {
        self.icon = icon
        self.iconSize = iconSize
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.actionTitle = actionTitle
        self.actionHint = actionHint
        self.isActionProminent = isActionProminent
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            if title != nil || subtitle != nil {
                VStack(spacing: 4) {
                    if let title = title {
                        Text(title)
                            .font(.headline)
                    }

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 16)
            }

            if let action = action, let actionTitle = actionTitle {
                GlassButton(
                    title: actionTitle,
                    hint: actionHint,
                    isProminent: isActionProminent,
                    action: action
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
