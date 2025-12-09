# Changelog

All notable changes to Viewpoint will be documented in this file.

## [2.1] - 2025-12-09

### Added

**📊 Resolution Display in Issue Details**
- Resolution field now displayed in issue detail window header next to Status
- Shows resolution value (Done, Won't Do, Cancelled, etc.) for resolved issues
- Color-coded green for easy identification

### Improved

**🤖 Smarter AI Status Transitions**
- LLM-based semantic field matching for status transitions with resolutions
- Natural language resolution matching - say "cancel this" and AI finds correct resolution value
- No more hardcoded value matching - AI handles spelling variations and synonyms
- Shared validation architecture for both CREATE and UPDATE operations
- More reliable handling of resolution values like "Done", "Won't Do", "Cancelled"

### Fixed

**🪟 Indigo Keep on Top Toggle**
- "Keep on Top" toggle now applies immediately when Indigo window opens
- Previously required toggling off and on to take effect

### Technical Improvements

- Added `resolution` field to Jira API field list for issue fetching
- Added `ResolutionField` decoding to `IssueFields` model
- Refactored field validation to use shared `matchFieldsWithLLM()` function
- Added `validateUpdateFields()` for UPDATE operations using same pattern as CREATE
- Applied `.onAppear` modifier to apply initial window floating state

---

## [2.1] - 2025-12-08

### Added

**💬 @ Mention Autocomplete in Comments**
- Type @ in comment fields to trigger autocomplete with real-time user search
- Shows user display name and email address for disambiguation
- Supports multiple users with same name across different domains
- Keyboard navigation with arrow keys (↑↓), Tab, and Enter to select
- Escape to dismiss autocomplete dropdown
- Mentions convert to proper Jira ADF format with account IDs
- Users mentioned in Jira comments now render correctly as @Username in Viewpoint

**🧵 Threaded Comment Replies**
- Reply directly to specific comments in issue detail view
- Threaded conversation support for better organization
- Comment input now available directly in issue detail Comments tab

### Fixed

**Menu Bar Quick Create**
- Enter key now works correctly in menu bar popover when main window is visible
- Previously, keyboard events were intercepted by main window
- Added custom NSEvent monitoring for reliable keyboard event handling

**Saved Views with JQL Negation**
- Saved views now work correctly with JQL negation operators (!=, NOT IN)
- Views store and execute original JQL instead of parsed filters
- "Load More" uses stored JQL to prevent query reconstruction bugs
- Parser skips status field when using negation operators to avoid conflicts
- Fixed views showing 0 results when using "status != Done" or similar queries

**Comment Mention Stability**
- Fixed crash when inserting mentions (String index out of bounds error)
- Added comprehensive bounds checking for safe string manipulation
- Multi-word names now parse correctly (e.g., "Kevin Zheng" instead of just "Kevin")
- Parser tries up to 5-word combinations for accurate name matching

### Technical Improvements

- Refactored `MenuBarQuickCreateView` to MVVM pattern with dedicated ViewModel
- `MenuBarManager` now inherits from NSObject for proper NSPopoverDelegate conformance
- `SavedView` model stores original JQL queries alongside parsed filters
- Enhanced user search API returns email addresses for disambiguation
- Implemented `KeyInterceptingTextView` for custom keyboard event handling
- Comment parsing uses progressive word matching for multi-word display names
- ADF mention node extraction for proper @ mention rendering from Jira

---

## [2.0.1] - 2025-12-04

### Fixed
- Epic-type issues now filtered out when grouping by Epic to avoid confusion

---

## [2.0] - 2025-12-03

🎉 **Official Release!** Viewpoint 2.0 is now production-ready.

### What's New Since Beta 3

**🚀 Menu Bar Quick Create**
- Menu bar icon for instant issue creation from anywhere
- Quick create panel with keyboard shortcuts (Enter to create, ESC to cancel)
- Smart defaults using configured project, assignee, epic, and component
- Success confirmation showing created issue key
- Right-click menu for quick access to main window, settings, and quit
- Toggle in Settings → General tab
- App runs in background when windows closed

**🎨 Enhanced Epic Filtering**
- Converted to searchable popover-based picker for better UX
- Multi-select support - select multiple epics simultaneously
- Search by epic key or summary
- Epic names and summaries persist after filtering
- Shows epic summary + key for better identification

**📋 Issue Detail Enhancements**
- Automatic refresh after updates (sprint, epic, estimate, time logging)
- No need to close and reopen windows
- Seamless integration with all edit operations

**💅 Visual Polish**
- Thicker split view divider (10 points) in dark gray for better visibility
- Improved contrast and readability
- Better window management - windows stay visible when switching apps
- Professional date-based build numbering (YYYYMMDD format)

### Fixed
- Epic multi-select filter persistence - options no longer vanish after selection
- Epic summaries persistence - names remain visible after filtering
- Window disappearing on app switch with Cmd+Tab
- Filter panel search functionality for epic names and keys

### Technical
- Build number now uses date-based format (20251203) for instant identification
- Removed .accessory activation policy that was hiding windows
- Epic summaries and available epics now merge instead of replace
- Enhanced epic search across all loaded issues

---

## [2.0 Beta 3] - 2025-11-26

### Added
- **🎨 Saved Views** - Save and restore filter configurations with named views
  - Save current filter settings as named views (up to 20 views)
  - Quick access via Views menu in main toolbar
  - Manage views: rename and delete saved views
  - Views automatically track which one is currently active
  - Manual filter changes clear current view to avoid confusion

### Changed
- **Filter Persistence** - Removed automatic filter restoration on app startup
  - Filters no longer automatically restore from previous session
  - Use saved views to preserve and restore filter configurations
  - Fixes confusion when app restarts with unexpected filters applied

### Fixed
- **Double-Click Behavior** - Issue rows now open detail windows instead of browser
  - Double-click on issue row opens Mac-native detail window
  - "Open in Jira" moved to context menu only
  - Multi-select context menu shows "Open All (N)" option

## [2.0 Beta 2] - 2025-11-26

### Added
- **🎯 Multi-Select Issues** - Select multiple issues in the main viewer to perform bulk operations via Indigo
  - Use Cmd+Click or Shift+Click to select multiple issues
  - Selected issues automatically sync to Indigo for bulk actions
  - Sliding drawer in Indigo shows all selected issues with details
  - Natural language bulk commands: "log 30 minutes to each", "close these as done", "add comment to all"

- **📋 Issue Detail Windows** - Mac-native detail view with comprehensive issue information
  - Ask Indigo "show me details for PROJ-123" to open a new detail window
  - Three tabs: Details (description, time tracking, components), Comments (all comments with authors), History (complete changelog)
  - Multiple detail windows can be open simultaneously
  - "Open in Jira" button for quick browser access
  - Properly formatted dates, times, and metadata with color-coding

- **📜 Changelog Support** - Fetch complete change history for any issue
  - Ask Indigo "get me the changelog for PROJ-123"
  - Shows all field changes with timestamps and authors
  - Formatted chronologically with clear before/after values

- **📊 Log Rotation** - Automatic log file management prevents unbounded growth
  - Logs rotate at 10MB with up to 5 archived files kept
  - Maximum disk usage: ~60MB total
  - Automatic cleanup of oldest logs

### Fixed
- **Sprint Filtering** - Sprints now intelligently filter based on selected projects
  - Selecting a project shows only sprints from that project's boards
  - Sprint selections auto-clear when changing projects to avoid confusion

- **Multi-Select Filters** - All filters now support true multi-select
  - Selecting an assignee no longer hides other assignees
  - All filter options remain visible for easy multi-selection
  - Smart option population when projects change

- **Component Field Handling** - Fixed crashes when component field missing from API response
  - Components default to empty array if not present
  - Prevents JSON decoding failures

### Technical Improvements
- Enhanced issue detail API with parallel fetching of comments and changelog
- ADF (Atlassian Document Format) text extraction for descriptions and comments
- Improved state sharing between main window and Indigo using reactive bindings
- Window management via NotificationCenter for cross-window communication
- Smart filter option updates detect project changes automatically

## [2.0 Beta 1] - 2025-11-26

### What's New in 2.0

**🚀 JQL Query Builder**
- Build powerful Jira queries with intelligent autocomplete - no JQL knowledge required!
- Type "pro" and see "project" appear, press space to see operators (=, !=, IN), press space again to see your actual projects
- Navigate suggestions with arrow keys, select with Enter
- Works seamlessly with Indigo AI - see and edit the exact queries Indigo creates
- Color-coded suggestions help you understand what you're building

**⚡ Faster Startup**
- App now loads instantly - only fetches your projects and sprints on startup
- Issues load when you select a project or run a query
- Much more responsive, especially with large Jira instances

**🤖 Smarter Indigo AI**
- More natural status changes - just say "mark as done" or "move to in progress"
- Better understanding of your requests with longer conversation context
- Intelligent fuzzy matching finds the right status even if you're not exact
- Improved issue creation and updates with smart component lookup

**✨ Quality of Life**
- All filter options now show everything you have access to, not just what's currently loaded
- Better integration between filters and JQL queries
- Cleaner, more intuitive workflow

### Technical Improvements
- Enhanced Jira REST API v3 integration with proper pagination
- Improved status transition handling with better error messages
- More comprehensive epic search across projects
- Better logging for troubleshooting AI interactions

## [1.11] - 2025-11-20

### Added
- **Client-side filtering** in secondary toolbar for already-loaded issues
  - Created date filter with relative time options (Last 24 hours, Last week, Last month, Last 6 months)
  - Issue type filter (dynamically populated from loaded issues)
  - Status filter (dynamically populated from loaded issues)
- **"Get more..." button** to load additional issues beyond initial batch
- **Status bar** at bottom of window showing loading state and active filter indicators
- **Performance Settings tab** with configurable initial load count
  - Default changed to 100 issues for faster initial load
  - User-configurable for 100, 500, 1000+ issues
- **Debug logging** for date parsing failures to aid troubleshooting

### Changed
- **Settings window** restructured into tabbed interface
  - Connection tab (Jira URL, email, API key)
  - Performance tab (initial load count configuration)
  - Logs tab (view application logs)
- **Default JQL ordering** changed from `updated DESC` to `created DESC`
- **API endpoint migration** from deprecated `/rest/api/3/search` (POST) to `/rest/api/3/search/jql` (GET)
  - Fixes HTTP 410 errors
  - Uses URL query parameters instead of JSON body
- **Pagination logic** improved to work without total count field
  - Smart detection based on full/partial page results
  - Shows "Get more..." when additional issues likely available

### Fixed
- **Critical: Date parsing** now works correctly for sorting and filtering
  - Implemented proper ISO8601 date formatters with fractional seconds support
  - Added fallback parser for dates without fractional seconds
  - Fixes "Sort by Date Created" and "Sort by Date Updated" not changing order
  - Fixes client-side created date filter showing no results
- **Sorting within grouped issues** now applies sort option and direction correctly
- **HTTP 410 error** from using deprecated Jira API endpoint

## [1.02] - 2025-11-19

### Added
- Secondary toolbar with expand/collapse controls for grouped issues
- Persistent expansion state for disclosure groups
- Collapsible section headers with visual indicators
- Dedicated log file system at `~/Library/Application Support/Viewpoint/viewpoint.log`
- Keychain support for secure credential storage
- Customizable toolbar
- Context menu for issues (Copy Link, Log Work)
- Epic summaries with automatic fetching and display
- Settings persistence across app launches

### Changed
- Toolbar layout improved with better organization
- Resizable divider between filter panel and issue list

### Fixed
- Various UI layout and spacing improvements

## [1.01] - 2025-11-18

### Added
- Initial release of Viewpoint
- Jira Cloud integration with Basic Auth
- Issue list view with sorting and grouping
- Filter panel with server-side JQL filters
  - Status, Sprint, Assignee, Issue Type, Project, Epic filters
  - Time period filtering
- Issue details with summary, status, assignee, dates
- Status dropdown with transition support
- Required field dialogs for status transitions
- Time tracking display (original estimate, time spent, time remaining)
- Work logging functionality with time input (30m, 2h, 1d format)
- Sprint information view
- Dark mode support with auto/light/dark options
- Text size adjustment controls
- Search functionality for issues
- Double-click to open issue in browser
- Refresh button for manual data reload
- macOS menu bar integration
