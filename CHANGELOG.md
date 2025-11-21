# Changelog

All notable changes to Viewpoint will be documented in this file.

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
