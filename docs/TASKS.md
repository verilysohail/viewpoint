# Viewpoint Tasks

## Feature Enhancements

### Status Dropdown - Show Only Valid Transitions
**Status**: Pending
**Priority**: Medium
**Description**: Currently, the status dropdown in both the List view and Detail window shows all available statuses from the Jira instance. However, Jira workflows only allow specific transitions between statuses based on workflow configuration. This can be confusing when users select a status and nothing happens because that transition isn't allowed.

**Current Behavior**:
- All statuses are shown in the dropdown menu
- User can select any status, but the transition may fail silently if not allowed by the workflow
- For example, "New" might not be able to transition directly to "Closed"

**Desired Behavior**:
- Query Jira for valid transitions available for the current issue
- Only show statuses that are valid transitions in the dropdown
- This makes it clear what status changes are actually possible

**Implementation Notes**:
- JiraService already has `getTransitionInfo(issueKey:targetStatus:)` method
- Need to query available transitions for the issue when building the dropdown
- Should cache transitions to avoid repeated API calls
- Affects both `StatusDropdown` in ContentView.swift and `statusDropdown` in IssueDetailView.swift

**Related Files**:
- `/Viewpoint/ContentView.swift` (StatusDropdown view)
- `/Viewpoint/Views/IssueDetailView.swift` (statusDropdown view)
- `/Viewpoint/Services/JiraService.swift` (transition API methods)

---

### Create Child Items from Detail Window
**Status**: Pending
**Priority**: Medium
**Description**: Add the ability to create child items directly from the Detail window based on the parent issue type. This would streamline the workflow for creating hierarchical issue structures without needing to go back to the main list view.

**Current Behavior**:
- The Detail window shows child items in the "Child Items" tab
- No way to create new child items from the Detail window
- Users must close the Detail window and create child items from the main view

**Desired Behavior**:
- Add a "Create Child" button in the Detail window
- Button behavior depends on parent issue type:
  - **Initiative** → Create child Epic
  - **Epic** → Create child Story
  - **Story** → Create child Subtask
  - **Task** → Create child Subtask
- Automatically link the new child to the parent issue
- Automatically set appropriate fields (project, sprint inheritance, etc.)
- After creation, refresh the Child Items tab to show the new item

**Implementation Notes**:
- Add button to the Child Items tab or in the header area
- Reuse or create a dialog similar to the existing issue creation flow
- The new issue should:
  - Have the correct issue type based on parent
  - Be linked to the parent (via parent field or epic link)
  - Inherit project from parent
  - Optionally inherit sprint from parent
- After creation, refresh both the child issues list and potentially the main issue list
- Consider disabling the button for issue types that don't have child types (e.g., Subtasks can't have children)

**Related Files**:
- `/Viewpoint/Views/IssueDetailView.swift` (Detail window and Child Items tab)
- `/Viewpoint/Services/JiraService.swift` (issue creation methods)
- `/Viewpoint/ContentView.swift` (may have create issue dialogs to reference)
