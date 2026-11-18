import SwiftUI

struct SecretField: View {
    let title: String
    let subtitle: String?
    let isSaved: Bool
    let onCommit: (String) -> Void
    let onRemove: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
            HStack {
                SecureField(title, text: $draft, prompt: Text(isSaved ? "Saved in Keychain" : "Not set"))
                    .labelsHidden()
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                if isSaved {
                    Button("Remove", action: onRemove)
                }
            }
        } label: {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
    }

    private func commit() {
        guard !draft.isEmpty else { return }
        let value = draft
        draft = ""
        onCommit(value)
    }
}
