import SwiftUI

// MARK: - Liquid Glass Search Bar

/// A reusable search bar component with macOS 26 Liquid Glass styling
public struct LiquidGlassSearchBar: View {
    @Binding var text: String
    var prompt: String
    @Binding var focused: Bool

    @FocusState private var isFocused: Bool

    // Configuration
    private let iconSize: CGFloat = 15
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 6
    private let cornerRadius: CGFloat = 16

    public init(
        text: Binding<String>,
        prompt: String = "Search",
        focused: Binding<Bool> = .constant(false)
    ) {
        _text = text
        self.prompt = prompt
        _focused = focused
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: iconSize))

            // Search field
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)

            // Clear button (only visible when text exists)
            if !text.isEmpty {
                Button(action: clearText) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: iconSize))
                        .transition(.scale.combined(with: .opacity))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .animation(.smooth(duration: 0.15), value: text.isEmpty)
        .onChange(of: focused) { _, shouldFocus in
            if shouldFocus {
                isFocused = true
                focused = false
            }
        }
        .glassEffect()
    }

    private func clearText() {
        text = ""
    }
}

// MARK: - Search Bar Styles

public extension LiquidGlassSearchBar {
    /// Apply a compact style suitable for toolbars
    func compactStyle() -> some View {
        scaleEffect(0.9)
    }

    /// Apply custom padding around the search bar
    func searchBarPadding(horizontal: CGFloat = 12, vertical: CGFloat = 8) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
    }
}

// MARK: - Environment Extensions

struct SearchBarFocusKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var searchBarFocus: Binding<Bool> {
        get { self[SearchBarFocusKey.self] }
        set { self[SearchBarFocusKey.self] = newValue }
    }
}
