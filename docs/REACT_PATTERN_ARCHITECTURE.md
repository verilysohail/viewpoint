# ReAct Pattern & Agentic Loops: Architectural Documentation

**Version:** 1.0
**Date:** January 6, 2026
**Purpose:** Explain the ReAct (Reasoning + Acting) pattern and agentic loops for implementing intelligent, multi-step task execution in Indigo

---

## Table of Contents

1. [The Problem: Why We Need ReAct](#the-problem-why-we-need-react)
2. [What is the ReAct Pattern?](#what-is-the-react-pattern)
3. [Understanding Agentic Loops](#understanding-agentic-loops)
4. [Information Flow Architecture](#information-flow-architecture)
5. [Implementation Breakdown](#implementation-breakdown)
6. [Specific Application to Indigo](#specific-application-to-indigo)
7. [Benefits and Trade-offs](#benefits-and-trade-offs)

---

## The Problem: Why We Need ReAct

### The Limitation of Single-Turn Execution

Imagine you're asking a human assistant to complete a task:

**You:** "Find the document about Q1 planning and email it to Sarah."

**Traditional AI (Single-Turn) Approach:**
```
AI receives request → AI creates complete plan upfront → System executes plan
```

This works fine for simple tasks where all information is available upfront. But consider this scenario:

**You:** "Assign that epic to me and give it the parent SETI-1089."

The AI doesn't know which epic you're referring to! It needs to:
1. **Search** for the epic (requires searching with a query like "FY26Q1 management tasks")
2. **Discover** the epic key (e.g., "FY26Q1-123")
3. **Update** the epic with assignee and parent

Here's the problem: In a single-turn system, the AI must generate ALL actions at once:

```
❌ BROKEN: Single-Turn Planning

User Request:
"Assign that epic to me and give it the parent SETI-1089"

AI Generates Actions (all at once):
1. ACTION: search_issues with query "FY26Q1 management tasks"
2. ACTION: update_issue with issueKey = ???  ← PROBLEM: Don't know the key yet!

Result: The AI can't plan step 2 because it doesn't know
        the result of step 1 yet!
```

This is called an **information dependency** - a later step depends on the results of an earlier step.

### Real-World Example: The Epic Assignment Failure

In Indigo, we saw this exact problem:

```
User Voice Input (transcribed):
"Okay, there was an epic with FY26Q1 management tasks.
 Assign that epic to me and give it the parent SETI-1089."

What Happened:
✓ AI searched and found issue FY26Q1-123
✗ AI stopped - didn't assign or set parent

Why:
The AI couldn't know the issue key when planning the update action,
so it only generated the search action.
```

---

## What is the ReAct Pattern?

### Core Concept

**ReAct** stands for **Reasoning + Acting** - a pattern where an AI agent alternates between:
- **Reasoning:** Thinking about what to do next
- **Acting:** Taking actions in the world
- **Observing:** Seeing the results of those actions
- **Repeating:** Using new information to decide next steps

Think of it like a conversation between the AI and the system:

```
┌─────────────────────────────────────────────────────────┐
│  ReAct Pattern: A Conversation Between AI and System   │
└─────────────────────────────────────────────────────────┘

AI:       "I'll search for the FY26Q1 epic first."
          ACTION: search_issues(query="FY26Q1 management")

System:   "Found 1 issue: FY26Q1-123"

AI:       "Great! Now I can assign it. The issue key is FY26Q1-123."
          ACTION: update_issue(key="FY26Q1-123", assignee="user", parent="SETI-1089")

System:   "Successfully updated FY26Q1-123"

AI:       "Task complete! I've assigned the epic to you and set the parent."
```

### The Three Phases

Every iteration of ReAct has three phases:

```
┌──────────────┐
│ 1. THINK     │ → AI analyzes the situation and decides what to do
└──────────────┘
       ↓
┌──────────────┐
│ 2. ACT       │ → AI generates action(s) to execute
└──────────────┘
       ↓
┌──────────────┐
│ 3. OBSERVE   │ → System executes actions and reports results back
└──────────────┘
       ↓
      (Repeat until task complete)
```

### Comparison: Before and After

**Before ReAct (Single-Turn):**
```
User → AI → [Action1, Action2, Action3] → System → Done
           ↑
           All actions planned upfront
           Can't handle information dependencies
```

**After ReAct (Multi-Turn with Feedback Loop):**
```
User → AI → Action1 → System → Results → AI → Action2 → System → Results → AI → Done
       ↑                        ↓          ↑              ↓          ↑
       Initial plan      Feedback loop  Adjust plan  More feedback  Decide complete
```

---

## Understanding Agentic Loops

### What is an "Agent"?

In AI, an **agent** is a system that:
1. Perceives its environment (gets information)
2. Makes decisions (reasons about what to do)
3. Takes actions (does something)
4. Learns from outcomes (adapts based on results)

Think of it like a human employee who doesn't just follow a script, but actively solves problems:

```
┌────────────────────────────────────────────────────────┐
│          Script Follower vs. Autonomous Agent          │
├────────────────────────────────────────────────────────┤
│                                                        │
│  Script Follower (Traditional):                        │
│  "Follow these exact steps: 1, 2, 3, 4, 5"           │
│  → Can't handle unexpected situations                  │
│  → Breaks if a step fails                             │
│  → Can't adapt to new information                      │
│                                                        │
│  Autonomous Agent (Agentic Loop):                      │
│  "Achieve this goal using available tools"            │
│  → Handles unexpected results                          │
│  → Retries or adapts if something fails               │
│  → Incorporates new information dynamically            │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### The Agentic Loop Structure

An **agentic loop** is the control flow that enables agent behavior:

```
┌─────────────────────────────────────────────────────────────┐
│                    THE AGENTIC LOOP                         │
└─────────────────────────────────────────────────────────────┘

    ╔════════════════════════════════════════════════╗
    ║  START: User provides goal                     ║
    ╚════════════════════════════════════════════════╝
                        ↓
    ┌────────────────────────────────────────────────┐
    │ 1. PERCEIVE                                    │
    │    - What do I know?                           │
    │    - What happened from last action?           │
    │    - What information do I have?               │
    └────────────────────────────────────────────────┘
                        ↓
    ┌────────────────────────────────────────────────┐
    │ 2. REASON                                      │
    │    - Is the goal achieved?                     │
    │    - If not, what should I do next?            │
    │    - What tools do I need?                     │
    └────────────────────────────────────────────────┘
                        ↓
                ┌───────────────┐
                │ Goal complete?│
                └───────────────┘
                    ↙       ↘
                 YES        NO
                  ↓          ↓
             ┌─────────┐  ┌────────────────────────────┐
             │  DONE   │  │ 3. ACT                     │
             └─────────┘  │    - Generate action(s)    │
                          │    - Execute action(s)     │
                          └────────────────────────────┘
                                      ↓
                          ┌────────────────────────────┐
                          │ 4. OBSERVE                 │
                          │    - Get results           │
                          │    - Update knowledge      │
                          └────────────────────────────┘
                                      ↓
                                      ↓
                          ┌───────────────────────────┐
                          │ Loop back to PERCEIVE     │
                          │ (with new information)    │
                          └───────────────────────────┘
                                      ↓
                                (Continue loop...)
```

### Key Components of an Agentic Loop

#### 1. **State Memory**
The loop maintains a "memory" of what has happened:
- Original user request
- Actions taken so far
- Results from each action
- Current progress toward goal

```
Example State After First Iteration:

User Goal: "Assign FY26Q1 epic to me with parent SETI-1089"

State:
  - Actions Taken: [search_issues]
  - Results: ["Found FY26Q1-123"]
  - Progress: "Located the epic, now need to assign and set parent"
  - Next Step: "Update issue FY26Q1-123"
```

#### 2. **Termination Condition**
The loop needs to know when to stop:
- ✅ Task completed successfully
- ✅ User's goal achieved
- ❌ Maximum iterations reached (safety limit)
- ❌ Unrecoverable error occurred

```
Termination Checks:

while (not task_complete) AND (iterations < max_iterations):
    # Run loop
    if AI says "TASK_COMPLETE":
        break
    if critical_error:
        break
```

#### 3. **Feedback Mechanism**
Results flow back to the AI as context:

```
┌─────────────────────────────────────────────────────┐
│             Feedback Flow in Loop                   │
└─────────────────────────────────────────────────────┘

Iteration 1:
  Input to AI: "User wants: Assign epic to me"
  AI Output: ACTION: search_issues
  System Executes → Result: "Found FY26Q1-123"

Iteration 2:
  Input to AI: "User wants: Assign epic to me
                + Previous result: Found FY26Q1-123"  ← FEEDBACK
  AI Output: ACTION: update_issue(key="FY26Q1-123", ...)
  System Executes → Result: "Successfully updated"

Iteration 3:
  Input to AI: "User wants: Assign epic to me
                + Previous results: [Found FY26Q1-123, Updated successfully]"
  AI Output: "TASK_COMPLETE"
```

---

## Information Flow Architecture

### High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   INDIGO AGENTIC SYSTEM                         │
└─────────────────────────────────────────────────────────────────┘

 ┌──────────┐
 │   USER   │
 └──────────┘
      │
      │ Voice/Text Input
      ↓
 ┌─────────────────────────────────────────────────────┐
 │  INDIGO VIEW MODEL                                  │
 │  (Orchestrates the conversation & loop)             │
 └─────────────────────────────────────────────────────┘
      │                                      ↑
      │ User Request                         │ Results & Continuation
      ↓                                      │
 ┌─────────────────────────────────────────────────────┐
 │  AI SERVICE                                         │
 │  (Manages communication with Gemini)                │
 │  - Builds context from state                        │
 │  - Includes action results in prompt                │
 │  - Parses AI response for actions                   │
 └─────────────────────────────────────────────────────┘
      │                                      ↑
      │ Chat Request                         │ Response + Actions
      ↓                                      │
 ┌─────────────────────────────────────────────────────┐
 │  GEMINI AI MODEL                                    │
 │  (Google's LLM)                                     │
 │  - Reasons about task                               │
 │  - Generates actions                                │
 │  - Decides if complete                              │
 └─────────────────────────────────────────────────────┘
      │
      │ Actions to execute
      ↓
 ┌─────────────────────────────────────────────────────┐
 │  CAPABILITY REGISTRY                                │
 │  (Routes actions to appropriate handlers)           │
 └─────────────────────────────────────────────────────┘
      │
      │ Specific action type
      ↓
 ┌─────────────────────────────────────────────────────┐
 │  JIRA CAPABILITY                                    │
 │  (Executes Jira operations)                         │
 │  - search_issues                                    │
 │  - update_issue                                     │
 │  - create_issue                                     │
 │  - etc.                                             │
 └─────────────────────────────────────────────────────┘
      │
      │ API calls
      ↓
 ┌─────────────────────────────────────────────────────┐
 │  JIRA SERVICE                                       │
 │  (Makes HTTP requests to Jira REST API)             │
 └─────────────────────────────────────────────────────┘
      │
      │ HTTP
      ↓
 ┌─────────────────────────────────────────────────────┐
 │  JIRA SERVER                                        │
 │  (External service)                                 │
 └─────────────────────────────────────────────────────┘
```

### Detailed Information Flow: Single Iteration

```
┌────────────────────────────────────────────────────────────────────┐
│            ONE ITERATION OF THE AGENTIC LOOP                       │
└────────────────────────────────────────────────────────────────────┘

Step 1: BUILD CONTEXT
┌────────────────────────────────────────────────┐
│ IndigoViewModel                                │
│  ↓                                             │
│ Collects:                                      │
│  - User's original request                     │
│  - Selected issues in UI                       │
│  - Previous action results (if any)            │
│  - Conversation history                        │
│  - Available projects, sprints, etc.           │
└────────────────────────────────────────────────┘
                    ↓

Step 2: SEND TO AI
┌────────────────────────────────────────────────┐
│ AIService                                      │
│  ↓                                             │
│ Builds System Prompt:                          │
│  "You are Indigo. Here's the context:          │
│   - User wants: [original request]             │
│   - Previous actions: [action history]         │
│   - Results so far: [results]                  │
│   - Available tools: [tool descriptions]       │
│                                                │
│   What should you do next?"                    │
└────────────────────────────────────────────────┘
                    ↓

Step 3: AI REASONS
┌────────────────────────────────────────────────┐
│ Gemini AI                                      │
│  ↓                                             │
│ Analyzes context and decides:                  │
│  "Based on the search result (FY26Q1-123),     │
│   I should now update that issue to:           │
│   - Set assignee to current user               │
│   - Set parent to SETI-1089"                   │
│                                                │
│ Generates response:                            │
│  "I'll update the epic now."                   │
│  ACTION: {"tool": "update_issue", ...}         │
└────────────────────────────────────────────────┘
                    ↓

Step 4: PARSE RESPONSE
┌────────────────────────────────────────────────┐
│ AIService                                      │
│  ↓                                             │
│ Extracts from AI response:                     │
│  - Display text: "I'll update the epic now."   │
│  - Actions: [update_issue action]              │
│  - Task complete flag: false                   │
└────────────────────────────────────────────────┘
                    ↓

Step 5: EXECUTE ACTIONS
┌────────────────────────────────────────────────┐
│ IndigoViewModel → CapabilityRegistry           │
│  ↓                                             │
│ For each action:                               │
│  1. Route to appropriate capability            │
│  2. Execute the operation                      │
│  3. Collect result (success/failure + data)    │
│                                                │
│ Example:                                       │
│  execute("update_issue", {                     │
│    issueKey: "FY26Q1-123",                    │
│    assignee: "shoaib@example.com",            │
│    parent: "SETI-1089"                        │
│  })                                           │
│  → Result: {success: true, message: "Updated"} │
└────────────────────────────────────────────────┘
                    ↓

Step 6: CHECK COMPLETION
┌────────────────────────────────────────────────┐
│ IndigoViewModel                                │
│  ↓                                             │
│ Decision:                                      │
│  - Did AI say "TASK_COMPLETE"? → DONE         │
│  - Were there errors? → Maybe retry or stop    │
│  - Max iterations reached? → STOP             │
│  - Otherwise → CONTINUE TO NEXT ITERATION      │
└────────────────────────────────────────────────┘
                    ↓
            (Loop continues)
```

### Complete Multi-Turn Flow Example

```
┌────────────────────────────────────────────────────────────────────┐
│   COMPLETE EXAMPLE: "Assign that epic to me with parent SETI-1089" │
└────────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════
ITERATION 1: Search for the Epic
═══════════════════════════════════════════════════════════════════

User Input:
  "Assign that epic to me and give it the parent SETI-1089"

Context to AI:
  ┌──────────────────────────────────────────┐
  │ User wants: Assign epic + set parent     │
  │ Previous actions: None                   │
  │ Previous results: None                   │
  │ Available tools: search, update, create...│
  └──────────────────────────────────────────┘

AI Response:
  ┌──────────────────────────────────────────────────────┐
  │ "I'll search for the FY26Q1 management tasks epic    │
  │  to get its key, then I can assign it to you."       │
  │                                                      │
  │ ACTION: {                                           │
  │   "tool": "search_issues",                          │
  │   "args": {                                         │
  │     "jql": "project = FY26Q1 AND type = Epic        │
  │             AND summary ~ 'management tasks'"       │
  │   }                                                 │
  │ }                                                   │
  │                                                      │
  │ [No TASK_COMPLETE flag]                             │
  └──────────────────────────────────────────────────────┘

Execution:
  search_issues executes → Finds issue "FY26Q1-123"

Result:
  ┌──────────────────────────────────────────┐
  │ Success: true                            │
  │ Message: "Found 1 issue"                 │
  │ Data: {                                  │
  │   issues: [{                             │
  │     key: "FY26Q1-123",                  │
  │     summary: "FY26Q1 Management Tasks"  │
  │   }]                                     │
  │ }                                        │
  └──────────────────────────────────────────┘

Loop Status: Task NOT complete → Continue to Iteration 2

═══════════════════════════════════════════════════════════════════
ITERATION 2: Update the Epic
═══════════════════════════════════════════════════════════════════

Context to AI (NOW INCLUDING PREVIOUS RESULT):
  ┌──────────────────────────────────────────────────┐
  │ User wants: Assign epic + set parent             │
  │ Previous actions:                                │
  │   - search_issues (iteration 1)                  │
  │ Previous results:                                │
  │   - search_issues: Found FY26Q1-123              │
  │ Available tools: search, update, create...        │
  │                                                  │
  │ 📝 NEW INFO: The epic key is FY26Q1-123         │
  └──────────────────────────────────────────────────┘

AI Response:
  ┌──────────────────────────────────────────────────────┐
  │ "Perfect! I found the epic FY26Q1-123. Now I'll      │
  │  assign it to you and set the parent to SETI-1089."  │
  │                                                      │
  │ ACTION: {                                           │
  │   "tool": "update_issue",                          │
  │   "args": {                                         │
  │     "issueKey": "FY26Q1-123",                      │
  │     "assignee": "currentUser()",                   │
  │     "parent": "SETI-1089"                          │
  │   }                                                 │
  │ }                                                   │
  │                                                      │
  │ [Still no TASK_COMPLETE flag]                       │
  └──────────────────────────────────────────────────────┘

Execution:
  update_issue executes → Updates FY26Q1-123

Result:
  ┌──────────────────────────────────────────┐
  │ Success: true                            │
  │ Message: "Successfully updated issue"    │
  │ Data: {                                  │
  │   issueKey: "FY26Q1-123",               │
  │   updated: true                          │
  │ }                                        │
  └──────────────────────────────────────────┘

Loop Status: Task NOT complete → Continue to Iteration 3

═══════════════════════════════════════════════════════════════════
ITERATION 3: Verify and Complete
═══════════════════════════════════════════════════════════════════

Context to AI:
  ┌──────────────────────────────────────────────────┐
  │ User wants: Assign epic + set parent             │
  │ Previous actions:                                │
  │   - search_issues (iteration 1)                  │
  │   - update_issue (iteration 2)                   │
  │ Previous results:                                │
  │   - search_issues: Found FY26Q1-123              │
  │   - update_issue: Successfully updated           │
  │ Available tools: search, update, create...        │
  └──────────────────────────────────────────────────┘

AI Response:
  ┌──────────────────────────────────────────────────────┐
  │ "Done! I've assigned epic FY26Q1-123 to you and      │
  │  set its parent to SETI-1089."                       │
  │                                                      │
  │ TASK_COMPLETE                                       │
  └──────────────────────────────────────────────────────┘

Loop Status: TASK_COMPLETE flag detected → STOP LOOP

FINAL RESULT: Success! User's request fully completed.
```

---

## Implementation Breakdown

### Core Data Structures

#### 1. Action Result Structure

```swift
// Represents the outcome of executing a single action
struct ToolResult {
    let success: Bool           // Did the action succeed?
    let message: String?        // Human-readable result message
    let data: [String: Any]?    // Structured data from the action
}

// Example:
ToolResult(
    success: true,
    message: "Found 1 issue",
    data: ["issues": [{"key": "FY26Q1-123", "summary": "..."}]]
)
```

#### 2. Loop State

```swift
// Maintains state across iterations
struct AgenticLoopState {
    let originalRequest: String                  // What the user originally asked for
    var actionHistory: [(AIAction, ToolResult)]  // All actions + their results
    var iterations: Int                          // How many times we've looped
    var isComplete: Bool                         // Has the task been completed?
}

// Example after 2 iterations:
AgenticLoopState(
    originalRequest: "Assign that epic to me with parent SETI-1089",
    actionHistory: [
        (search_issues, ToolResult(success: true, message: "Found 1 issue")),
        (update_issue, ToolResult(success: true, message: "Updated"))
    ],
    iterations: 2,
    isComplete: false
)
```

#### 3. AI Context with Feedback

```swift
// Enhanced context that includes action results
struct AIContext {
    // Existing context fields...
    let currentUser: String
    let selectedIssues: [JiraIssue]
    let availableTools: [Tool]

    // NEW: Feedback from previous actions
    let recentActionResults: [(action: AIAction, result: ToolResult)]?

    // NEW: Original user request for reference
    let userGoal: String?
}
```

### Pseudocode Implementation

#### Main Agentic Loop

```pseudocode
FUNCTION executeAgenticLoop(userRequest):
    // Initialize state
    state = AgenticLoopState(
        originalRequest: userRequest,
        actionHistory: [],
        iterations: 0,
        isComplete: false
    )

    MAX_ITERATIONS = 5  // Safety limit

    // Main loop
    WHILE state.isComplete == false AND state.iterations < MAX_ITERATIONS:
        state.iterations += 1

        // PHASE 1: Build context with action history
        context = buildAIContext(
            userRequest: state.originalRequest,
            actionResults: state.actionHistory,
            selectedIssues: currentlySelectedIssues,
            availableTools: registeredTools
        )

        // PHASE 2: Get AI's next decision
        aiResponse = callAI(context)

        // PHASE 3: Parse response
        actions = parseActions(aiResponse.text)
        taskComplete = checkForCompletionFlag(aiResponse.text)

        // PHASE 4: Execute actions and collect results
        FOR EACH action IN actions:
            showUserMessage("Executing: " + action.tool)

            result = executeAction(action)

            state.actionHistory.append((action, result))

            IF result.success:
                showUserMessage("✓ " + result.message)
            ELSE:
                showUserMessage("✗ " + result.message)
                // Optionally break or retry
            END IF
        END FOR

        // PHASE 5: Check termination
        IF taskComplete OR actions.isEmpty:
            state.isComplete = true
            showUserMessage("Task complete!")
        END IF

        // Safety check
        IF state.iterations >= MAX_ITERATIONS:
            showUserMessage("⚠️ Reached maximum iterations. Stopping.")
            state.isComplete = true
        END IF
    END WHILE

    RETURN state
END FUNCTION
```

#### Building Context with Feedback

```pseudocode
FUNCTION buildAIContext(userRequest, actionResults, selectedIssues, tools):
    context = new AIContext()

    // Basic context
    context.userGoal = userRequest
    context.selectedIssues = selectedIssues
    context.availableTools = tools

    // Add action results if any
    IF actionResults is not empty:
        context.recentActionResults = actionResults
    END IF

    RETURN context
END FUNCTION
```

#### Generating System Prompt with Feedback

```pseudocode
FUNCTION generateSystemPrompt(context):
    prompt = "You are Indigo, an AI assistant for Jira.\n\n"

    // Add user's goal
    prompt += "## User's Goal\n"
    prompt += context.userGoal + "\n\n"

    // Add selected issues context
    IF context.selectedIssues is not empty:
        prompt += "## Currently Selected Issues\n"
        FOR EACH issue IN context.selectedIssues:
            prompt += "- " + issue.key + ": " + issue.summary + "\n"
        END FOR
        prompt += "\n"
    END IF

    // Add action results (feedback loop!)
    IF context.recentActionResults is not empty:
        prompt += "## Previous Actions and Results\n"
        prompt += "You have already taken these actions:\n\n"

        FOR EACH (action, result) IN context.recentActionResults:
            status = result.success ? "✓ Success" : "✗ Failed"
            prompt += "- " + action.tool + ": " + status + "\n"
            prompt += "  Result: " + result.message + "\n"

            IF result.data is not empty:
                prompt += "  Data: " + formatData(result.data) + "\n"
            END IF
        END FOR

        prompt += "\nBased on these results, what should you do next "
        prompt += "to complete the user's goal?\n\n"
    END IF

    // Add available tools
    prompt += "## Available Tools\n"
    FOR EACH tool IN context.availableTools:
        prompt += "- " + tool.name + ": " + tool.description + "\n"
    END FOR

    // Add completion instructions
    prompt += "\n## Instructions\n"
    prompt += "1. Analyze the situation and decide what to do next.\n"
    prompt += "2. Generate action(s) in the format:\n"
    prompt += "   ACTION: {\"tool\": \"tool_name\", \"args\": {...}}\n"
    prompt += "3. When the task is fully complete, end with: TASK_COMPLETE\n"

    RETURN prompt
END FUNCTION
```

#### Executing Actions

```pseudocode
FUNCTION executeAction(action):
    TRY:
        // Route to capability registry
        result = CapabilityRegistry.execute(
            toolName: action.tool,
            arguments: action.args
        )

        RETURN result

    CATCH error:
        RETURN ToolResult(
            success: false,
            message: "Error: " + error.message,
            data: null
        )
    END TRY
END FUNCTION
```

#### Checking for Completion

```pseudocode
FUNCTION checkForCompletionFlag(aiResponseText):
    // Look for completion signal
    IF aiResponseText contains "TASK_COMPLETE":
        RETURN true
    END IF

    // Could also check for other signals:
    // - "Done!"
    // - "Task finished"
    // - "Goal achieved"

    RETURN false
END FUNCTION
```

### State Diagram

```
                    ┌─────────────────┐
                    │  USER REQUEST   │
                    └────────┬────────┘
                             │
                             ↓
                    ┌─────────────────┐
                    │ Initialize State│
                    │ iterations = 0  │
                    │ complete = false│
                    └────────┬────────┘
                             │
                             ↓
          ┌──────────────────────────────────┐
          │  ITERATION START                 │
          │  iterations++                    │
          └──────────────┬───────────────────┘
                         │
                         ↓
          ┌──────────────────────────────────┐
          │  Build Context                   │
          │  - Include action history        │
          │  - Include results               │
          └──────────────┬───────────────────┘
                         │
                         ↓
          ┌──────────────────────────────────┐
          │  Call AI                         │
          │  - Send context                  │
          │  - Get response + actions        │
          └──────────────┬───────────────────┘
                         │
                         ↓
          ┌──────────────────────────────────┐
          │  Execute Actions                 │
          │  - Run each action               │
          │  - Collect results               │
          │  - Update history                │
          └──────────────┬───────────────────┘
                         │
                         ↓
          ┌──────────────────────────────────┐
          │  Check Termination               │
          └──────┬───────────────────┬───────┘
                 │                   │
        ┌────────┴────────┐   ┌──────┴──────────┐
        │ TASK_COMPLETE?  │   │ Max iterations? │
        │ OR no actions?  │   │                 │
        └────────┬────────┘   └──────┬──────────┘
                YES                 YES
                 │                   │
                 ↓                   ↓
          ┌──────────────────────────────────┐
          │  END LOOP                        │
          │  Display final result            │
          └──────────────────────────────────┘

                NO
                 │
                 │
                 └─────────────► Loop back to ITERATION START
```

---

## Specific Application to Indigo

### Integration Points

#### 1. IndigoViewModel Changes

**Current State:**
```swift
// Single-turn execution
func sendMessage() {
    // ... get AI response ...
    if !response.actions.isEmpty {
        for action in response.actions {
            await executeAction(action)  // Execute once and done
        }
    }
}
```

**With Agentic Loop:**
```swift
func sendMessage() {
    // ... get AI response ...
    if !response.actions.isEmpty {
        await executeAgenticLoop(
            initialActions: response.actions,
            userRequest: inputText
        )  // Executes until complete
    }
}

private func executeAgenticLoop(
    initialActions: [AIAction],
    userRequest: String
) async {
    var state = AgenticLoopState(
        originalRequest: userRequest,
        actionHistory: [],
        iterations: 0,
        isComplete: false
    )

    var currentActions = initialActions

    while !state.isComplete && state.iterations < 5 {
        state.iterations += 1

        // Execute current batch
        for action in currentActions {
            let result = await executeAction(action)
            state.actionHistory.append((action, result))
        }

        // Check if we need to continue
        // Ask AI: "Based on results, what's next?"
        let continuation = await askAIForNextSteps(state)

        if continuation.isComplete {
            state.isComplete = true
        } else {
            currentActions = continuation.actions
        }
    }
}
```

#### 2. AIService Enhancement

**Add Method for Continuation:**
```swift
func askForNextSteps(
    originalRequest: String,
    actionHistory: [(AIAction, ToolResult)]
) async -> (actions: [AIAction], isComplete: Bool) {

    // Build context with action results
    let context = await buildContextWithHistory(
        userRequest: originalRequest,
        actionHistory: actionHistory
    )

    // Generate prompt that includes results
    let systemPrompt = buildSystemPromptWithFeedback(context)

    // Ask AI what to do next
    let continuationPrompt = """
    Based on the action results above, is the user's goal complete?
    If not, what should you do next?
    """

    // Get response
    let response = await sendMessageWithContext(
        systemPrompt: systemPrompt,
        userMessage: continuationPrompt,
        conversationHistory: messages
    )

    return (response.actions, response.taskComplete)
}
```

#### 3. Enhanced System Prompt

**Template with Feedback Section:**
```
You are Indigo, an AI assistant for Jira.

## User's Goal
{original_user_request}

## Current Context
- Selected Issues: {selected_issues}
- Available Projects: {projects}
- Available Tools: {tools}

{IF action_history exists:}
## Actions You've Already Taken

{FOR EACH action, result IN action_history:}
Step {index}: {action.tool}
  Arguments: {action.args}
  Result: {result.success ? "✓ Success" : "✗ Failed"}
  Message: {result.message}
  {IF result.data:}
  Data Returned: {result.data}
  {END IF}
{END FOR}

## What to Do Next

Based on the results above, determine if you need to take
additional actions to fully complete the user's goal.

If the goal is FULLY achieved, respond with just:
  "TASK_COMPLETE"

If more work is needed, generate the next action(s):
  ACTION: {"tool": "...", "args": {...}}

{END IF action_history}

## Available Actions

You can use these tools:
- search_issues: Search for Jira issues
- update_issue: Update an existing issue
- create_issue: Create a new issue
... (full tool list)

Remember: Include your reasoning in the response text, then
provide actions on separate lines.
```

### Example Flow in Indigo

```
┌──────────────────────────────────────────────────────────────────┐
│                    User Interaction Flow                         │
└──────────────────────────────────────────────────────────────────┘

1. User speaks into microphone:
   🎤 "Assign that epic to me and give it the parent SETI-1089"

2. Whisper transcribes:
   📝 Text: "Assign that epic to me and give it the parent SETI-1089"

3. IndigoViewModel receives text:
   - Shows user message in chat
   - Calls AIService.sendMessage()

4. AIService (Iteration 1):
   - Builds context (no previous actions)
   - Sends to Gemini
   - Gemini returns: "I'll search for the epic first"
     ACTION: search_issues
   - Returns to ViewModel

5. ViewModel executes action:
   - Shows: "⚡ Executing: search_issues"
   - CapabilityRegistry routes to JiraCapability
   - JiraService makes API call
   - Result: Found FY26Q1-123
   - Shows: "✓ Found 1 issue. Results displayed in main window."

6. ViewModel checks completion:
   - No TASK_COMPLETE flag → Continue loop

7. AIService (Iteration 2):
   - Builds context WITH previous result:
     "Previous action: search_issues found FY26Q1-123"
   - Sends to Gemini
   - Gemini returns: "Now I'll update the epic"
     ACTION: update_issue(key="FY26Q1-123", assignee="...", parent="SETI-1089")
   - Returns to ViewModel

8. ViewModel executes action:
   - Shows: "⚡ Executing: update_issue"
   - Updates FY26Q1-123
   - Shows: "✓ Successfully updated FY26Q1-123"

9. ViewModel checks completion:
   - No TASK_COMPLETE flag → Continue loop

10. AIService (Iteration 3):
    - Builds context with all results
    - Sends to Gemini
    - Gemini returns: "Done! Epic assigned and parent set. TASK_COMPLETE"
    - Returns to ViewModel

11. ViewModel sees TASK_COMPLETE:
    - Shows: "Task complete!"
    - Exits loop
    - Updates UI

Final State:
  ✅ Epic FY26Q1-123 assigned to user
  ✅ Parent set to SETI-1089
  ✅ User sees success message
  ✅ Main window shows updated issue
```

---

## Benefits and Trade-offs

### Benefits

#### 1. **Handles Information Dependencies**
```
❌ Before: Can't assign issue until we know its key
✅ After:  Search for key, THEN assign using that key
```

#### 2. **Error Recovery**
```
Example:
  Iteration 1: Try to update issue → FAILS (permission denied)
  Iteration 2: AI sees failure → Changes strategy → Asks user for help
```

#### 3. **Adaptive Behavior**
```
Example:
  Iteration 1: Search returns multiple matches
  Iteration 2: AI sees ambiguity → Asks user to clarify which one
```

#### 4. **Multi-Step Workflows**
```
Example: "Create a bug for the login issue and assign it to the team lead"
  Iteration 1: Search for team lead's account ID
  Iteration 2: Create bug with found assignee
  Iteration 3: Verify creation, confirm to user
```

#### 5. **Better User Experience**
```
User sees progress in real-time:
  "🔍 Searching for epic..."
  "✓ Found FY26Q1-123"
  "✏️ Updating issue..."
  "✓ Success! Epic assigned and parent set."
```

### Trade-offs

#### 1. **Increased API Costs**
```
Before: 1 API call to AI per user request
After:  N API calls (one per iteration)

Example:
  Simple task: 1-2 iterations (similar cost)
  Complex task: 3-5 iterations (higher cost)

Mitigation:
  - Set MAX_ITERATIONS limit
  - Use cheaper models for continuation checks
  - Cache action results
```

#### 2. **Latency**
```
Before: Response time = 1 AI call + action execution
After:  Response time = N × (AI call + action execution)

Example:
  Simple: 2-3 seconds total (same as before)
  Complex: 5-10 seconds total (longer wait)

Mitigation:
  - Stream updates to user in real-time
  - Show progress indicators
  - Execute actions in parallel when possible
```

#### 3. **Complexity**
```
Before: Linear flow
After:  Loop with state management

New concerns:
  - When to stop the loop?
  - How to handle infinite loops?
  - How to manage conversation context across iterations?

Mitigation:
  - MAX_ITERATIONS safety limit
  - Clear termination conditions
  - Careful state management
```

#### 4. **Debugging Difficulty**
```
Before: Single interaction to trace
After:  Multiple iterations to trace

Questions when debugging:
  - Which iteration failed?
  - Why did the loop continue/stop?
  - What context did the AI have at each step?

Mitigation:
  - Comprehensive logging
  - State snapshots at each iteration
  - Clear error messages
```

### When to Use Agentic Loop vs. Single-Turn

**Use Agentic Loop for:**
- ✅ Multi-step workflows
- ✅ Tasks with information dependencies
- ✅ Complex goals requiring adaptation
- ✅ Scenarios where errors need recovery

**Use Single-Turn for:**
- ✅ Simple, atomic actions
- ✅ Tasks with all information upfront
- ✅ High-performance requirements
- ✅ Cost-sensitive operations

### Performance Metrics

```
┌───────────────────────────────────────────────────────────┐
│           Estimated Performance Characteristics           │
└───────────────────────────────────────────────────────────┘

Metric                 Single-Turn      Agentic Loop
────────────────────────────────────────────────────────────
API Calls             1                2-5
Latency (simple)      1-2s             2-4s
Latency (complex)     N/A (fails)      5-10s
Success Rate          60-70%           85-95%
Cost per request      $0.001           $0.002-$0.005
User satisfaction     ⭐⭐⭐           ⭐⭐⭐⭐⭐

Example Scenarios:
  "Search for my issues"           → Single-turn (1 call, 1s)
  "Assign FY26Q1 epic to me"       → Agentic (2 calls, 3s)
  "Create bug and link to epic"    → Agentic (3 calls, 6s)
  "Close all resolved issues"      → Agentic (4 calls, 8s)
```

---

## Conclusion

The **ReAct pattern** and **agentic loops** transform Indigo from a simple command executor into an intelligent agent that can:

1. **Reason** about what to do
2. **Act** by executing tools
3. **Observe** results
4. **Adapt** its plan based on outcomes
5. **Complete** complex multi-step tasks

This architecture enables Indigo to handle real-world task complexity while maintaining a natural conversation flow with users.

**Key Takeaway:** By giving the AI the ability to see the results of its actions and decide what to do next, we create a system that can handle information dependencies, recover from errors, and adapt to unexpected situations—just like a human assistant would.

---

## Further Reading

- **ReAct Paper:** "ReAct: Synergizing Reasoning and Acting in Language Models" (Yao et al., 2022)
- **Agent Architectures:** "AutoGPT" and "BabyAGI" for examples of agentic systems
- **Tool Use in LLMs:** OpenAI's function calling, Anthropic's tool use
- **Multi-agent Systems:** LangChain, LlamaIndex agent frameworks

---

**Document Version:** 1.0
**Last Updated:** January 6, 2026
**Next Review:** After initial implementation and user testing
