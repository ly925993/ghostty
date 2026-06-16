import SwiftUI

struct SSHGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: SSHConnectionsViewModel
    @State var draft: SSHConnectionsViewModel.GroupDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.groupID == nil ? "添加分组" : "编辑分组")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                TextField("分组名称", text: $draft.name)
                if let error = viewModel.groupValidationError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    if viewModel.saveGroup(draft) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
