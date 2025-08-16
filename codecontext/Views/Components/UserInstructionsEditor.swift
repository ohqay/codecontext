import SwiftUI

/// Native-styled text editor for user instructions using native SwiftUI placeholder support
struct UserInstructionsEditor: View {
    @Binding var text: String
    let placeholder: String

    init(
        text: Binding<String>,
        placeholder: String = "Enter your instructions or prompt here..."
    ) {
        _text = text
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            EditableTextView(text: $text)

            // Custom placeholder text overlay
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .padding(.leading, 12) // Slight right offset to match text position (12px + 4px)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
            }
        }
    }
}

// MARK: - Preview Support

#if DEBUG
    #Preview {
        @Previewable @State var text = ""
        return VStack {
            UserInstructionsEditor(text: $text)
                .frame(height: 120)
                .background(.background)
                .cornerRadius(8)
                .padding()
        }
    }
#endif
