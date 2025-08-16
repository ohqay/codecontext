import SwiftUI

/// A reusable view modifier that applies consistent card styling with background, border, and rounded corners
struct StyledCard: ViewModifier {
    let material: Material
    let cornerRadius: CGFloat
    let borderOpacity: Double
    let borderWidth: CGFloat

    init(
        material: Material = .thinMaterial,
        cornerRadius: CGFloat = 8,
        borderOpacity: Double = 0.75,
        borderWidth: CGFloat = 1
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.borderOpacity = borderOpacity
        self.borderWidth = borderWidth
    }

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.separator.opacity(borderOpacity), lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - View Extension

extension View {
    /// Applies styled card appearance with configurable material
    func styledCard(
        material: Material = .thinMaterial,
        cornerRadius: CGFloat = 8,
        borderOpacity: Double = 0.75,
        borderWidth: CGFloat = 1
    ) -> some View {
        modifier(StyledCard(
            material: material,
            cornerRadius: cornerRadius,
            borderOpacity: borderOpacity,
            borderWidth: borderWidth
        ))
    }
}

// MARK: - Preview Support

#if DEBUG
    #Preview {
        VStack(spacing: 16) {
            Text("Regular Material Card")
                .padding()
                .styledCard(material: .regularMaterial)

            Text("Thin Material Card")
                .padding()
                .styledCard(material: .thinMaterial)

            Text("Custom Corner Radius")
                .padding()
                .styledCard(cornerRadius: 12)
        }
        .padding()
    }
#endif
