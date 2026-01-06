# Viewpoint

A lightweight macOS app that provides an instant view into Jira with native macOS controls.

## Features

- **Real-time Jira Integration**: Direct API integration with your Jira instance
- **Comprehensive Filtering**: Filter issues by:
  - Status
  - Sprint
  - Assignee
  - Issue Type
  - Project
  - Epic
  - Time Period
- **Sprint Information**: View active sprint details, progress, and statistics
- **Native macOS UI**: Built with SwiftUI for a fast, native experience
- **Instant Refresh**: Quick manual refresh with ⌘R

## Setup

### Prerequisites

- macOS 13.0 or later
- Xcode 15.0 or later
- Jira account with API access

### Configuration

1. Ensure your `.env` file exists in the project root with the following variables:

```env
JIRA_API_KEY = "your-api-key"
JIRA_BASE_URL = "https://your-instance.atlassian.net"
JIRA_EMAIL = "your-email@company.com"
```

2. To generate a Jira API key:
   - Go to https://id.atlassian.com/manage-profile/security/api-tokens
   - Click "Create API token"
   - Give it a name and copy the token to your `.env` file

### Building and Running

#### Xcode (Recommended)

1. Open the project in Xcode:
   ```bash
   open Viewpoint.xcodeproj
   ```

2. The project should open in Xcode with all source files properly organized

3. Select the "Viewpoint" scheme at the top (next to the play/stop buttons)

4. Press ⌘R or click the Play button to build and run

#### Command Line (Alternative - Swift Package)

You can also use the Swift Package for command-line building:
```bash
swift build
swift run Viewpoint
```

Note: The Xcode project provides better integration for macOS app development, including proper app bundling, signing, and debugging.

## Project Structure

```
Viewpoint/
├── ViewpointApp.swift       # App entry point
├── Models/
│   └── JiraModels.swift     # Data models for Jira objects
├── Services/
│   └── JiraService.swift    # Jira API client
├── Views/
│   ├── ContentView.swift    # Main window view
│   ├── FilterPanel.swift    # Filter controls
│   └── SprintInfoView.swift # Sprint information sidebar
└── Config/
    └── Configuration.swift  # Environment configuration
```

## Usage

### Filters

Use the filter panel at the top of the window to:
- Select specific statuses, assignees, issue types, projects, or epics
- Choose sprints to view
- Set date ranges for issue creation
- Apply multiple filters simultaneously

### Sprint Information

The right sidebar shows information about the active sprint:
- Sprint name and status
- Timeline (start/end dates)
- Progress breakdown (To Do, In Progress, Done)
- Completion percentage

### Keyboard Shortcuts

- ⌘R: Refresh data from Jira

## Troubleshooting

### "Failed to fetch issues" error

- Verify your `.env` file has correct credentials
- Check that your API token is valid
- Ensure your Jira instance URL is correct

### No issues showing up

- Check your filter settings - you may have filters that exclude all issues
- Verify you have issues assigned to you in Jira

### Sprint information not loading

- Ensure you have access to at least one Jira board
- Check that there is an active sprint

## License

This project is for personal use.
