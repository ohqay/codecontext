import AppKit
import SwiftUI

/// High-performance text view for displaying large amounts of text
/// Uses NSTextView for efficient rendering and scrolling of content that would
/// cause performance issues with SwiftUI's Text view
struct PerformantTextView: NSViewRepresentable {
    let text: String
    let font: NSFont

    init(text: String, font: NSFont = .systemFont(ofSize: 14)) {
        self.text = text
        self.font = font
    }

    func makeNSView(context _: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true

        // Configure text view for optimal performance
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = font
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        // Performance optimizations
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 12, height: 12)

        // Set content
        textView.string = text

        // Set up scroll view
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context _: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text changed to avoid unnecessary redraws
        if textView.string != text {
            textView.string = text
        }
    }
}

// MARK: - Preview Support

#if DEBUG
    #Preview {
        PerformantTextView(text: String(repeating: "This is a test line with some sample content.\n", count: 1000))
            .frame(width: 600, height: 400)
    }
#endif
