import SwiftUI
import OddFrogCore

struct LinkManagerView: View {
    @Bindable var model: LinkManagerModel
    @FocusState private var nameFocused: Bool
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Table(model.links, selection: Binding(
                        get: { model.selection },
                        set: { model.select($0) }
                    )) {
                        TableColumn("Name") { link in
                            Text(link.name).help(link.name)
                        }
                        TableColumn("URL") { link in
                            let address = LinkManagerModel.address(of: link)
                            Text(address).truncationMode(.middle).help(address)
                        }
                        TableColumn("Aliases") { link in
                            let value = link.aliases.joined(separator: ", ")
                            Text(value).help(value)
                        }
                    }
                    .frame(height: 120)
                } header: {
                    Text("Links")
                } footer: {
                    Text(verbatim: "Web links open in your default browser. App links open in the app registered for that URL. Put {query} in a URL to insert what you type after the alias, for example gh odd-frog.")
                }

                Section {
                    TextField("Name", text: $model.name, prompt: Text("GitHub"))
                        .focused($nameFocused)
                    TextField("URL", text: $model.url, prompt: Text(verbatim: "https://github.com or obsidian://open"))
                    TextField("Aliases (comma separated)", text: $model.aliases, prompt: Text("gh, github"))
                } header: {
                    Text(model.original == nil ? "New link" : "Edit link")
                } footer: {
                    if let error = model.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("New Link") {
                    model.newLink()
                    nameFocused = true
                }
                Button("Delete", role: .destructive) {
                    confirmingDelete = true
                }
                .disabled(model.original == nil)
                Spacer()
                Button("Done") { model.onDone?() }
                    .keyboardShortcut(.cancelAction)
                Button(model.original == nil ? "Add Link" : "Save Changes") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .defaultFocus($nameFocused, true)
        .alert("Delete “\(model.original?.name ?? "")”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                model.delete()
                nameFocused = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the link and its aliases from the launcher.")
        }
    }
}
