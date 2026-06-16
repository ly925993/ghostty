import SwiftUI

struct SSHConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: SSHConnectionsViewModel
    @State var draft: SSHConnectionsViewModel.ConnectionDraft
    @State private var isPrivateKeySelectionPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.connectionID == nil ? "添加服务器" : "编辑服务器")
                .font(.headline)

            Form {
                field("名称", text: $draft.name, error: viewModel.connectionValidationErrors[.name])
                field("主机", text: $draft.host, error: viewModel.connectionValidationErrors[.host])
                field("端口", text: $draft.port, error: viewModel.connectionValidationErrors[.port])
                field("用户名", text: $draft.username)

                Picker("分组", selection: $draft.groupID) {
                    Text("未分组").tag(UUID?.none)
                    ForEach(viewModel.library.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }

                privateKeyField

                VStack(alignment: .leading, spacing: 4) {
                    Text("备注")
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
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    if viewModel.saveConnection(draft) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .sheet(isPresented: $isPrivateKeySelectionPresented) {
            SSHPrivateKeySelectionView(selectedPath: $draft.privateKeyPath)
        }
    }

    private var privateKeyField: some View {
        HStack(spacing: 8) {
            Text("用户密钥")
            TextField("", text: $draft.privateKeyPath)
            Button("浏览...") {
                isPrivateKeySelectionPresented = true
            }
        }
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
