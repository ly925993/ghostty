import SwiftUI

struct SSHConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: SSHConnectionsViewModel
    @State var draft: SSHConnectionsViewModel.ConnectionDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.connectionID == nil ? "Add Server" : "Edit Server")
                .font(.headline)

            Form {
                field("Name", text: $draft.name, error: viewModel.connectionValidationErrors[.name])
                field("Host", text: $draft.host, error: viewModel.connectionValidationErrors[.host])
                field("Port", text: $draft.port, error: viewModel.connectionValidationErrors[.port])
                field("Username", text: $draft.username)

                Picker("Group", selection: $draft.groupID) {
                    Text("Ungrouped").tag(UUID?.none)
                    ForEach(viewModel.library.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }

                field("Private Key", text: $draft.privateKeyPath)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .frame(minHeight: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if viewModel.saveConnection(draft) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        error: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: text)
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}
