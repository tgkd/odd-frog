import SwiftUI
import CoreText
import OddFrogCore

struct AppearancePaneView: View {
    let model: AppearancePaneModel

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { model.appearance.theme }, set: { model.setTheme($0) })) {
                    Text("System").tag(OddFrogCore.Settings.Appearance.Theme.system)
                    Text("Light").tag(OddFrogCore.Settings.Appearance.Theme.light)
                    Text("Dark").tag(OddFrogCore.Settings.Appearance.Theme.dark)
                } label: {
                    Text("Appearance")
                }
            }

            Section {
                Picker(selection: Binding(get: { model.selectedFamily }, set: { model.setFamily($0) })) {
                    Text("System").tag(String?.none)
                    Divider()
                    ForEach(model.families, id: \.self) { family in
                        Text(family).tag(Optional(family))
                    }
                } label: {
                    Text("Font")
                    Text("Used in the launcher, notes and chat.")
                }

                LabeledContent {
                    HStack {
                        Text(sizeText).monospacedDigit()
                        Stepper(
                            value: Binding(get: { model.appearance.fontSize }, set: { model.setSize($0) }),
                            in: OddFrogCore.Settings.Appearance.sizeRange,
                            step: 1
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                } label: {
                    Text("Size")
                }

                Text("Find apps, run commands, take notes.")
                    .font(Font(model.previewFont as CTFont))
            }
        }
        .formStyle(.grouped)
    }

    private var sizeText: String {
        let size = model.appearance.fontSize
        if size == size.rounded() {
            return "\(Int(size)) pt"
        }
        return "\(size) pt"
    }
}
