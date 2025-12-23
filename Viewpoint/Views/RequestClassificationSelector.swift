import SwiftUI

/// A selector component for the Request Classification cascading select field
struct RequestClassificationSelector: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.refreshIssueDetails) var refreshIssueDetails

    @State private var showingPopover = false
    @State private var options: [CascadingSelectOption] = []
    @State private var isLoading = false
    @State private var isUpdating = false

    @State private var selectedParent: String?
    @State private var selectedChild: String?

    private var currentValue: String {
        if let classification = issue.requestClassification {
            if let child = classification.child {
                return "\(classification.value) → \(child.value)"
            }
            return classification.value
        }
        return "None"
    }

    private var isSet: Bool {
        issue.requestClassification != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Request Classification")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Button(action: { showingPopover = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12))
                    Text(currentValue)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    if isUpdating {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(isSet ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Click to change Request Classification")
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                classificationPopover
            }
        }
        .onAppear {
            // Initialize selected values from current issue
            if let classification = issue.requestClassification {
                selectedParent = classification.value
                selectedChild = classification.child?.value
            }
        }
    }

    private var classificationPopover: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Request Classification")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if isLoading && options.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading options...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    Spacer()
                }
                .frame(height: 150)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    // Parent options column
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Category")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)

                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                // Clear option
                                Button(action: {
                                    selectedParent = nil
                                    selectedChild = nil
                                    saveSelection()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 11))
                                        Text("None")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if !isSet && selectedParent == nil {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10))
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(!isSet && selectedParent == nil ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Divider()

                                ForEach(options) { option in
                                    Button(action: {
                                        selectedParent = option.value
                                        // If no children, auto-save. Otherwise clear child selection
                                        if option.children == nil || option.children?.isEmpty == true {
                                            selectedChild = nil
                                            saveSelection()
                                        } else {
                                            selectedChild = nil
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Text(option.value)
                                                .font(.system(size: 12))
                                                .foregroundColor(.primary)
                                            Spacer()
                                            if selectedParent == option.value {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.accentColor)
                                            }
                                            if option.children != nil && !(option.children?.isEmpty ?? true) {
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedParent == option.value ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(width: 180)

                    Divider()

                    // Child options column
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Sub-category")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)

                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if let parent = selectedParent,
                                   let parentOption = options.first(where: { $0.value == parent }),
                                   let children = parentOption.children, !children.isEmpty {

                                    // None option for child
                                    Button(action: {
                                        selectedChild = nil
                                        saveSelection()
                                    }) {
                                        HStack(spacing: 6) {
                                            Text("(No sub-category)")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .italic()
                                            Spacer()
                                            if selectedChild == nil {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedChild == nil ? Color.accentColor.opacity(0.1) : Color.clear)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Divider()

                                    ForEach(children) { child in
                                        Button(action: {
                                            selectedChild = child.value
                                            saveSelection()
                                        }) {
                                            HStack(spacing: 6) {
                                                Text(child.value)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                if selectedChild == child.value {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.accentColor)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(selectedChild == child.value ? Color.accentColor.opacity(0.1) : Color.clear)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } else {
                                    Text("Select a category first")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .italic()
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                    }
                    .frame(width: 220)
                }
                .frame(height: 250)
            }
        }
        .frame(width: 402)
        .onAppear {
            loadOptions()
        }
    }

    private func loadOptions() {
        guard options.isEmpty else { return }
        isLoading = true

        Task {
            let fetchedOptions = await jiraService.fetchRequestClassificationOptions()
            await MainActor.run {
                options = fetchedOptions
                isLoading = false
            }
        }
    }

    private func saveSelection() {
        showingPopover = false
        isUpdating = true

        Task {
            let success = await jiraService.updateRequestClassification(
                issueKey: issue.key,
                parentValue: selectedParent,
                childValue: selectedChild
            )

            await MainActor.run {
                isUpdating = false
                if success {
                    Logger.shared.info("Updated Request Classification for \(issue.key)")
                    Task {
                        await jiraService.fetchMyIssues()
                    }
                    refreshIssueDetails()
                } else {
                    Logger.shared.error("Failed to update Request Classification for \(issue.key)")
                }
            }
        }
    }
}
