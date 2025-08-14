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
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.automatic)
                .padding(8)
            
            // Custom placeholder overlay
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .padding(.leading, 12) // Slight right offset to match TextEditor text position
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
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
