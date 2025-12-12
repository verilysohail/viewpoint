import SwiftUI

/// A selector component for the PCM Master CMDB field with autocomplete
struct PCMMasterSelector: View {
    let issue: JiraIssue
    @EnvironmentObject var jiraService: JiraService
    @Environment(\.refreshIssueDetails) var refreshIssueDetails

    @State private var showingPopover = false
    @State private var searchText = ""
    @State private var searchResults: [(id: String, label: String, objectKey: String)] = []
    @State private var allPCMEntries: [(id: String, label: String, objectKey: String)] = []
    @State private var isLoading = false
    @State private var isUpdating = false

    private var currentValue: String {
        if let pcm = issue.pcmMaster {
            // Prefer label from API response
            if let label = pcm.label, !label.isEmpty {
                return label
            }
            // Try to find label from cached entries using objectId
            if let cached = allPCMEntries.first(where: { $0.id == pcm.objectId }) {
                return cached.label
            }
            // Still loading - show a placeholder
            if isLoadingLabel {
                return "Loading..."
            }
            return pcm.objectKey ?? "PCM-\(pcm.objectId)"
        }
        return "None"
    }

    private var isSet: Bool {
        issue.pcmMaster != nil
    }

    @State private var isLoadingLabel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PCM Master")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Button(action: { showingPopover = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 12))
                    Text(currentValue)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    if isUpdating || isLoadingLabel {
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
            .help("Click to change PCM Master")
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                pcmSearchPopover
            }
        }
        .onAppear {
            // Pre-load entries so we can look up labels if needed
            if issue.pcmMaster != nil && issue.pcmMaster?.label == nil && allPCMEntries.isEmpty {
                isLoadingLabel = true
                Task {
                    let entries = await jiraService.searchPCMMaster()
                    await MainActor.run {
                        allPCMEntries = entries.sorted { $0.label.lowercased() < $1.label.lowercased() }
                        isLoadingLabel = false
                    }
                }
            }
        }
    }

    private var pcmSearchPopover: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search PCM Master...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        if !filteredResults.isEmpty {
                            selectPCM(filteredResults[0])
                        }
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Results list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Clear option
                    Button(action: {
                        clearPCM()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                            Text("None")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            if !isSet {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(!isSet ? Color.accentColor.opacity(0.1) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()

                    if isLoading && allPCMEntries.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    } else if filteredResults.isEmpty && !searchText.isEmpty {
                        Text("No matches found")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(filteredResults.prefix(50).enumerated()), id: \.element.id) { index, pcm in
                            Button(action: {
                                selectPCM(pcm)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "server.rack")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pcm.label)
                                            .font(.system(size: 12))
                                            .foregroundColor(.primary)
                                        Text(pcm.objectKey)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if issue.pcmMaster?.objectId == pcm.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(issue.pcmMaster?.objectId == pcm.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < filteredResults.prefix(50).count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(width: 300, height: 300)
        }
        .onAppear {
            loadPCMEntries()
        }
    }

    private var filteredResults: [(id: String, label: String, objectKey: String)] {
        if searchText.isEmpty {
            return allPCMEntries
        }
        let query = searchText.lowercased()
        return allPCMEntries.filter {
            $0.label.lowercased().contains(query) ||
            $0.objectKey.lowercased().contains(query)
        }
    }

    private func loadPCMEntries() {
        guard allPCMEntries.isEmpty else { return }
        isLoading = true

        Task {
            let entries = await jiraService.searchPCMMaster()
            await MainActor.run {
                allPCMEntries = entries.sorted { $0.label.lowercased() < $1.label.lowercased() }
                isLoading = false
            }
        }
    }

    private func selectPCM(_ pcm: (id: String, label: String, objectKey: String)) {
        showingPopover = false
        isUpdating = true

        Task {
            let success = await jiraService.updatePCMMaster(issueKey: issue.key, objectId: pcm.id)

            await MainActor.run {
                isUpdating = false
                if success {
                    Logger.shared.info("Updated PCM Master for \(issue.key) to \(pcm.label)")
                    Task {
                        await jiraService.fetchMyIssues()
                    }
                    refreshIssueDetails()
                } else {
                    Logger.shared.error("Failed to update PCM Master for \(issue.key)")
                }
            }
        }
    }

    private func clearPCM() {
        showingPopover = false
        isUpdating = true

        Task {
            let success = await jiraService.updatePCMMaster(issueKey: issue.key, objectId: nil)

            await MainActor.run {
                isUpdating = false
                if success {
                    Logger.shared.info("Cleared PCM Master for \(issue.key)")
                    Task {
                        await jiraService.fetchMyIssues()
                    }
                    refreshIssueDetails()
                } else {
                    Logger.shared.error("Failed to clear PCM Master for \(issue.key)")
                }
            }
        }
    }
}
