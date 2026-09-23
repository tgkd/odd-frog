import SwiftUI
import OddFrogCore
import OddFrogPluginAPI
import UniformTypeIdentifiers

struct PluginsPaneView: View {
    let model: PluginsPaneModel

    @State private var choosingFolders = false
    @State private var folderTarget: (package: PluginPackage, definition: PluginSettingDefinition)?

    var body: some View {
        let bundled = model.packages.filter(\.bundled)
        let installed = model.packages.filter { !$0.bundled }
        Form {
            ForEach(Array(bundled.enumerated()), id: \.element.manifest.id) { index, package in
                section(for: package, header: index == 0 && !installed.isEmpty ? "Bundled" : nil)
            }
            ForEach(Array(installed.enumerated()), id: \.element.manifest.id) { index, package in
                section(for: package, header: index == 0 ? "Installed" : nil)
            }
            if model.packages.isEmpty, model.errors.isEmpty {
                Section {
                    Text("No plugins found. Build the app bundle to include bundled plugins.")
                        .foregroundStyle(.secondary)
                }
            }
            if !model.errors.isEmpty {
                Section {
                    ForEach(Array(model.errors.enumerated()), id: \.offset) { _, error in
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            Section {
                Button("Reload Plugins") { model.onReload?() }
            } footer: {
                Text("Local packages are trusted code. Enable user packages explicitly; changes to a package restart its providers.")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, let target = folderTarget {
                model.addFolders(urls, for: target.definition, in: target.package)
            }
        }
        .fileDialogConfirmationLabel("Add")
    }

    @ViewBuilder
    private func section(for package: PluginPackage, header: String?) -> some View {
        if let header {
            Section {
                rows(for: package)
            } header: {
                Text(header)
            } footer: {
                messageFooter(for: package)
            }
        } else {
            Section {
                rows(for: package)
            } footer: {
                messageFooter(for: package)
            }
        }
    }

    @ViewBuilder
    private func messageFooter(for package: PluginPackage) -> some View {
        if model.message?.package == package.manifest.id, let message = model.message {
            Text(message.text).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func rows(for package: PluginPackage) -> some View {
        let manifest = package.manifest
        let enabled = package.isEnabled(settings: model.settings)
        let failure = model.failures[manifest.id]
        let state = failure ?? (enabled ? "Ready" : "Off")
        let source = package.bundled ? "Bundled" : LauncherItem.abbreviate(package.directory.path)

        Toggle(isOn: Binding(get: { enabled }, set: { model.onToggle?(manifest.id, $0) })) {
            Text(manifest.name)
            Text("\(manifest.version) · \(source) · \(state)")
                .foregroundStyle(failure == nil ? Color.secondary : Color.red)
        }

        if let trigger = manifest.trigger {
            CommitTextField(
                title: trigger.label,
                subtitle: "Type this first in the launcher to use \(manifest.name).",
                prompt: trigger.text,
                value: model.resolvedTrigger(of: package),
                onCommit: { model.commitTrigger($0, for: package) }
            )
        }

        ForEach(manifest.settings, id: \.key) { definition in
            row(for: definition, in: package)
        }

        if enabled, failure == nil, manifest.capabilities.contains("links.manage@1") {
            LabeledContent {
                Button("Manage Links…") { model.onManageLinks?() }
            } label: {
                Text("Links")
                Text("Add, edit and remove URL commands.")
            }
        }
    }

    @ViewBuilder
    private func row(for definition: PluginSettingDefinition, in package: PluginPackage) -> some View {
        let value = model.value(of: definition, in: package)
        switch definition.type {
        case .boolean:
            Toggle(definition.title, isOn: Binding(
                get: { value.bool == true },
                set: { model.commit(.bool($0), for: definition, in: package) }
            ))
        case .choice:
            Picker(definition.title, selection: Binding(
                get: { value.string ?? "" },
                set: { model.commit(.string($0), for: definition, in: package) }
            )) {
                ForEach(definition.choices ?? [], id: \.self) { choice in
                    Text(choice).tag(choice)
                }
            }
        case .string:
            CommitTextField(
                title: definition.title,
                subtitle: nil,
                prompt: definition.defaultValue.string ?? "",
                value: value.string ?? "",
                onCommit: { model.commit(.string($0), for: definition, in: package) }
            )
        case .number:
            CommitTextField(
                title: definition.title,
                subtitle: numberSubtitle(for: definition),
                prompt: definition.defaultValue.number.map(PluginsPaneModel.format) ?? "",
                value: value.number.map(PluginsPaneModel.format) ?? "",
                onCommit: { model.commit(Double($0.trimmingCharacters(in: .whitespaces)).map(JSONValue.number) ?? .null, for: definition, in: package) }
            )
        case .folders:
            foldersRow(for: definition, in: package)
        }
    }

    @ViewBuilder
    private func foldersRow(for definition: PluginSettingDefinition, in package: PluginPackage) -> some View {
        let folders = (model.value(of: definition, in: package).array ?? []).compactMap(\.string)
        LabeledContent {
            HStack {
                Button("Add…") {
                    folderTarget = (package, definition)
                    choosingFolders = true
                }
                Button("Clear") {
                    model.commit(.array([]), for: definition, in: package)
                }
                .disabled(folders.isEmpty)
            }
        } label: {
            Text(definition.title)
            if folders.isEmpty {
                Text("No folders yet.")
            } else {
                Text(folders.map(LauncherItem.abbreviate).joined(separator: "\n"))
            }
        }
    }

    private func numberSubtitle(for definition: PluginSettingDefinition) -> String? {
        guard let minimum = definition.minimum, let maximum = definition.maximum else { return nil }
        return "\(PluginsPaneModel.format(minimum)) – \(PluginsPaneModel.format(maximum))"
    }
}
