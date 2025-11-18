# Quick Start Guide

## Running the App

### Xcode (Recommended)

1. Open the project in Xcode:
   ```bash
   open Viewpoint.xcodeproj
   ```

2. Wait for Xcode to load (should only take a few seconds)

3. The project structure in the left sidebar should show:
   - Viewpoint (folder)
     - ViewpointApp.swift
     - ContentView.swift
     - Models/
     - Services/
     - Views/
     - Config/
     - Info.plist
     - Viewpoint.entitlements

4. At the top of Xcode, ensure "Viewpoint" scheme is selected and "My Mac" is the destination

5. Press ⌘R or click the Play button to build and run

6. First time running: You may need to select a development team in the Signing & Capabilities tab

### Command Line (Alternative)

You can also build using Swift Package Manager:
```bash
swift build
swift run Viewpoint
```

Note: The Xcode project provides the full macOS app experience with proper bundling and signing.

## First Time Setup

When you first run the app:

1. The app will automatically load your Jira credentials from the `.env` file
2. It will fetch your assigned issues and active sprint information
3. All available filters will be populated based on your issues

## Using the App

### Viewing Issues

- Issues are displayed in the main list
- Each issue shows:
  - Issue key (e.g., PROJ-123)
  - Issue type and status
  - Summary/title
  - Project, assignee, and epic (if applicable)
  - Last updated time

### Filtering

The filter panel at the top allows you to:

1. **Status**: Select which statuses to show (To Do, In Progress, Done, etc.)
2. **Sprint**: Choose which sprints to view
3. **Assignee**: Filter by specific team members
4. **Issue Type**: Show only Stories, Bugs, Tasks, etc.
5. **Project**: Filter by project
6. **Epic**: View issues from specific epics
7. **Time Period**: Set date ranges for issue creation

Filters are applied automatically when you check/uncheck options.

### Sprint Information

The right sidebar shows:
- Active sprint name and status
- Sprint goal
- Timeline (start and end dates)
- Progress breakdown:
  - Total issues
  - Completed, In Progress, and To Do counts
  - Completion percentage with visual progress bar

### Keyboard Shortcuts

- **⌘R**: Refresh data from Jira

## Troubleshooting

### App won't start

Make sure your `.env` file is in the project root directory (same level as Package.swift).

### No issues appear

1. Check that you have issues assigned to you in Jira
2. Verify your filters - you may have excluded all issues
3. Click the Refresh button (⌘R) to reload data

### "Failed to fetch issues" error

1. Verify your Jira credentials in `.env` are correct
2. Check that your API token hasn't expired
3. Ensure your Jira instance URL is correct (should include https://)

### Sprint info not loading

This is normal if:
- You don't have access to any boards
- There are no active sprints
- Your projects don't use sprints

## Next Steps

- Customize the filters to match your workflow
- Keep the app running in the background for quick Jira access
- Use ⌘R frequently to stay updated with the latest changes
