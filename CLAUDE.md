# Viewpoint

macOS app built with Swift/SwiftUI. Xcode project at `Viewpoint.xcodeproj`.

## Building

- Open in Xcode: `open Viewpoint.xcodeproj` then Cmd+R
- Command line: `swift build && swift run Viewpoint`

## Build, Sign, and Notarize for Distribution

Run `./scripts/build-and-notarize.sh` to archive, sign, notarize, and staple the app.

### Prerequisites

- The **Developer ID Application** certificate (`Developer ID Application: Verily Life Sciences, LLC (LDF8KBK2SH)`) must be in the `dev-secrets` keychain at `~/Library/Keychains/dev-secrets.keychain-db`.
- The Apple ID `smamdani@verily.com` must be signed in to Xcode with the Verily Life Sciences team (`LDF8KBK2SH`).

### How it works

1. Archives the app with the Developer ID cert from the dev-secrets keychain.
2. Exports with `destination: upload` in ExportOptions.plist, which submits to Apple's notary service using Xcode's stored credentials (not `notarytool` profiles).
3. Staples the notarization ticket to the exported `.app`.
4. Verifies with `spctl`.

### Important notes

- Do NOT use `xcrun notarytool` directly -- the Apple ID is a managed account and cannot authenticate via `notarytool store-credentials` or `--apple-id` flags. Use `xcodebuild -exportArchive` with `destination: upload` instead, which leverages Xcode's stored session.
- The project uses **manual signing** with the Developer ID cert for distribution builds. The Xcode project defaults to automatic signing with Apple Development certs for local dev builds.
- The output app lands in `build/export/Viewpoint.app`.

## Indigo AI Assistant Architecture

### How it works
- The AI gets a system prompt (built in `AIService.buildSystemPrompt()`) containing its identity, available tools, selected issue context, and behavioral guidelines.
- Tools are defined as Swift classes conforming to the `Tool` protocol in `Viewpoint/Capabilities/`. The `CapabilityRegistry` registers them at startup and dispatches execution by tool name.
- The AI emits `ACTION: {"tool": "...", "args": {...}}` lines in its response. These are parsed and executed via the ReAct loop in `IndigoViewModel.executeAgenticLoop()`.
- The ReAct loop feeds action results back into the system prompt for the next iteration, up to 5 iterations max.

### Key design principles
- **Tool descriptions should be generated from the `Tool` protocol**, not hand-maintained as duplicate strings. `generateToolsSchema()` already does this; `generateToolsPrompt()` should use it instead of its hardcoded string.
- **Workflow patterns are domain knowledge, not rigid scripts.** They provide facts the LLM can't infer (transition IDs, field formats, ordering constraints) while letting the LLM reason about execution and tool selection. See `docs/INDIGO_PATTERNS_AND_EXTENSIBILITY.md`.
- **Non-code-derived prompt content should be externalized.** Identity, guidelines, and workflow patterns should be loaded from external storage at runtime, not hardcoded in Swift. Tool definitions stay generated from code since they're tied to implementations.
- **Promote to a dedicated tool only when a pattern is consistently unreliable.** Start with prompt-based knowledge; harden to deterministic Swift code only when needed.

### Key files
- `Viewpoint/Services/AIService.swift` — System prompt construction, message sending, response parsing
- `Viewpoint/Services/VertexAIClient.swift` — Vertex AI API client (streaming via `streamGenerateContent`)
- `Viewpoint/ViewModels/IndigoViewModel.swift` — User message handling, ReAct loop, action execution
- `Viewpoint/Models/IndigoModels.swift` — Message, AIAction, AIContext, AIResponse models
- `Viewpoint/Capabilities/Capability.swift` — Tool and Capability protocols
- `Viewpoint/Capabilities/CapabilityRegistry.swift` — Tool registry and prompt generation
- `Viewpoint/Capabilities/JiraCapability.swift` — All 15 Jira tool implementations
