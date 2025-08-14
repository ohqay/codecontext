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
        TextField(
            "Instructions",
            text: $text,
            prompt: Text(placeholder),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .lineLimit(5 ... 20)
        .scrollIndicators(.automatic)
        .padding(8)
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
