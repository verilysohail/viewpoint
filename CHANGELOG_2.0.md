# Viewpoint 2.0 - Release Notes

**Build:** 20251203
**Release Date:** December 3, 2025

---

## 🎉 What's New in Version 2.0

Version 2.0 represents a major evolution of Viewpoint, transforming it from a simple Jira viewer into a powerful, AI-enhanced productivity tool. This release brings over 50 improvements across UI, UX, AI capabilities, and workflow efficiency.

---

## ✨ Major Features

### 🚀 Menu Bar Quick Create
Create Jira issues instantly from anywhere on your Mac without opening the main app!

- **Menu bar icon** - Colorful plus icon always available in your menu bar
- **Quick create panel** - Lightweight panel for instant issue creation
- **Keyboard shortcuts** - Press Enter to create, ESC to cancel
- **Smart defaults** - Uses your default project, assignee, epic, and component settings
- **Background operation** - App continues running in background when windows are closed
- **Success confirmation** - Shows created issue key (e.g., "Issue created: SETI-123")
- **Right-click menu** - Quick access to main window, settings, and quit
- **Toggle in Settings** - Enable/disable via Settings → General tab

### 🎨 Saved Views
Save and restore your favorite filter configurations with named views!

- Save current filter settings as named views (up to 20)
- Quick access via Views menu in main toolbar
- Manage views: rename and delete
- Auto-tracking of currently active view
- Manual filter changes clear current view to prevent confusion

### 🎯 Multi-Select & Bulk Operations
Work with multiple issues simultaneously using natural language!

- **Multi-select** - Cmd+Click or Shift+Click to select multiple issues
- **Bulk actions via Indigo** - "log 30 minutes to each", "close these as done"
- **Sliding drawer** - Shows all selected issues with details in Indigo
- **Auto-sync** - Selected issues automatically sync to AI assistant

### 📋 Native Issue Detail Windows
Beautiful Mac-native detail view with comprehensive issue information!

- **Ask Indigo** - "show me details for PROJ-123" opens detail window
- **Three tabs:**
  - **Details** - Description, time tracking, components, metadata
  - **Comments** - All comments with authors and timestamps
  - **History** - Complete changelog with field changes
- **Multiple windows** - Open multiple detail windows simultaneously
- **Auto-refresh** - Automatically updates after making changes
- **Quick browser access** - "Open in Jira" button
- **Two-column layout** - Editable fields with inline editing
- **Proper formatting** - Color-coded dates, times, and status

### 🤖 Indigo AI Assistant
Your intelligent Jira assistant with comprehensive natural language control!

- **Voice transcription** - Speak your commands naturally
- **Comprehensive operations** - Create, update, delete, transition, comment, log work
- **Smart field resolution** - Understands epic names, sprint names, component names
- **Status transitions** - "mark as done", "move to in progress" with fuzzy matching
- **Bulk operations** - Work with multiple issues at once
- **Issue details** - Fetch and display complete issue information
- **Changelog access** - "get me the changelog for PROJ-123"
- **Model selection** - Choose between different AI models
- **Enhanced context** - Longer conversation memory (65K tokens)

### 🔍 JQL Query Builder
Build powerful queries with intelligent autocomplete - no JQL knowledge required!

- **Smart autocomplete** - Type "pro" → suggests "project", space → shows operators
- **Arrow key navigation** - Navigate suggestions like a pro
- **Color-coded** - Visual hints help understand query structure
- **Seamless AI integration** - See and edit exact queries Indigo creates
- **Click activation** - Click anywhere to start building
- **Real-time validation** - Catches errors as you type

---

## 🎨 UI/UX Improvements

### Enhanced Issue Detail View
- **Redesigned layout** - Beautiful two-column design with better information hierarchy
- **Editable fields** - Click to edit sprint, epic, estimate, time remaining
- **Sprint selector** - Dropdown with project-specific sprints
- **Epic selector** - Searchable popover picker with epic summaries
- **Estimate editing** - Direct input for time estimates (e.g., "2h", "1d 4h")
- **Time logging** - Quick time entry with smart parsing

### Improved Filter Panel
- **Epic multi-select** - Select multiple epics simultaneously
- **Epic search field** - Search by epic key or summary
- **Enhanced epic display** - Shows epic summary + key for better identification
- **Project-scoped sprints** - Sprints filter based on selected projects
- **Search fields** - Quick search in Epic and Assignee filters (5+ items)
- **Persistent options** - All previously seen options remain visible
- **Smart clearing** - Sprint selection clears when projects change

### Visual Polish
- **Thicker dividers** - 10-point dark gray dividers for better visibility
- **Better contrast** - Improved readability in both light and dark mode
- **Cleaner layout** - Better spacing and alignment throughout
- **Window persistence** - Windows stay visible when switching apps

---

## ⚡ Performance & Technical

### Faster Startup
- **Instant loading** - App loads immediately, fetches data on demand
- **Smart caching** - Project sprints cached per project key
- **Parallel fetching** - Projects, sprints, and user info load concurrently
- **Configurable batch size** - Choose initial load count in Performance settings

### API Improvements
- **Modern API** - Migrated to Jira REST API v3 with proper pagination
- **Token-based pagination** - Uses nextPageToken for reliable paging
- **Smart loading** - "Load more" button appears when additional issues available
- **Optimistic updates** - UI updates immediately, syncs in background
- **Better error handling** - Comprehensive logging and error messages

### Data Management
- **Epic summaries** - Persistent storage, merged instead of replaced
- **Sprint caching** - Per-project sprint caching with on-demand fetching
- **Filter persistence** - Saved views instead of auto-restore
- **Log rotation** - Automatic log file management (10MB max, 5 archives)

---

## 🐛 Bug Fixes

### Critical Fixes
- **Date parsing** - Proper ISO8601 formatting with fractional seconds
- **HTTP 410 errors** - Fixed deprecated API endpoint usage
- **Component handling** - Defaults to empty array when missing from API
- **Sprint filtering** - Correctly filters by project-specific sprints
- **Epic persistence** - Epic names and summaries persist after filtering
- **Multi-select filters** - All options remain visible during selection
- **Window disappearing** - Windows stay visible when switching apps
- **Sequential AI execution** - Fixed race conditions in bulk operations

### UX Fixes
- **Double-click behavior** - Opens detail window instead of browser
- **Filter confusion** - Manual changes clear current view
- **Sprint auto-clear** - Selections clear when projects change
- **"Show Only My Issues"** - Checkbox now persists correctly
- **Epic dropdown** - Fixed to show epic names properly
- **Swift 6 concurrency** - Replaced semaphores with async/await
- **Toolbar crash** - Moved create popover to sheet

---

## 🔧 Settings & Configuration

### New Settings Tabs
- **General** - Menu bar icon toggle, app behavior
- **Connection** - Jira URL, email, API credentials
- **Performance** - Initial load count configuration
- **Defaults** - Default assignee, project, component, epic for quick create
- **Logs** - View application logs

### Enhanced Defaults
- **Quick create defaults** - Configure default values for menu bar quick create
- **Smart component lookup** - Automatically finds "Management Tasks" when unspecified
- **Current sprint resolution** - "current" automatically finds active sprint
- **Account ID caching** - Faster assignee resolution

---

## 📊 What's Changed Since 1.x

**From Version 1.11:**
- Added Indigo AI assistant (completely new)
- Added JQL query builder with autocomplete
- Added saved views for filter management
- Added multi-select and bulk operations
- Added native issue detail windows
- Added menu bar quick create
- Removed automatic filter persistence on startup
- Migrated to Jira REST API v3
- Complete UI redesign of issue details
- Enhanced epic and sprint filtering
- Date-based build numbering (YYYYMMDD format)

---

## 🎯 Migration Notes

### From Version 1.x
- **No breaking changes** - All your settings and credentials carry over
- **Filter behavior** - Filters no longer auto-restore on startup (use Saved Views instead)
- **Performance** - Default initial load reduced to 100 issues (configurable)
- **Keyboard shortcuts** - CMD+TAB now keeps windows visible (fixed)

---

## 🙏 Thank You

Version 2.0 represents months of development and refinement based on real-world usage. Thank you for your continued support and feedback!

---

## 📝 Version Information

- **Version:** 2.0
- **Build:** 20251203 (December 3, 2025)
- **Minimum macOS:** 13.0 (Ventura)
- **Bundle ID:** com.smamdani.Viewpoint

---

*For detailed technical changes, see the full CHANGELOG.md*
