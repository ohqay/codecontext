import SwiftUI

/// Native-styled text editor for user instructions
struct UserInstructionsEditor: View {
    @Binding var text: String
    let placeholder: String
    
    init(
        text: Binding<String>, 
        placeholder: String = "Enter your instructions or prompt here..."
    ) {
        self._text = text
        self.placeholder = placeholder
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
            
            // Placeholder text when empty
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
                    .padding(.top, 16)
                    .padding(.leading, 12)
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