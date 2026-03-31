import SwiftUI

struct IndigoSettingsTab: View {
    @State private var selectedSection = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSection) {
                Text("Workflow Patterns").tag(0)
                Text("Tools Reference").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            if selectedSection == 0 {
                WorkflowPatternsSection()
            } else {
                ToolsReferenceSection()
            }
        }
    }
}

// MARK: - Workflow Patterns Section

struct WorkflowPatternsSection: View {
    @EnvironmentObject var patternsManager: WorkflowPatternsManager
    @State private var selectedPatternId: UUID?
    @State private var isEditing = false
    @State private var isCreating = false
    @State private var editName = ""
    @State private var editTrigger = ""
    @State private var editKnowledge = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        HSplitView {
            // Pattern list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedPatternId) {
                    ForEach(patternsManager.patterns) { pattern in
                        PatternRow(pattern: pattern, onToggle: {
                            patternsManager.togglePattern(id: pattern.id)
                        })
                        .tag(pattern.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack {
                    Button(action: startCreating) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)

                    if let patternId = selectedPatternId,
                       let pattern = patternsManager.patterns.first(where: { $0.id == patternId }) {
                        if pattern.isBuiltIn {
                            Button(action: { patternsManager.resetPattern(id: patternId) }) {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Reset to default")
                        } else {
                            Button(action: { showDeleteConfirmation = true }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                    }

                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 200, idealWidth: 220)

            // Detail/edit area
            VStack {
                if isCreating || isEditing {
                    patternEditor
                } else if let patternId = selectedPatternId,
                          let pattern = patternsManager.patterns.first(where: { $0.id == patternId }) {
                    patternDetail(pattern)
                } else {
                    emptyState
                }
            }
            .frame(minWidth: 300)
        }
        .confirmationDialog("Delete Pattern", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let id = selectedPatternId {
                    patternsManager.deletePattern(id: id)
                    selectedPatternId = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this workflow pattern?")
        }
        .onChange(of: selectedPatternId) { _ in
            isCreating = false
            isEditing = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Select a pattern or create a new one")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func patternDetail(_ pattern: WorkflowPattern) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(pattern.name)
                        .font(.headline)
                    if pattern.isBuiltIn {
                        Text("Built-in")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                    Spacer()
                    if pattern.isBuiltIn {
                        Button("Reset") {
                            patternsManager.resetPattern(id: pattern.id)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Edit") {
                        editName = pattern.name
                        editTrigger = pattern.trigger
                        editKnowledge = pattern.knowledge
                        isEditing = true
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("When")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Text(pattern.trigger)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Instructions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Text(pattern.knowledge)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack(spacing: 16) {
                    Text("Created: \(pattern.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Modified: \(pattern.lastModified.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private var patternEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isCreating ? "New Pattern" : "Edit Pattern")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline)
                TextField("e.g., Cancel Issue", text: $editName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("When to apply")
                    .font(.subheadline)
                TextField("e.g., When the user asks to cancel or void an issue", text: $editTrigger)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions")
                    .font(.subheadline)
                TextEditor(text: $editKnowledge)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isCreating = false
                    isEditing = false
                }
                .buttonStyle(.bordered)

                Button(isCreating ? "Create" : "Save") {
                    savePattern()
                }
                .buttonStyle(.borderedProminent)
                .disabled(editName.isEmpty || editTrigger.isEmpty || editKnowledge.isEmpty)
            }
        }
        .padding()
    }

    private func startCreating() {
        editName = ""
        editTrigger = ""
        editKnowledge = ""
        selectedPatternId = nil
        isCreating = true
        isEditing = false
    }

    private func savePattern() {
        if isCreating {
            patternsManager.addPattern(name: editName, trigger: editTrigger, knowledge: editKnowledge)
        } else if let id = selectedPatternId {
            let currentPattern = patternsManager.patterns.first { $0.id == id }
            patternsManager.updatePattern(
                id: id,
                name: editName,
                trigger: editTrigger,
                knowledge: editKnowledge,
                isEnabled: currentPattern?.isEnabled ?? true
            )
        }
        isCreating = false
        isEditing = false
    }
}

// MARK: - Pattern Row

struct PatternRow: View {
    let pattern: WorkflowPattern
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(pattern.name)
                    .font(.system(size: 13, weight: .medium))
                Text(pattern.trigger)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { pattern.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tools Reference Section

struct ToolsReferenceSection: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(capabilityData, id: \.name) { capability in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(capability.tools, id: \.name) { tool in
                                ToolReferenceRow(tool: tool)
                            }
                        }
                        .padding(.leading, 8)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "cube.box")
                                .foregroundColor(Color(red: 0.46, green: 0.39, blue: 1.0))
                            Text(capability.name)
                                .font(.headline)
                            Text("(\(capability.tools.count) tools)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var capabilityData: [CapabilityInfo] {
        // Read from CapabilityRegistry on MainActor
        let capabilities = CapabilityRegistry.shared.capabilities
        return capabilities.map { capability in
            CapabilityInfo(
                name: capability.name,
                description: capability.description,
                tools: capability.tools.map { tool in
                    ToolInfo(
                        name: tool.name,
                        description: tool.description,
                        parameters: tool.parameters.map { param in
                            ToolParamInfo(
                                name: param.name,
                                type: param.type.jsonSchemaType,
                                description: param.description,
                                required: param.required
                            )
                        }
                    )
                }
            )
        }
    }
}

// MARK: - Tool Reference Row

struct ToolReferenceRow: View {
    let tool: ToolInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tool.name)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Text(tool.description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if !tool.parameters.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(tool.parameters, id: \.name) { param in
                        HStack(alignment: .top, spacing: 6) {
                            Text(param.name)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(minWidth: 80, alignment: .trailing)
                            Text(param.type)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.blue)
                                .frame(width: 50)
                            Text(param.required ? "req" : "opt")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(param.required ? .orange : .secondary)
                                .frame(width: 25)
                            Text(param.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - View Data Models

private struct CapabilityInfo {
    let name: String
    let description: String
    let tools: [ToolInfo]
}

struct ToolInfo {
    let name: String
    let description: String
    let parameters: [ToolParamInfo]
}

struct ToolParamInfo {
    let name: String
    let type: String
    let description: String
    let required: Bool
}
