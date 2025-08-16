import SwiftUI

/// A reusable section container with title and content, following consistent spacing and layout patterns
struct DetailSection<Content: View>: View {
    let title: String?
    let content: Content
    let horizontalPadding: CGFloat
    let verticalPadding: EdgeInsets
    let spacing: CGFloat

    init(
        title: String? = nil,
        horizontalPadding: CGFloat = 20,
        verticalPadding: EdgeInsets = EdgeInsets(top: 16, leading: 0, bottom: 20, trailing: 0),
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.spacing = spacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title = title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            content
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, verticalPadding.top)
        .padding(.bottom, verticalPadding.bottom)
    }
}

// MARK: - Convenience Constructors

extension DetailSection {
    /// Creates a section with top padding only (for first section)
    init(
        topSectionTitle title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            verticalPadding: EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0),
            content: content
        )
    }

    /// Creates a section with bottom padding only (for last section)
    init(
        bottomSectionTitle title: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            verticalPadding: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0),
            spacing: title == nil ? 0 : 8,
            content: content
        )
    }
}

// MARK: - Preview Support

#if DEBUG
    #Preview {
        VStack(spacing: 20) {
            DetailSection(topSectionTitle: "Instructions") {
                Rectangle()
                    .fill(.blue.opacity(0.3))
                    .frame(height: 120)
                    .styledCard(material: .regularMaterial)
            }

            DetailSection(bottomSectionTitle: "Output") {
                Rectangle()
                    .fill(.green.opacity(0.3))
                    .frame(height: 200)
                    .styledCard(material: .thinMaterial)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.thinMaterial)
    }
#endif
