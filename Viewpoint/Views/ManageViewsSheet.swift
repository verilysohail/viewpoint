import SwiftUI

struct ManageViewsSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var viewsManager: ViewsManager

    @State private var editingViewID: UUID?
    @State private var editedName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Views")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(viewsManager.savedViews.count) of 20 views")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Views list
            if viewsManager.savedViews.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No saved views")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Save your current filters as a view to access them quickly later")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(60)
            } else {
                List {
                    ForEach(viewsManager.savedViews) { view in
                        ViewRow(
                            view: view,
                            isEditing: editingViewID == view.id,
                            editedName: $editedName,
                            onStartEdit: {
                                editingViewID = view.id
                                editedName = view.name
                            },
                            onSaveEdit: {
                                if !editedName.trimmingCharacters(in: .whitespaces).isEmpty {
                                    viewsManager.updateView(id: view.id, name: editedName.trimmingCharacters(in: .whitespaces))
                                }
                                editingViewID = nil
                            },
                            onCancelEdit: {
                                editingViewID = nil
                            },
                            onDelete: {
                                viewsManager.deleteView(id: view.id)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct ViewRow: View {
    let view: SavedView
    let isEditing: Bool
    @Binding var editedName: String
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .foregroundColor(.blue)
                .font(.system(size: 16))

            if isEditing {
                TextField("View name", text: $editedName)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    onSaveEdit()
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    onCancelEdit()
                }
                .buttonStyle(.bordered)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(view.name)
                        .font(.system(size: 14, weight: .medium))

                    Text(formatViewSummary(view))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onStartEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Rename view")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete view")
            }
        }
        .padding(.vertical, 4)
    }

    private func formatViewSummary(_ view: SavedView) -> String {
        var parts: [String] = []

        if !view.filters.projects.isEmpty {
            parts.append("\(view.filters.projects.count) project\(view.filters.projects.count == 1 ? "" : "s")")
        }
        if !view.filters.statuses.isEmpty {
            parts.append("\(view.filters.statuses.count) status\(view.filters.statuses.count == 1 ? "" : "es")")
        }
        if !view.filters.assignees.isEmpty {
            parts.append("\(view.filters.assignees.count) assignee\(view.filters.assignees.count == 1 ? "" : "s")")
        }
        if view.filters.showOnlyMyIssues {
            parts.append("my issues")
        }
        if !view.filters.sprints.isEmpty {
            parts.append("\(view.filters.sprints.count) sprint\(view.filters.sprints.count == 1 ? "" : "s")")
        }

        return parts.isEmpty ? "No filters" : parts.joined(separator: ", ")
    }
}
