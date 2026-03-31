# Indigo Patterns and Extensibility

_Design conversation, 2026-03-30_

This document captures a conversation exploring how the Indigo AI assistant handles instructions, what "patterns" are, and how the architecture should evolve to support extensibility.

---

## How does Indigo know what to do?

The AI's ability to act comes from two sources:

### 1. The System Prompt (rebuilt every message)

Constructed in `AIService.buildSystemPrompt()` (line 234), it includes:
- Identity ("You are Indigo, an AI assistant for Jira...")
- Selected issues with full details (description, comments, changelog)
- Current Jira context (projects, statuses, resolutions, sprints, filters)
- The tool list from `CapabilityRegistry.generateToolsPrompt()`
- The action format (`ACTION: {"tool": "...", "args": {...}}`)
- General guidelines (time logging conversions, JQL tips, etc.)

### 2. The 15 Jira Tools

Defined in `JiraCapability.swift`, each one is a Swift class conforming to the `Tool` protocol (`Capability.swift`) and calling `JiraService` methods. These are the only operations the AI can perform. They are registered at startup via `CapabilityRegistry`.

The full flow for a user message:

1. User types & sends -> `IndigoViewModel.sendMessage()` creates Message and calls AIService
2. Context gathered -> `buildContext()` fetches selected issues, available Jira data
3. System prompt built -> `buildSystemPrompt()` assembles identity, tools, context
4. Message sent to Vertex AI -> `streamGenerateContent` streams response
5. Response parsed -> `parseActions()` looks for `ACTION: {...}` lines
6. ReAct loop enters -> `executeAgenticLoop()` runs actions, feeds results back to AI
7. Loop continues until `TASK_COMPLETE` or max 5 iterations

---

## The "cancel issue" problem

Canceling a Jira issue in our instance requires a specific 3-step process:

1. Ensure the issue is In Progress -- if Closed, reopen with transition 121; if New, move to In Progress with transition 11
2. Set the resolution to "Canceled" via a direct field update
3. Close the issue with transition 51

This fails when the AI tries it on its own because it lacks the domain-specific knowledge (transition IDs, ordering requirements). However, when given these steps as natural language instructions, the AI successfully mapped them to existing tools (`change_status`, `update_issue`) and executed them via the ReAct loop.

**Key insight:** The AI doesn't need new tools for complex workflows. It needs domain knowledge it can't infer -- specific transition IDs, field formats, preconditions. The LLM handles the reasoning and tool orchestration.

---

## What are "patterns"?

Patterns are **domain knowledge with constraints** -- not rigid scripts. They fill in gaps the LLM can't infer about the specific Jira instance, while leaving the LLM free to reason about execution.

A pattern has:
- **Name:** "Cancel Issue"
- **When:** "The user asks to cancel, void, or abandon an issue"
- **Knowledge:** Free-text instructions covering the domain-specific facts (transition IDs, field formats, preconditions, ordering requirements)

The knowledge field is free text because that's what works. The reliability comes from the LLM always having that knowledge (injected into the prompt), not from forcing a rigid execution path.

If a pattern is consistently unreliable even with good instructions, that's when it should be promoted to a dedicated tool with deterministic Swift code -- like the existing 15 tools in `JiraCapability.swift`.

---

## Current architecture problems identified

### 1. System prompt is hardcoded in Swift

The entire system prompt is built from string literals in:
- `AIService.buildSystemPrompt()` (lines 234-352)
- `CapabilityRegistry.generateToolsPrompt()` (lines 82-189)

Any change to prompt wording or workflow patterns requires a code change, rebuild, re-sign, and notarization.

### 2. Tool descriptions are duplicated

`generateToolsPrompt()` contains a hand-written string describing all 15 tools, but each tool already has `name`, `description`, and `parameters` defined via the `Tool` protocol. `generateToolsSchema()` (line 76) already generates structured output from these properties, but `generateToolsPrompt()` ignores it.

The tool prompt text should be generated from the `Tool` protocol -- one source of truth.

### 3. No persistent workflow knowledge

There is no storage system for multi-step workflow instructions. Knowledge given in a chat session is lost when the session ends.

### 4. No context caching

The system prompt is sent in full with every request via the Vertex AI API. The static portions (identity, tools, patterns, guidelines) could be cached using Vertex AI's context caching feature for reduced cost and latency.

---

## Planned changes

### Externalize non-code-derived prompt content

The identity, behavioral guidelines, and workflow patterns should be loaded from external files at runtime, not hardcoded in Swift.

Tool descriptions should remain generated from code (the `Tool` protocol), since they're tied to actual implementations.

### Workflow Patterns management UI

A CRUD interface for managing workflow patterns:
- List existing patterns
- Create new patterns (name, trigger, knowledge instructions)
- Edit patterns
- Delete patterns

Patterns are stored persistently and injected into the system prompt at runtime.

### Tools reference UI

A read-only companion view showing all registered tools, their descriptions, and parameters. Generated from the `Tool` protocol definitions so it's always in sync. Lives alongside the patterns UI -- patterns are "how" (learned workflows), tools are "what" (available operations).

### Tool use highlighting in chat

When the AI executes a tool during a conversation, it should be visually called out in the message flow so the user can see what's happening under the hood.

### Vertex AI context caching

Split the system prompt into static (cacheable) and dynamic (per-request) portions. Cache the static prefix using Vertex AI's `cachedContents` API for reduced cost and latency.

Cacheable: identity, tool definitions, workflow patterns, guidelines.
Not cacheable: selected issues, Jira context, action history, conversation history.

---

## Full Conversation Transcript

The following is the complete conversation that led to the design decisions above.

---

### User

> Explain to me what patterns are in the context of this app when it comes to the Indigo assistant?

### Assistant

In Viewpoint, "patterns" refers to the ReAct (Reasoning + Acting) pattern -- the architectural loop that powers the Indigo AI assistant's multi-step task execution. It's not a data model you store; it's how Indigo thinks and acts.

#### How it works

The ReAct pattern is a loop with three phases:

1. **Reason** -- The AI analyzes the situation and decides what to do
2. **Act** -- It generates actions (tool calls like `search_issues`, `update_issue`)
3. **Observe** -- The system executes the actions, and the results feed back to the AI

This loop repeats until the task is complete (or hits a safety limit of 5 iterations).

#### Why it matters

Without this pattern (the old single-turn approach), the AI had to plan everything upfront. It couldn't handle dependent operations like "assign that epic to me and give it the parent SETI-1089" -- because it would need to search for the epic first, then use the result to update it.

With ReAct, each iteration builds on the last:
- **Iteration 1:** AI searches for the epic -> gets back `FY26Q1-123`
- **Iteration 2:** AI updates `FY26Q1-123` with assignee and parent -> success
- **Iteration 3:** AI confirms task is complete -> loop ends

#### Key implementation points

- **`IndigoViewModel.swift:278-404`** -- The `executeAgenticLoop()` method runs the loop, accumulating action history
- **`AIService.swift:184-231`** -- Builds context including action history so the AI can see what already happened
- **`AIService.swift:259-314`** -- Generates a system prompt that includes previous action results, so the AI can reason about next steps
- **`IndigoModels.swift:98-111`** -- Defines `AIAction` (tool + args) and `ToolResult` (success/message/data)

#### Safety guardrails

The pattern includes confirmation dialogs for bulk operations (>5 issues), destructive operation checks, a cancellation/stop button, and the max-iterations cap to prevent runaway loops.

---

### User

> So are multiple things that define what Indigo should do when given an instruction? Like when I say "Close this issue", is there somewhere where it knows what API calls to make to Jira?

### Assistant

Yes, there are three layers that define what Indigo can do:

#### 1. Tool definitions (`Viewpoint/Capabilities/JiraCapability.swift`)

Each Jira operation is a concrete `Tool` class -- `ChangeStatusTool`, `SearchIssuesTool`, `AssignIssueTool`, etc. (15 total). Each defines:
- A **name** (e.g. `"change_status"`)
- **Parameters** it accepts (e.g. `issueKey` + `newStatus`)
- An **`execute()`** method that calls the actual `JiraService` API

So when you say "close this issue", the `ChangeStatusTool` is what actually calls `jiraService.updateIssueStatus(issueKey:newStatus:)`.

#### 2. The system prompt (`CapabilityRegistry.swift:82-188`)

The `generateToolsPrompt()` method produces a text block that gets injected into the AI's system prompt. It lists every tool with its name, description, and parameters in a format the LLM can understand. This is how the AI knows that `change_status` exists and what arguments it needs.

The `generateActionFormatPrompt()` method tells the AI how to invoke tools -- by emitting `ACTION: {"tool": "change_status", "args": {"issueKey": "SETI-123", "newStatus": "Done"}}` lines in its response.

#### 3. The Capability Registry (`CapabilityRegistry.swift`)

A singleton that ties it all together. At app startup, the `JiraCapability` (which bundles all 15 tools) is registered. When the AI emits an `ACTION:` line, the registry looks up the tool by name and calls its `execute()` method.

#### The full flow for "Close this issue"

1. Your message + system prompt (including tool list) goes to the AI
2. AI responds with: `ACTION: {"tool": "change_status", "args": {"issueKey": "SETI-123", "newStatus": "Done"}}`
3. `AIService` parses the `ACTION:` line into an `AIAction`
4. `IndigoViewModel` passes it to `CapabilityRegistry.execute()`
5. Registry finds `ChangeStatusTool`, calls its `execute()`
6. `ChangeStatusTool` calls `jiraService.updateIssueStatus()`
7. The result feeds back into the ReAct loop

In short: **`JiraCapability.swift`** is the file that defines everything Indigo can do with Jira, and `CapabilityRegistry` is what makes those tools discoverable by the AI and executable at runtime.

---

### User

> Okay so when I say "Cancel this issue", it fails consistently. That's because the cancel issue thing isn't straightforward; it's a three-step process.
>
> 3-step process:
>
> 1. Ensure the issue is In Progress -- if it's Closed, reopen it first with transition 121; if it's in New, move it to In Progress with transition 11
> 2. Set the resolution to "Canceled" via a direct field update:
>    PUT /rest/api/3/issue/{key}
>    {'fields': {'resolution': {'name': 'Canceled'}}}
> 3. Close the issue with transition 51 (Close from In Progress)
>
> So how would I "train" the assistant on something like this?

### Assistant

There are two options:

**Option A: Add a dedicated `cancel_issue` tool (recommended)** -- Create a single tool that encapsulates the 3-step process. The AI just says `ACTION: {"tool": "cancel_issue", "args": {"issueKey": "SETI-123"}}` and the tool handles the complexity internally.

**Option B: Teach the AI via the system prompt** -- Add workflow instructions to the system prompt in `CapabilityRegistry.generateToolsPrompt()` explaining the steps. But this is fragile -- the AI would need to use `update_issue` for the resolution field and `change_status` for transitions, and `change_status` matches by name not transition ID, so it might pick the wrong transition.

**Option A is the better path.**

---

### User

> When I gave the Agent this list, it was able to follow it just fine.

### Assistant

Got it -- so the system prompt approach works. You just need to embed those instructions somewhere the AI always sees them.

The right place is in `CapabilityRegistry.generateToolsPrompt()` at `Viewpoint/Capabilities/CapabilityRegistry.swift:82`. You'd add a workflows section after the tool listings.

---

### User

> No. Let's talk about general patterns like this. Where are they stored and in what format?

### Assistant

There's no existing pattern/workflow storage system in the app. Right now, the only "instructions" the AI gets are the tool descriptions hardcoded in `CapabilityRegistry.generateToolsPrompt()`. There's no concept of multi-step workflow recipes stored anywhere.

---

### User

> So how does it know how to create a new issue?

### Assistant

It doesn't need a workflow for that -- it's a single tool call. The AI reads the tool list in the system prompt and sees `create_issue` with its parameters. The LLM already knows how to map "create a new bug for the SETI project called 'Fix login'" to `ACTION: {"tool": "create_issue", "args": {"project": "SETI", "summary": "Fix login", "type": "Bug"}}`. That's just what LLMs do -- they understand the intent and match it to the tool definition.

The "cancel issue" problem is different because it's domain-specific procedural knowledge that no LLM would know -- your Jira instance requires specific transition IDs in a specific order.

---

### User

> That... doesn't make sense. We built this app. Did we build the tool?

### Assistant

You're right -- yes, you built the `CreateIssueTool` in `JiraCapability.swift:71-136`. It's a Swift class with an `execute()` method that calls `jiraService.createIssue(fields:)`. And you wrote the description of it in `CapabilityRegistry.generateToolsPrompt()` so the AI knows it exists.

So the AI knows how to create an issue because you explicitly taught it at two levels:

1. **The tool implementation** -- the Swift code that actually calls the Jira API
2. **The prompt description** -- the text that tells the AI the tool exists and what parameters it takes

Either way, you're the one defining what Indigo can do. Nothing is "automatic."

---

### User

> So if nothing is automatic, when I gave it the steps to cancel, it did so by itself?

### Assistant

You're right, I was contradicting myself. The AI did figure out how to use the existing tools -- `change_status`, `update_issue` -- to execute the steps you described. The ReAct loop handled the orchestration automatically.

So the LLM's reasoning is automatic. What it was missing was the domain knowledge -- the specific transition IDs, the order of operations, the resolution field format. Once you gave it that, it mapped the steps to existing tools on its own.

Which means "patterns" are really just **domain knowledge injected into the prompt**. Not new tools, not new code -- just instructions that fill in the gaps the LLM can't infer about your specific Jira setup.

---

### User

> I don't like that you're vacillating back and forth. Confirm the way this app works first. Do a deep dive into the code, not the docs. Spin up subagents if you have to but I want you to understand EXACTLY how the assistant handles the whole thing.

### Assistant

_[Deep code analysis was performed across `AIService.swift`, `IndigoViewModel.swift`, `IndigoModels.swift`, `CapabilityRegistry.swift`, `Capability.swift`, and `JiraCapability.swift`.]_

There is no pattern storage system. The AI's ability to do things comes from exactly two sources:

**1. The System Prompt** -- rebuilt every message in `AIService.buildSystemPrompt()`, it includes identity, selected issues with full details, current Jira context, the tool list, the action format, and general guidelines.

**2. The 15 Jira Tools** -- defined in `JiraCapability.swift`, registered via `CapabilityRegistry`, executed when the AI emits `ACTION:` lines.

When the user told the AI the cancel steps in chat, the AI used the ReAct loop to chain `change_status` and `update_issue` calls. The LLM reasoned through the steps and mapped them to existing tools. It didn't need new tools -- it needed domain knowledge about the specific Jira instance's transition IDs and required order of operations.

There is currently no place where multi-step workflow instructions are stored. That knowledge would need to be added to the system prompt to make it permanent.

---

### User

> This means that in the process of building out the capabilities of Indigo, we'll keep making that system prompt bigger and bigger and bigger. That may not be a problem since Gemini 3.1 has a million token context window, but that seems awfully wasteful. Could some of those tokens be cached?

### Assistant

Yes, Vertex AI supports context caching. The system prompt has a clear split:

**Cacheable (static across requests):** Identity, tool definitions, workflow patterns, guidelines.

**Not cacheable (changes per request):** Selected issues, Jira context, action history, conversation history.

The static parts would go into a cached content object via the `cachedContents` API, valid for a configurable TTL. Cached tokens are billed at a 75% discount.

Currently the app calls Vertex AI directly via `streamGenerateContent` in `VertexAIClient.swift`, and the system prompt is sent as a regular user message every request -- no caching at all.

---

### User

> Let's think this through. Implementing this is one step in making this app more extensible. But let me ask you this, where is the system prompt right now? Is it embedded in the code itself?

### Assistant

Yes. The entire system prompt is hardcoded in two places:

1. `AIService.buildSystemPrompt()` (lines 234-352)
2. `CapabilityRegistry.generateToolsPrompt()` (lines 82-189)

Every bit of it is Swift code. To change a single word in the prompt -- or add a workflow pattern -- you'd have to modify the source, recompile, and redistribute the app.

---

### User

> Do you think that's a good design choice?

### Assistant

No. It means every prompt change requires a code change, a rebuild, and (given the notarization pipeline) a full re-sign and distribution cycle. That's fine for a prototype, but now that the app needs workflow patterns and prompt iteration, those are content changes, not code changes.

The system prompt should live in external files loaded at runtime. The tool definitions in `CapabilityRegistry` are a different case -- those are tied to actual Swift implementations. But even there, the prompt text describing them could be generated from the `Tool` protocol's existing properties rather than being a separate hardcoded string (which `generateToolsSchema()` already does, but `generateToolsPrompt()` ignores).

---

### User

> But why would you separate the prompt text describing the tools from the tool protocol's existing setup?

### Assistant

You wouldn't. The tool definitions should be generated from the `Tool` protocol properties that already exist. The current `generateToolsPrompt()` is just a hand-maintained duplicate of information that's already in the code.

The things that should be externalized are the parts that aren't derived from code: the identity, behavioral guidelines, and workflow patterns.

---

### User

> I want them not just to be externalized, but stored and accessed by the application in such a way that we have a separate interface for viewing the existing workflow patterns, editing them, deleting them, and adding new ones.

### Assistant

That means patterns become a first-class managed resource in the app:

1. **A data model** -- what defines a pattern (name, trigger, instructions)
2. **Persistent storage** -- where they live on disk
3. **A management UI** -- a view to list, create, edit, and delete patterns
4. **Prompt integration** -- the system prompt builder loads all patterns at runtime and injects them

---

### User

> That's a tough one. In our initial examination, we determined that the LLM was able to map intent to the existing tools, stacking them and using them in a way that fulfilled the request by the end user. I don't want to lose that, but at the same time, I understand that the more deterministic we make this thing, the better we are going to be able to provide structure, predictability, and reliability. So the question becomes, what is the best amalgamation? What approach gives us the reliability of deterministic code via discrete typed steps, specific tool references, etc., without losing the creativity of the LLM's capability of putting tools together when it needs to?

### Assistant

The answer is in what you actually did when you taught it to cancel. You didn't say "call `change_status`, then call `update_issue`, then call `change_status` again." You said:

1. **Ensure** the issue is In Progress -- if Closed, use transition 121; if New, use transition 11
2. **Set** the resolution to Canceled -- here's the exact API shape
3. **Close** with transition 51

That's not a script. It's **domain knowledge with constraints**. You told it what must be true at each stage and gave it the specific details it couldn't infer (transition IDs, field format). But you left it to the LLM to figure out that if the issue is already In Progress, it skips step 1. Or if something fails, it can reason about why.

So the pattern model isn't "steps to execute" -- it's **knowledge the LLM needs but can't infer, plus constraints on ordering and prerequisites**. The LLM still does the planning and tool selection.

A pattern would have:
- **Name:** "Cancel Issue"
- **When:** "The user asks to cancel, void, or abandon an issue"
- **Knowledge:** The domain-specific facts -- transition IDs, field formats, preconditions -- written as natural language instructions to the AI

The structured part is the metadata -- name, trigger, categorization -- which powers the management UI. The creative part stays as prose instructions that the LLM interprets in context.

If a pattern is consistently unreliable, that's when you promote it to a dedicated tool with deterministic code. But you start with knowledge, and only harden to code when you have to.

---

### User

> Okay, I like that approach. That pattern makes sense. With one addition. In addition to having an interface to manage the workflow patterns, what we also need is a way to see what tools are available to the assistant. These don't need to be editable, but I want to make their existence and their use more transparent to the end user. We're going to do this in two ways. First, we are going to highlight tool use when it happens within the Assistant interface. Second, we are going to add an interface that lets us also look at, but not change or edit, the tools and their descriptions.

### Assistant

Three things:

1. **Patterns management UI** -- CRUD for workflow patterns (name, trigger, knowledge instructions). These get injected into the system prompt at runtime.

2. **Tools reference UI** -- A read-only companion view showing all registered tools, their descriptions, and parameters. Generated from the `Tool` protocol definitions, so it's always in sync with what's actually available. No editing because tools are code.

3. **Tool use highlighting in chat** -- When the AI executes a tool during a conversation, it's visually called out in the message flow so you can see what's happening under the hood, not just the result.

The patterns and tools views live together -- probably as tabs or sections in the same window -- since they're both about understanding what Indigo can do. Patterns are "how" (learned workflows), tools are "what" (available operations).
