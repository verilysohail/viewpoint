What Phase 2 Actually Did (December 2025)

  Looking at the commit "Phase 2: Dynamic Intent/Action System with JSON-based tool execution" (cca2fbe), Phase 2 implemented:

  1. Infrastructure/Architecture Layer

  - Capability abstraction (Capability.swift, CapabilityRegistry.swift)
  - Tool protocol with standardized execute interface
  - JSON-based actions (AIAction with tool and args)
  - Dynamic routing via CapabilityRegistry.shared.execute()

  2. Dynamic System Prompt Generation

  - Tools are now described to the AI dynamically from the registry
  - AI generates actions in JSON format: ACTION: {"tool": "...", "args": {...}}

  3. Single-Turn Execution

  // From IndigoViewModel (before my changes)
  if !response.actions.isEmpty {
      Task {
          for action in response.actions {
              await self.executeAction(action)  // Execute all actions
          }
          // STOPS HERE - No loop back to AI!
      }
  }

  What Phase 2 Did NOT Implement

  Phase 2 did not implement the ReAct pattern or feedback loop:

  ❌ No feedback - Action results don't flow back to the AI
  ❌ No multi-turn - AI can't see what happened and decide what to do next
  ❌ No iteration - System executes AI's initial plan and stops

  The Gap (Why Your Epic Assignment Failed)

  With Phase 2 alone:

  User: "Assign that epic to me"

  AI thinks: "I need to search first, then update"
  AI generates: ACTION: search_issues

  System executes: search → finds FY26Q1-123
  System STOPS ❌ (no way to tell AI the result)

  AI never gets to generate:
  ACTION: update_issue (because it doesn't know the key yet)

  What I Just Added (ReAct Pattern)

  The agentic loop on top of Phase 2's infrastructure:

  ✅ Feedback - Results flow back to AI via actionHistory in context
  ✅ Multi-turn - executeAgenticLoop() keeps calling AI until taskComplete
  ✅ Iteration - Loop continues with sendMessageWithActionHistory()

  User: "Assign that epic to me"

  Iteration 1:
    AI: ACTION: search_issues
    Execute → Result: found FY26Q1-123
    
  Iteration 2:
    AI sees result, generates: ACTION: update_issue(key="FY26Q1-123", ...)
    Execute → Result: success

  Iteration 3:
    AI sees success, responds: "Done! TASK_COMPLETE"
    Loop exits ✅

  Why The Confusion?

  The confusion is understandable because:

  1. Phase 2's name ("Dynamic Intent/Action System") sounds comprehensive
  2. The infrastructure was there - All the pieces needed (tools, actions, registry)
  3. The AI was prompted correctly - System prompt includes tools and asks for actions

  But Phase 2 was really about "how actions are defined and executed" (the plumbing), not "how the AI iterates toward a goal" (the intelligence).

  The Layering

  ┌─────────────────────────────────────────────┐
  │  ReAct Pattern (What I Just Added)         │
  │  - Agentic loop                             │
  │  - Feedback to AI                           │
  │  - Multi-turn reasoning                     │
  └─────────────────────────────────────────────┘
                      ↓ uses
  ┌─────────────────────────────────────────────┐
  │  Phase 2 Infrastructure                     │
  │  - Capability/Tool abstraction              │
  │  - JSON action format                       │
  │  - Dynamic routing                          │
  │  - Registry system                          │
  └─────────────────────────────────────────────┘
                      ↓ uses
  ┌─────────────────────────────────────────────┐
  │  Phase 1 Foundation                         │
  │  - JiraService                              │
  │  - Basic AI integration                     │
  │  - Intent parsing (legacy)                  │
  └─────────────────────────────────────────────┘

  So You Were Right To Expect It

  Given Phase 2's ambitious name and the sophisticated infrastructure it built, it's completely reasonable to think it included the feedback loop. But Phase 2 was the foundation that makes ReAct possible, not ReAct itself.

  Think of it this way:
  - Phase 2 = Building a highway system with exits and signs
  - ReAct = Adding GPS navigation that reroutes based on traffic