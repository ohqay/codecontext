import AppKit
import SwiftUI

/// Editable text view with proper scroll bar auto-hiding behavior
/// Based on PerformantTextView but with editing capabilities and text binding support
struct EditableTextView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    
    init(text: Binding<String>, font: NSFont = .systemFont(ofSize: 14)) {
        self._text = text
        self.font = font
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        // Configure scroll view with proper auto-hiding behavior
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        
        // Configure text view for editing
        textView.isEditable = true
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
        
        // Performance optimizations and styling
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 12, height: 12)
        
        // Set content and delegate
        textView.string = text
        textView.delegate = context.coordinator
        
        // Set up scroll view
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Only update if text changed to avoid unnecessary redraws and cursor jumping
        if textView.string != text {
            textView.string = text
        }
    }
}

// MARK: - Coordinator for Text Binding

extension EditableTextView {
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableTextView
        
        init(_ parent: EditableTextView) {
            self.parent = parent
        }
        
        nonisolated func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            // Update SwiftUI binding on main thread
            Task { @MainActor in
                self.parent.text = textView.string
            }
        }
    }
}

// MARK: - Preview Support

#if DEBUG
    #Preview {
        @Previewable @State var text = "Sample editable text..."
        return VStack {
            EditableTextView(text: $text)
                .frame(height: 120)
                .background(.background)
                .cornerRadius(8)
                .padding()
        }
    }
#endif