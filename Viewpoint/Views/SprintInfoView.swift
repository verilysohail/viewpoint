import SwiftUI

struct SprintInfoView: View {
    @EnvironmentObject var jiraService: JiraService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundColor(.accentColor)
                Text("Sprint Info")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                if let sprintInfo = jiraService.currentSprintInfo {
                    VStack(alignment: .leading, spacing: 16) {
                        // Sprint details
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sprintInfo.sprint.name)
                                .font(.title3)
                                .fontWeight(.semibold)

                            HStack {
                                Image(systemName: "circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(sprintStateColor(sprintInfo.sprint.state))
                                Text(sprintInfo.sprint.state.capitalized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            if let goal = sprintInfo.sprint.goal, !goal.isEmpty {
                                Text(goal)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)

                        // Dates
                        if let startDate = sprintInfo.sprint.startDate,
                           let endDate = sprintInfo.sprint.endDate {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "calendar")
                                        .foregroundColor(.accentColor)
                                    Text("Timeline")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Start:")
                                            .foregroundColor(.secondary)
                                        Text(formatDate(startDate))
                                    }
                                    .font(.caption)

                                    HStack {
                                        Text("End:")
                                            .foregroundColor(.secondary)
                                        Text(formatDate(endDate))
                                    }
                                    .font(.caption)
                                }
                                .padding(.leading, 24)
                            }
                        }

                        Divider()

                        // Progress overview
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "chart.bar")
                                    .foregroundColor(.accentColor)
                                Text("Progress")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            // Total issues
                            StatRow(
                                label: "Total Issues",
                                value: "\(sprintInfo.totalIssues)",
                                color: .blue
                            )

                            // Completed
                            StatRow(
                                label: "Completed",
                                value: "\(sprintInfo.completedIssues)",
                                color: .green,
                                percentage: percentage(sprintInfo.completedIssues, of: sprintInfo.totalIssues)
                            )

                            // In Progress
                            StatRow(
                                label: "In Progress",
                                value: "\(sprintInfo.inProgressIssues)",
                                color: .blue,
                                percentage: percentage(sprintInfo.inProgressIssues, of: sprintInfo.totalIssues)
                            )

                            // To Do
                            StatRow(
                                label: "To Do",
                                value: "\(sprintInfo.todoIssues)",
                                color: .gray,
                                percentage: percentage(sprintInfo.todoIssues, of: sprintInfo.totalIssues)
                            )

                            // Progress bar
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Completion")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        // Background
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.2))

                                        // Progress
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.green)
                                            .frame(width: geometry.size.width * completionPercentage(sprintInfo))
                                    }
                                }
                                .frame(height: 8)

                                Text("\(Int(completionPercentage(sprintInfo) * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "flag.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No active sprint")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
        }
    }

    private func sprintStateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "active": return .green
        case "future": return .blue
        case "closed": return .gray
        default: return .gray
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        return dateString
    }

    private func percentage(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }

    private func completionPercentage(_ sprintInfo: SprintInfo) -> Double {
        percentage(sprintInfo.completedIssues, of: sprintInfo.totalIssues)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let color: Color
    var percentage: Double?

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if let percentage = percentage {
                Text("\(Int(percentage * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 4)
            }

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
