# Viewpoint Frameworks & Patterns

This document describes the architectural patterns and frameworks implemented in Viewpoint's AI assistant (Indigo).

---

## 1. Capability-Tool Framework

A plugin-style architecture for AI-executable actions, inspired by LangChain/OpenAI function calling.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    CapabilityRegistry                        │
│                      (Singleton)                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  toolCache: [String: Tool]  ← Fast O(1) lookup      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      Capability                              │
│            (Protocol - groups related tools)                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  JiraCapability                                      │    │
│  │    ├── search_issues                                 │    │
│  │    ├── create_issue                                  │    │
│  │    ├── update_issue                                  │    │
│  │    └── ... (15 tools total)                          │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                        Tool                                  │
│                      (Protocol)                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  name: String                                        │    │
│  │  description: String                                 │    │
│  │  parameters: [ToolParameter]                         │    │
│  │  execute(with:) async throws -> ToolResult           │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| `Tool` protocol | Defines executable actions | `Capability.swift:6-20` |
| `ToolParameter` | Type-safe parameter definitions | `Capability.swift:25-49` |
| `ParameterType` | Recursive enum for JSON schema types | `Capability.swift:52-79` |
| `ToolResult` | Standardized success/failure result | `Capability.swift:84-96` |
| `Capability` protocol | Groups related tools | `Capability.swift:122-132` |
| `CapabilityRegistry` | Singleton registry with tool cache | `CapabilityRegistry.swift` |

### Design Decisions

- **JSON Schema Generation**: Tools auto-generate their schema for AI prompts (`generateToolSchema()`)
- **Type-Safe Argument Extraction**: Helper methods like `stringArgument()`, `intArgument()` with validation
- **Weak References**: Tools hold `weak` refs to JiraService to avoid retain cycles

### Adding a New Tool

```swift
class MyNewTool: Tool {
    let name = "my_tool"
    let description = "Does something useful"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "arg1", type: .string, description: "First argument"),
        ToolParameter(name: "arg2", type: .int, description: "Second argument", required: false)
    ]

    func execute(with arguments: [String: Any]) async throws -> ToolResult {
        guard let arg1 = try stringArgument("arg1", from: arguments) else {
            return .failure("arg1 is required")
        }
        // Do work...
        return .success("Completed successfully", data: ["result": "value"])
    }
}
```

---

## 2. ReAct Pattern (Reasoning-Acting-Observing-Thinking)

An agentic loop that allows multi-step task execution with feedback. The AI can execute actions, observe results, and decide what to do next.

### Flow

```
User Request: "Find my open bugs and close them all"
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  ITERATION 1                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  REASONING  │───▶│   ACTING    │───▶│  OBSERVING  │     │
│  │  AI decides │    │  Execute    │    │  Collect    │     │
│  │  to search  │    │  search_    │    │  results    │     │
│  │             │    │  issues     │    │  [BUG-1,2]  │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼ (actionHistory passed back)
┌─────────────────────────────────────────────────────────────┐
│  ITERATION 2                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  THINKING   │───▶│   ACTING    │───▶│  OBSERVING  │     │
│  │  AI sees    │    │  Execute    │    │  Both       │     │
│  │  BUG-1,2    │    │  change_    │    │  closed     │     │
│  │  decides to │    │  status x2  │    │  success    │     │
│  │  close both │    │             │    │             │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
└─────────────────────────────────────────────────────────────┘
                    │
                    ▼ (AI responds with TASK_COMPLETE)
┌─────────────────────────────────────────────────────────────┐
│  EXIT: "I've closed both BUG-1 and BUG-2. TASK_COMPLETE"    │
└─────────────────────────────────────────────────────────────┘
```

### Key Elements

| Element | Implementation | Location |
|---------|---------------|----------|
| Action History | `[(action: AIAction, result: ToolResult)]` tuple array | `AIContext` in `IndigoModels.swift:91` |
| User Goal | Preserved across iterations for context | `AIContext.userGoal` |
| Task Complete Signal | `TASK_COMPLETE` marker in AI response | `AIService.swift:909-915` |
| Safety Limit | Max 5 iterations | `IndigoViewModel.swift:287` |
| Cancellation | `isCancelled` flag + `stopExecution()` | `IndigoViewModel.swift:16, 196-207` |

### Implementation Details

The loop is implemented in `IndigoViewModel.executeAgenticLoop()`:

```swift
while !taskComplete && iterations < maxIterations {
    // Check for user cancellation
    if isCancelled { break }

    // Execute current batch of actions
    for action in currentActions {
        let result = await executeActionAndGetResult(action)
        actionHistory.append((action, result))
    }

    // Ask AI for next steps based on results
    let continuationResponse = await askAIForNextSteps(
        userGoal: userGoal,
        actionHistory: actionHistory,
        aiService: aiService
    )

    taskComplete = continuationResponse.taskComplete
    currentActions = continuationResponse.actions
}
```

---

## 3. Contextual Reference Resolution

Pattern for resolving natural language references ("this", "me") to concrete values.

### Resolution Table

| Reference | Resolved To | Source in Context |
|-----------|-------------|-------------------|
| "this", "it", "the issue" | Selected issue key(s) | `selectedIssues` |
| "these", "them" | All selected issues | `selectedIssues` |
| "me", "myself", "current user" | User's email | `currentUser` |
| "retry", "try again" | Same selection | `selectedIssues` (priority over history) |
| "what is this about?" | Direct answer | `selectedIssueDetails` |

### Implementation

Resolution happens at the **prompt level**, not in tools. The system prompt in `AIService.buildSystemPrompt()` includes:

```
CURRENTLY SELECTED ISSUES (CRITICAL - USE THESE FOR OPERATIONS):
The user has 2 issue(s) currently selected: PROJ-123, PROJ-456

IMPORTANT RULES FOR SELECTED ISSUES:
1. When the user says "this", "it", "the issue", "these", "them",
   "try again", "retry", or asks to perform any action without
   explicitly specifying an issue key, ALWAYS use: PROJ-123, PROJ-456
2. IGNORE any issue keys mentioned in the conversation history above -
   the user may have changed their selection
3. The selected issues shown here are the CURRENT selection and take
   priority over everything else
```

### Design Rationale

- **Tools stay simple**: They just take explicit parameters
- **AI handles interpretation**: Natural language resolution is the AI's job
- **Context is fresh**: Rebuilt on each request
- **Selection overrides history**: Prevents stale references

---

## 4. Confirmation Guard Pattern

Safety mechanism for bulk and destructive operations.

### Triggers

| Condition | Threshold | Message |
|-----------|-----------|---------|
| Bulk operations | >5 issues affected | "Confirm Bulk Operation" |
| Destructive operations | Any `delete_issue` | "Confirm Deletion" |

### Implementation

```swift
// IndigoViewModel.swift
func needsConfirmation(actions: [AIAction]) -> (needed: Bool, message: String, details: String) {
    let bulkActions = actions.filter { action in
        ["update_issue", "assign_issue", "delete_issue", "change_status", "add_comment"]
            .contains(action.tool)
    }

    let destructiveActions = actions.filter { $0.tool == "delete_issue" }

    if bulkActions.count > 5 {
        return (needed: true, message: "Confirm Bulk Operation", details: "...")
    }

    if !destructiveActions.isEmpty {
        return (needed: true, message: "Confirm Deletion", details: "...")
    }

    return (needed: false, message: "", details: "")
}

func waitForConfirmation(message: String, details: String) async -> Bool {
    await withCheckedContinuation { continuation in
        self.confirmationMessage = message
        self.confirmationDetails = details
        self.confirmationContinuation = continuation
        self.showConfirmationAlert = true
    }
}
```

The pattern uses Swift's `CheckedContinuation` to pause async execution until the user responds to the SwiftUI alert.

---

## 5. Dual Action System (Actions + Legacy Intents)

Backward-compatible migration from text-based commands to JSON actions.

### New System (JSON Actions)

```
ACTION: {"tool": "assign_issue", "args": {"issueKey": "PROJ-123", "assignee": "user@email.com"}}
```

- Parsed by `parseActions()` in `AIService.swift`
- Returns `[AIAction]`
- Executed via `CapabilityRegistry.execute()`

### Legacy System (Text Intents)

```
ASSIGN: PROJ-123 | user@email.com
UPDATE: PROJ-123 | status=Done | resolution=Fixed
```

- Parsed by `parseIntents()` in `AIService.swift`
- Returns `[AIResponse.Intent]`
- Executed via `executeIntent()` switch statement

### Priority

```swift
if !response.actions.isEmpty {
    // Use new JSON-based system with ReAct loop
    await executeAgenticLoop(...)
} else if !response.intents.isEmpty {
    // Fall back to legacy system
    for intent in response.intents {
        await executeIntent(intent)
    }
}
```

### Migration Path

The legacy system remains for backward compatibility but new development should use JSON actions. The legacy system will be deprecated once all AI models consistently produce JSON actions.

---

## 6. AIContext Pattern

Rich context object passed to the AI for informed decision-making.

### Structure

```swift
struct AIContext {
    // Identity & Selection
    let currentUser: String                    // For "me" resolution
    let selectedIssues: [JiraIssue]           // For "this" resolution
    let selectedIssueDetails: [IssueDetails]  // For answering questions

    // Current State
    let currentFilters: IssueFilters          // Active filter state
    let visibleIssues: [JiraIssue]            // Top 20 visible issues

    // Available Options (for dropdowns/pickers)
    let availableProjects: [String]
    let availableSprints: [JiraSprint]
    let availableEpics: [String]
    let availableStatuses: [String]
    let availableResolutions: [String]

    // Search/Create Results
    let lastSearchResults: [JiraIssue]?
    let lastCreatedIssue: String?

    // ReAct Pattern
    let actionHistory: [(action: AIAction, result: ToolResult)]?
    let userGoal: String?
}
```

### Usage

Context is built fresh on each AI request in `AIService.buildContext()`:

```swift
private func buildContext(
    actionHistory: [(action: AIAction, result: ToolResult)]? = nil,
    userGoal: String? = nil
) async -> AIContext {
    let currentUser = UserDefaults.standard.string(forKey: "jiraEmail") ?? "unknown"
    let selectedIssues = await MainActor.run { jiraService.selectedIssues... }
    // ... gather all context
    return AIContext(...)
}
```

---

## 7. AnyCodableValue Pattern

Type-erased wrapper for handling dynamic JSON in Swift's strict type system.

### Problem

Swift's `Codable` requires known types at compile time, but AI returns arbitrary JSON arguments like:

```json
{"tool": "update_issue", "args": {"issueKey": "PROJ-123", "fields": {"priority": "High", "storyPoints": 5}}}
```

### Solution

```swift
struct AnyCodableValue: Codable, Equatable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try each type in priority order
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(...)
        }
    }
}
```

### Usage in AIAction

```swift
struct AIAction: Codable {
    let tool: String
    let args: [String: AnyCodableValue]

    var arguments: [String: Any] {
        return args.mapValues { $0.value }  // Convert back for tool execution
    }
}
```

---

## 8. Message Status Pattern

Visual feedback system for chat messages.

### States

```swift
enum MessageStatus {
    case success    // ✓ Green checkmark
    case warning    // ⚠️ Yellow/orange
    case error      // ✗ Red
    case processing // 🔄 Animated spinner
}
```

### Usage

```swift
addMessage(Message(
    text: "✓ Successfully updated PROJ-123!",
    sender: .system,
    status: .success
))

addMessage(Message(
    text: "⚡ Executing: search_issues",
    sender: .system,
    status: .processing
))
```

The status is used by `IndigoView` to render appropriate styling and icons.

---

## Summary

| Pattern | Purpose | Key Files |
|---------|---------|-----------|
| Capability-Tool | Pluggable AI actions | `Capability.swift`, `CapabilityRegistry.swift`, `JiraCapability.swift` |
| ReAct Loop | Multi-step task execution | `IndigoViewModel.swift:277-404`, `AIService.swift:69-99` |
| Context Resolution | "this"/"me" → concrete values | `AIService.swift:234-352` |
| Confirmation Guard | Safety for bulk/destructive ops | `IndigoViewModel.swift:211-275` |
| Dual Action System | JSON + legacy compatibility | `AIService.swift:875-915`, `IndigoModels.swift:203-223` |
| AIContext | Rich context for AI | `IndigoModels.swift:76-93` |
| AnyCodableValue | Type-erased JSON | `IndigoModels.swift:114-171` |
| Message Status | Visual feedback | `IndigoModels.swift:26-31` |
