import SwiftUI

struct CommitTextField: View {
    let title: String
    let subtitle: String?
    let prompt: String
    let value: String
    let onCommit: (String) -> Void

    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(
            text: Binding(get: { draft ?? value }, set: { draft = $0 }),
            prompt: Text(verbatim: prompt)
        ) {
            Text(title)
            if let subtitle { Text(subtitle) }
        }
        .focused($focused)
        .onSubmit(commit)
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        guard let draft else { return }
        self.draft = nil
        onCommit(draft)
    }
}
