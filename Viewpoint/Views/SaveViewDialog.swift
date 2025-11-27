import SwiftUI

struct SaveViewDialog: View {
    @Binding var viewName: String
    @Binding var isPresented: Bool
    let onSave: (String) -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Save Current View")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Save your current filter settings as a named view for quick access later.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("View Name")
                    .font(.headline)

                TextField("e.g., My Sprint Issues", text: $viewName)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save View") {
                    saveView()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 250)
    }

    private func saveView() {
        let trimmedName = viewName.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a view name"
            return
        }

        errorMessage = nil
        onSave(trimmedName)
    }
}
