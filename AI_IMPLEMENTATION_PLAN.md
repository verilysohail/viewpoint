# AI Implementation Plan for Viewpoint

## Overview
Add natural language AI capabilities to Viewpoint, enabling users to search, create, and update Jira issues using conversational commands instead of manual UI interactions.

## Core Capabilities (Phase 1)

### 1. Natural Language Search
**Goal**: Find issues using conversational queries instead of JQL or manual filters

**Examples**:
- "Find tickets I created last week about authentication"
- "Show me all high priority bugs assigned to Kevin"
- "What issues are blocking the login feature?"

**Implementation**:
- AI converts natural language → JQL query
- Executes search via existing JiraService
- Displays results in main issue list

### 2. Natural Language Updates
**Goal**: Modify existing issues using conversational commands

**Examples**:
- "Add 4 hours estimate to SETI-840"
- "Log 2 hours of work on the selected issue"
- "Move SETI-776 to In Progress"
- "Change priority to High for all selected issues"

**Implementation**:
- AI interprets intent and extracts parameters
- Makes appropriate Jira API calls
- Confirms action and refreshes data

### 3. Natural Language Creation
**Goal**: Create new issues using conversational descriptions

**Examples**:
- "Create a story to implement OAuth login with 8 hour estimate"
- "Add a bug: Dashboard crashes when filtering by epic"
- "New task: Review security documentation, assign to me, current sprint"

**Implementation**:
- AI extracts issue type, summary, description, fields
- Creates issue via Jira API
- Returns issue key and link

## Technical Architecture

### New Components

#### 1. AIService.swift
```swift
class AIService: ObservableObject {
    // Claude API integration
    // Manages conversation context
    // Routes to appropriate handlers

    func processQuery(_ query: String, context: AIContext) async -> AIResponse
    func generateJQL(from query: String) async -> String?
    func interpretUpdateCommand(_ command: String) async -> UpdateIntent?
    func parseCreateIntent(_ command: String) async -> CreateIssueIntent?
}
```

#### 2. AIContext.swift
```swift
struct AIContext {
    // Current user info (from config)
    // Current filters/view state
    // Selected issue(s)
    // Recent operations
    // Available projects, epics, sprints, etc.
}
```

#### 3. AI Command Palette UI
**Location**: Accessible via keyboard shortcut (⌘K or ⌘Space)

**Features**:
- Floating command palette overlay
- Text input for natural language
- Real-time AI processing indicator
- Results/confirmation display
- Action buttons (Execute, Cancel, Refine)

#### 4. Configuration
**Settings → AI Tab**:
- Anthropic API Key (secure storage in Keychain)
- Model selection (Claude 3.5 Sonnet, Haiku, etc.)
- Enable/disable AI features
- Cost tracking display

### Integration Points

#### With Existing JiraService
```swift
// AIService calls existing methods:
- jiraService.fetchMyIssues() // After generating JQL
- jiraService.updateIssueStatus()
- jiraService.logWork()
- New: jiraService.createIssue()
- New: jiraService.updateIssueFields()
```

#### With Configuration
```swift
// Access existing credentials:
- config.jiraBaseURL
- config.jiraEmail
- config.jiraAPIKey

// New credential:
- config.anthropicAPIKey
```

## User Interface Design

### Command Palette (Primary Interface)
```
┌─────────────────────────────────────────────────┐
│ 🤖 Ask Viewpoint...                      ⌘K    │
│                                                  │
│ [Text input field]                              │
│                                                  │
│ ⚡ Quick Actions:                               │
│   • Search for issues                           │
│   • Update selected issue                       │
│   • Create new issue                            │
│                                                  │
│ 📝 Recent:                                      │
│   • "Find my issues from last week"             │
│   • "Log 2h on SETI-840"                        │
└─────────────────────────────────────────────────┘
```

### In-Context AI Actions
Add AI button to:
1. **Issue rows** → Quick update commands for that issue
2. **Toolbar** → Global AI command palette
3. **Filter panel** → AI-powered filter generation

### Response Display
```
┌─────────────────────────────────────────────────┐
│ 🤖 Understanding your request...                │
│                                                  │
│ You asked: "Find bugs I created last week"      │
│                                                  │
│ I'll search for:                                │
│ • Type: Bug                                     │
│ • Creator: You (smamdani@verily.health)        │
│ • Created: Last 7 days                          │
│                                                  │
│ Generated JQL:                                  │
│ type = Bug AND creator = currentUser()         │
│ AND created >= -7d                              │
│                                                  │
│ [Execute Search]  [Refine]  [Cancel]            │
└─────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Add Anthropic API key to Settings (Keychain storage)
- [ ] Create AIService.swift with Claude API integration
- [ ] Implement basic prompt engineering for JQL generation
- [ ] Add command palette UI (⌘K shortcut)
- [ ] Test natural language → JQL conversion

**Deliverable**: Can search using "Find my issues from last week"

### Phase 2: Search Refinement (Week 1-2)
- [ ] Improve context awareness (use current filters, selected issue)
- [ ] Add conversation memory (follow-up queries)
- [ ] Handle ambiguous queries with clarification
- [ ] Add search history
- [ ] Show AI reasoning/JQL preview before executing

**Deliverable**: Robust natural language search with context

### Phase 3: Update Operations (Week 2)
- [ ] Implement update intent parsing
- [ ] Add support for:
  - Status transitions
  - Time logging
  - Estimate updates
  - Assignee changes
  - Priority changes
  - Sprint assignment
- [ ] Confirmation dialogs for destructive changes
- [ ] Batch operations support

**Deliverable**: Can update issues via "Log 4h on SETI-840"

### Phase 4: Issue Creation (Week 2-3)
- [ ] Implement create intent parsing
- [ ] Extract fields from natural language:
  - Issue type
  - Summary
  - Description
  - Assignee
  - Estimate
  - Sprint
  - Epic
  - Priority
- [ ] Smart defaults (current sprint, assign to me, etc.)
- [ ] Preview before creation
- [ ] Return created issue key

**Deliverable**: Can create issues via natural language

### Phase 5: Polish & UX (Week 3)
- [ ] Add AI button to issue rows for quick actions
- [ ] Implement cost tracking and display
- [ ] Add model selection (Haiku for speed, Sonnet for quality)
- [ ] Error handling and user-friendly messages
- [ ] Loading states and progress indicators
- [ ] Help/examples in command palette
- [ ] Keyboard shortcuts for common actions

**Deliverable**: Production-ready AI features

## Prompt Engineering Strategy

### System Prompts

#### For Search (JQL Generation)
```
You are a Jira JQL expert integrated into Viewpoint.
Convert natural language queries to valid Jira JQL.

Available context:
- User: {userEmail}
- Current filters: {currentFilters}
- Available projects: {projects}
- Available sprints: {sprints}
- Available epics: {epics}

Rules:
1. Use currentUser() for "me/my/I"
2. Use relative dates (-7d, -1w, -1M)
3. Consider current context
4. Return ONLY valid JQL
5. If ambiguous, ask clarifying question
```

#### For Updates
```
You are a Jira update assistant in Viewpoint.
Parse natural language commands to update Jira issues.

Extract:
- Action: (log_work, update_status, change_assignee, etc.)
- Target: Issue key or "selected"
- Parameters: (time, status name, assignee, etc.)

Return JSON with intent and parameters.
```

#### For Creation
```
You are a Jira issue creation assistant in Viewpoint.
Extract structured data from natural language descriptions.

Extract:
- issueType: Story/Bug/Task/Epic
- summary: Brief title
- description: Detailed description
- assignee: Email or "me"
- estimate: Time in seconds
- sprint: Sprint ID or "current"
- epic: Epic key
- priority: High/Medium/Low

Apply smart defaults when not specified.
```

## API Cost Management

### Cost Tracking
- Track tokens used per request
- Display monthly usage in settings
- Warning when approaching budget limit
- Option to use Haiku for cheaper operations

### Optimization
- Use Haiku for simple JQL generation (faster, cheaper)
- Use Sonnet for complex updates/creation (better accuracy)
- Cache common patterns
- Minimize context size

## Security Considerations

1. **API Key Storage**: Use Keychain for Anthropic API key (like Jira credentials)
2. **Validation**: Validate all AI-generated JQL and API calls before execution
3. **Confirmation**: Require confirmation for destructive operations
4. **Audit Trail**: Log all AI operations to viewpoint.log
5. **Rate Limiting**: Prevent abuse with request throttling

## Testing Strategy

### Unit Tests
- JQL generation accuracy
- Intent parsing correctness
- Field extraction from natural language

### Integration Tests
- End-to-end search flow
- Update operations
- Issue creation

### User Testing
- Collect common query patterns
- Test with real Jira data
- Iterate on prompt engineering

## Future Enhancements (Phase 2+)

### Summaries & Reports
- End of day summary
- End of week summary
- Sprint retrospective summary
- Time tracking reports

### Advanced Features
- Bulk operations via natural language
- Smart suggestions based on context
- Learn from user patterns
- Voice input support
- Multi-turn conversations

### Integrations
- MCP server support (optional)
- Export summaries to Slack/Email
- Calendar integration for time tracking

## Success Metrics

1. **Adoption**: % of operations done via AI vs manual
2. **Accuracy**: % of AI commands executed without refinement
3. **Speed**: Time saved vs manual operations
4. **User Satisfaction**: Feedback and usage patterns
5. **Cost Efficiency**: Cost per operation vs value

## Questions to Resolve

1. **Model Selection**: Default to Haiku or Sonnet? User configurable?
2. **Confirmation UX**: Always confirm updates, or trust after N successful operations?
3. **Error Recovery**: How to handle API failures gracefully?
4. **Offline Mode**: Cache previous results? Show "AI unavailable"?
5. **Privacy**: Log prompts/responses? User control over this?

## Next Steps

1. Review this plan and get approval
2. Implement Phase 1 (Foundation + Command Palette)
3. Test with real queries
4. Iterate based on feedback
5. Proceed to subsequent phases

---

**Estimated Timeline**: 3 weeks for Phases 1-5
**Primary Risk**: Prompt engineering accuracy - may need iteration
**Mitigation**: Start with high-confidence operations, add confirmation steps
