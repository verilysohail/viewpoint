# Viewpoint Data Flow Architecture

## Overview
Viewpoint follows a single source of truth pattern where JiraService holds all app state as `@Published` properties, and SwiftUI views observe changes using `@EnvironmentObject`.

---

## Data Storage Locations

### JiraService (Single Source of Truth)
All data is stored in memory as `@Published` properties in `JiraService.swift`:

```
JiraService (@ObservableObject)
├── @Published var issues: [JiraIssue]              // Currently loaded issues (100-500 items)
├── @Published var sprints: [JiraSprint]            // Recently used sprints
├── @Published var availableSprints: [JiraSprint]   // All sprints (from issues + boards)
├── @Published var availableProjects: Set<String>   // All project names
├── @Published var availableStatuses: Set<String>   // All statuses (from loaded issues)
├── @Published var availableAssignees: Set<String>  // All assignees (from loaded issues)
├── @Published var availableIssueTypes: Set<String> // All issue types (from loaded issues)
├── @Published var availableComponents: Set<String> // All components (from loaded issues)
├── @Published var availableEpics: Set<String>      // All epic keys (from loaded issues)
├── @Published var epicSummaries: [String: String]  // Epic key -> summary mapping
├── @Published var projectSprintsCache: [String: [JiraSprint]] // Project key -> sprints
├── @Published var filters: IssueFilters            // Current filter state
├── @Published var isLoading: Bool                  // Loading state
├── @Published var errorMessage: String?            // Error state
└── var sprintProjectMap: [Int: Set<String>]        // Sprint ID -> project keys
```

### UserDefaults (Persistent Storage)
Small amounts of persistent data:
```
UserDefaults
├── jiraBaseURL: String
├── jiraEmail: String
├── jiraAPIKey: String
├── jiraAccountId: String?
└── filterPanelHeight: Double
```

---

## Data Flow Diagrams

### 1. App Startup Flow

```
┌─────────────┐
│ App Launch  │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ ContentView.onAppear()                  │
│ - Creates JiraService instance          │
│ - Injects as @EnvironmentObject         │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ JiraService.init()                      │
│ - Loads config from UserDefaults        │
│ - Initializes empty @Published vars     │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ JiraService.initialize() async          │
│ ├─→ fetchAvailableProjects()            │
│ ├─→ fetchSprints() (no-op now)          │
│ └─→ fetchCurrentUser()                  │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ JiraService.fetchMyIssues()             │
│ ├─→ Builds JQL from filters             │
│ ├─→ Calls Jira API (paginated)          │
│ ├─→ Stores in 'issues' array            │
│ └─→ Calls updateAvailableFilters()      │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ updateAvailableFilters()                │
│ - Extracts unique values from issues    │
│ - Updates availableStatuses              │
│ - Updates availableAssignees             │
│ - Updates availableIssueTypes            │
│ - Updates availableComponents            │
│ - Updates availableEpics                 │
│ - Merges issue sprints → availableSprints│
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ SwiftUI Views Auto-Refresh              │
│ (Because @Published vars changed)        │
│ - IssueListView shows issues             │
│ - FilterPanel shows filter options       │
└──────────────────────────────────────────┘
```

---

### 2. Filter Selection Flow

```
┌─────────────────────┐
│ User clicks filter  │
│ in FilterPanel      │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ FilterPanel updates                     │
│ jiraService.filters.projects.insert()   │
│ (SwiftUI Binding)                        │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ FilterPanel calls                       │
│ jiraService.applyFilters()              │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ JiraService.applyFilters()              │
│ ├─→ saveFilters() to UserDefaults       │
│ ├─→ Detects project change               │
│ └─→ Calls fetchMyIssues(updateOptions)   │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ fetchMyIssues()                         │
│ ├─→ Builds new JQL query                │
│ ├─→ Fetches from Jira API               │
│ ├─→ Updates 'issues' array              │
│ └─→ Updates available filter options     │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ SwiftUI Views Auto-Refresh              │
│ - IssueListView shows filtered issues   │
│ - FilterPanel shows updated options      │
└──────────────────────────────────────────┘
```

---

### 3. On-Demand Sprint Fetching Flow

```
┌─────────────────────┐
│ User filters to     │
│ project "SETI"      │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ FilterPanel computes filteredSprints    │
│ (computed property)                      │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ Check projectSprintsCache["SETI"]       │
└──────┬──────────────────────────────────┘
       │
       ├─ Cached ──→ Return cached sprints
       │
       └─ Not Cached
              │
              ▼
       ┌──────────────────────────────────┐
       │ Trigger async fetch:             │
       │ fetchAndCacheSprintsForProject() │
       └──────┬───────────────────────────┘
              │
              ▼
       ┌──────────────────────────────────┐
       │ API: GET /board?projectKeyOrId=SETI │
       │ Returns SETI's Scrum boards       │
       └──────┬───────────────────────────┘
              │
              ▼
       ┌──────────────────────────────────┐
       │ For each board:                   │
       │ fetchSprintsForBoard(boardId)     │
       │ API: GET /board/{id}/sprint       │
       └──────┬───────────────────────────┘
              │
              ▼
       ┌──────────────────────────────────┐
       │ Cache sprints:                    │
       │ projectSprintsCache["SETI"] = ... │
       └──────┬───────────────────────────┘
              │
              ▼
       ┌──────────────────────────────────┐
       │ @Published var triggers refresh   │
       │ FilterPanel shows ALL SETI sprints│
       └────────────────────────────────────┘
```

---

### 4. Issue Update Flow (with Optimistic Updates)

```
┌─────────────────────┐
│ User changes sprint │
│ in IssueDetailView  │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ IssueDetailView calls                   │
│ jiraService.moveIssueToSprint()         │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ moveIssueToSprint()                     │
│ API: POST /sprint/{id}/issue            │
│     Body: {"issues": ["SETI-123"]}      │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ If HTTP 200/204 (Success):              │
│ ✅ OPTIMISTIC UPDATE                     │
│                                          │
│ await MainActor.run {                   │
│   if let index = issues.firstIndex(...) │
│     var updated = issues[index]         │
│     updated.fields.sprint = newSprint   │
│     issues[index] = updated             │
│ }                                        │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ @Published var 'issues' changed         │
│ SwiftUI auto-refreshes ALL views:       │
│ - IssueListView (shows new sprint)      │
│ - IssueDetailView (shows new sprint)    │
│ - NO manual refresh needed! ✨           │
└──────────────────────────────────────────┘
```

---

### 5. JQL Autocomplete Flow (Dynamic API Fetching)

```
┌─────────────────────┐
│ User types:         │
│ "assignee = "       │
└──────┬──────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ JQLBuilderView.updateSuggestions()      │
│ - Detects context = .value              │
│ - Field = "assignee"                     │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ generateValueSuggestionsAsync()         │
│ Calls API for ALL assignees:            │
│ fetchJQLAutocompleteSuggestions()       │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ API: GET /jql/autocompletedata/         │
│      suggestions?fieldName=assignee     │
│ Returns ALL users in Jira instance      │
└──────┬──────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────┐
│ Display suggestions dropdown            │
│ - Shows 100s of users                   │
│ - Not limited to loaded issues! ✨       │
└──────────────────────────────────────────┘
```

---

## Key Architectural Patterns

### 1. **Single Source of Truth**
- All app state lives in `JiraService`
- Views don't maintain local copies
- Data flows one way: Service → Views

### 2. **Reactive Updates**
```swift
// When this changes...
jiraService.issues[0].status = "Done"

// These views AUTOMATICALLY refresh:
- IssueListView (shows new status)
- IssueDetailView (shows new status)
- FilterPanel (updates available statuses)
```

### 3. **Optimistic Updates**
```swift
// Old way (❌ Stale):
API.updateIssue() → return success
// UI still shows old data

// New way (✅ Fresh):
API.updateIssue() → return success
└→ Immediately update local 'issues' array
   └→ SwiftUI auto-refreshes all views
```

### 4. **On-Demand Fetching**
- Don't fetch ALL boards at startup (too slow)
- Fetch sprints per-project when needed
- Cache results for instant subsequent access

### 5. **Pagination**
- Issues fetched in batches of 100
- `currentPageToken` tracks pagination state
- "Load More" fetches next 500 issues

---

## Memory Footprint

### Typical Session
```
JiraService
├── issues: ~100-500 items × ~5KB = 500KB-2.5MB
├── availableSprints: ~50-200 items × 1KB = 50-200KB
├── projectSprintsCache: ~5 projects × 50 sprints = 250KB
├── epicSummaries: ~20 epics × 500B = 10KB
└── Filter options: ~5KB
──────────────────────────────────────────────────
Total: ~1-3MB in memory
```

### Persistence
```
UserDefaults: <5KB
No local database, no caching to disk
Everything re-fetched on app launch
```

---

## Data Lifetime

| Data | Lifetime | Refresh Trigger |
|------|----------|----------------|
| issues | Until filter change | User clicks filter, refresh button |
| availableSprints | Until app restart | Merged from issues + on-demand fetches |
| projectSprintsCache | Until app restart | First access per project |
| filters | Persistent | User changes filters |
| config (URL/credentials) | Persistent | User updates settings |

---

## API Call Patterns

### Startup (3 calls)
1. `GET /project` - Fetch all projects
2. `GET /myself` - Fetch current user
3. `GET /search?jql=...` - Fetch initial issues

### Filter Change (1 call)
1. `GET /search?jql=...` - Fetch filtered issues

### Sprint Selector (per project, cached)
1. `GET /board?projectKeyOrId=X` - Fetch project boards
2. `GET /board/{id}/sprint` - Fetch sprints for each board

### Issue Update (1-2 calls)
1. `POST /sprint/{id}/issue` - Move to sprint
   - OR `PUT /issue/{key}` - Update field
2. **No refetch needed** - Optimistic update!

### JQL Autocomplete (per keystroke)
1. `GET /jql/autocompletedata/suggestions` - Live suggestions

---

## Common Pitfalls (Now Fixed! ✅)

### ❌ Before: Stale Data After Updates
```swift
await updateIssue(...)
// UI still shows old sprint
// Must manually refresh
```

### ✅ After: Optimistic Updates
```swift
await updateIssue(...)
// Update local copy immediately
issues[index] = updatedIssue
// UI auto-refreshes!
```

### ❌ Before: Missing Autocomplete Values
```swift
// Only showed assignees from loaded issues
availableAssignees // 5 users
```

### ✅ After: API-Based Autocomplete
```swift
// Fetches ALL users from Jira
fetchJQLAutocompleteSuggestions() // 200+ users
```

### ❌ Before: Slow Startup
```swift
// Fetched ALL 529 boards at startup
// Took 2+ minutes
```

### ✅ After: On-Demand Fetching
```swift
// Fetches sprints only when project selected
// Takes 1-2 seconds
```

---

## Thread Safety

All API calls run on background threads, but updates to `@Published` properties happen on `MainActor`:

```swift
await MainActor.run {
    self.issues = newIssues
}
```

SwiftUI automatically observes these changes and updates the UI on the main thread.
