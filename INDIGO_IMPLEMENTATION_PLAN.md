# Indigo AI Assistant - Implementation Plan

## Overview
Indigo is a floating AI assistant window for Viewpoint that combines voice input (via local Whisper) with Claude AI to enable natural language interaction with Jira.

## Design Requirements (Confirmed)

### Window Behavior
- **Floating window** - Stays on top of other windows (like Scribe)
- **Visual style** - macOS Sequoia translucent/vibrancy effect ("liquid glass")
- **Persistence** - Stays open, doesn't close after commands
- **Multi-turn** - Full conversation history, supports follow-up questions

### Results Display
- **Summary in Indigo** - AI response shows in conversation window
- **Auto-refresh main window** - If Jira data changes, main Viewpoint updates automatically

### Input Methods
1. **Text input** - Type commands directly
2. **Voice input** - Click mic → speak → click again → transcription fills text field → user can edit → send

## UI Design

### Window Layout
```
┌─────────────────────────────────────────────────────┐
│ 🟣 Indigo                              [Keep on Top] │ ← Header with toggle
├─────────────────────────────────────────────────────┤
│                                                      │
│  👤 You                                    10:23 AM  │
│  Find my bugs from last week                        │
│                                                      │
│  🤖 Indigo                                10:23 AM  │
│  I found 3 bugs you created in the last 7 days:    │
│  • SETI-820: Login fails on Safari                  │
│  • SETI-818: Dashboard crashes on filter           │
│  • SETI-815: API timeout on large datasets         │
│                                                      │
│  I've updated the main window to show these.       │
│                                                      │
│  👤 You                                    10:24 AM  │
│  Log 2 hours on SETI-820                            │
│                                                      │
│  🤖 Indigo                                10:24 AM  │
│  ✓ Logged 2 hours on SETI-820                      │
│  Total time logged: 2h, Remaining: 6h               │
│                                                      │
│                                                      │
│                                          ↓ Scroll   │
├─────────────────────────────────────────────────────┤
│ [🎤]  Type or speak your command...     [Send ↗]   │ ← Input area
└─────────────────────────────────────────────────────┘
```

### Visual Effects (macOS Sequoia "Liquid Glass")
- **Background**: NSVisualEffectView with `.hudWindow` material
- **Translucency**: Semi-transparent with blur effect
- **Vibrancy**: Content adapts to background
- **Accent color**: Indigo/purple theme
- **Animations**: Smooth transitions for messages appearing

### Message Bubbles
- **User messages**: Right-aligned, indigo background
- **AI messages**: Left-aligned, subtle gray/translucent background
- **System messages**: Centered, italic (e.g., "Loading Whisper model...")
- **Timestamps**: Small, gray, next to each message
- **Status indicators**: ✓ for success, ⚠ for warnings, ✗ for errors

## Technical Architecture

### New Components

#### 1. IndigoWindow.swift
```swift
class IndigoWindow: NSWindow {
    // Floating window with vibrancy
    // Configures visual effect view
    // Manages window level and behavior
}
```

#### 2. IndigoView.swift (Main SwiftUI View)
```swift
struct IndigoView: View {
    @StateObject var viewModel: IndigoViewModel

    var body: some View {
        VStack {
            // Header with "Indigo" title and controls
            // Conversation scroll view
            // Input area (text field + mic button + send button)
        }
        .background(VisualEffectView()) // Vibrancy
    }
}
```

#### 3. IndigoViewModel.swift
```swift
class IndigoViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var keepOnTop: Bool = true

    // References to services
    private let aiService: AIService
    private let whisperService: WhisperService
    private let audioRecorder: AudioRecorder
    private let jiraService: JiraService

    func sendMessage(_ text: String)
    func toggleRecording()
    func processAIResponse()
}
```

#### 4. Message.swift (Data Model)
```swift
struct Message: Identifiable {
    let id: UUID
    let text: String
    let sender: Sender
    let timestamp: Date
    let status: MessageStatus?

    enum Sender {
        case user
        case ai
        case system
    }

    enum MessageStatus {
        case success
        case warning
        case error
        case processing
    }
}
```

#### 5. AIService.swift (Enhanced from original plan)
```swift
class AIService: ObservableObject {
    private var conversationHistory: [AIMessage] = []
    private let vertexAIClient: VertexAIClient

    func processQuery(
        _ query: String,
        context: AIContext,
        model: AIModel,  // Gemini or Claude via Vertex
        onStream: @escaping (String) -> Void  // For streaming responses
    ) async -> AIResponse

    func addToHistory(_ message: AIMessage)
    func clearHistory()
}

enum AIModel: String, CaseIterable {
    case gemini20Flash = "gemini-2.0-flash-exp"
    case gemini15Pro = "gemini-1.5-pro"
    case claude35Sonnet = "claude-3-5-sonnet-v2@20241022"
    case claude3Haiku = "claude-3-haiku@20240307"
}
```

#### 6. VertexAIClient.swift (New)
```swift
class VertexAIClient {
    private let projectID: String
    private let region: String
    private let apiKey: String

    init(projectID: String, region: String, apiKey: String) {
        self.projectID = projectID
        self.region = region
        self.apiKey = apiKey
    }

    func streamCompletion(
        model: AIModel,
        messages: [AIMessage],
        onChunk: @escaping (String) -> Void
    ) async throws -> String {
        // Call Vertex AI unified API
        // Supports both Gemini and Claude models
    }
}
```

#### 7. Scribe Integration Components
**Copy from Scribe:**
- `AudioRecorder.swift` - Audio recording functionality
- `WhisperService.swift` - Local transcription
- Modify for Indigo's needs (embedded in window, not full app)

#### 8. VisualEffectView.swift (SwiftUI wrapper)
```swift
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
}
```

## Settings UI - AI Configuration Tab

### New Tab in Settings Window

Add "AI" tab alongside Connection, Performance, and Logs:

```swift
struct AISettingsTab: View {
    @AppStorage("vertexProjectID") private var projectID: String = ""
    @AppStorage("vertexRegion") private var region: String = "us-central1"
    @AppStorage("selectedAIModel") private var selectedModel: String = AIModel.gemini20Flash.rawValue
    @State private var apiKey: String = ""

    var body: some View {
        Form {
            Section("Vertex AI Configuration") {
                TextField("Project ID", text: $projectID)
                    .help("Your Google Cloud Project ID")

                Picker("Region", selection: $region) {
                    Text("us-central1").tag("us-central1")
                    Text("us-east1").tag("us-east1")
                    Text("europe-west1").tag("europe-west1")
                    Text("asia-northeast1").tag("asia-northeast1")
                }

                SecureField("API Key", text: $apiKey)
                    .help("Google Cloud API Key or Service Account credentials")

                Button("Save Credentials") {
                    // Save to Keychain
                }
            }

            Section("AI Model Selection") {
                Picker("Model", selection: $selectedModel) {
                    Text("Gemini 2.0 Flash (Fast & Cheap)").tag(AIModel.gemini20Flash.rawValue)
                    Text("Gemini 1.5 Pro (Balanced)").tag(AIModel.gemini15Pro.rawValue)
                    Text("Claude 3.5 Sonnet (Best Quality)").tag(AIModel.claude35Sonnet.rawValue)
                    Text("Claude 3 Haiku (Fast)").tag(AIModel.claude3Haiku.rawValue)
                }
                .help("Choose which model Indigo uses for AI operations")
            }

            Section("Usage & Costs") {
                HStack {
                    Text("This month:")
                    Spacer()
                    Text("$0.00")  // TODO: Calculate from tracking
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Tokens used:")
                    Spacer()
                    Text("0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .onAppear {
            // Load API key from Keychain
        }
    }
}
```

### Configuration Storage

```swift
// In Configuration.swift
class Configuration: ObservableObject {
    // Existing Jira config...

    // New: Vertex AI config
    var vertexProjectID: String {
        UserDefaults.standard.string(forKey: "vertexProjectID") ?? ""
    }

    var vertexRegion: String {
        UserDefaults.standard.string(forKey: "vertexRegion") ?? "us-central1"
    }

    var vertexAPIKey: String {
        KeychainHelper.load(key: "vertexAPIKey") ?? ""
    }

    func saveVertexAPIKey(_ key: String) {
        KeychainHelper.save(key: "vertexAPIKey", value: key)
    }
}
```

## Implementation Phases

### Phase 1: Window & UI Foundation (Week 1)
- [ ] Create IndigoWindow class with vibrancy
- [ ] Build IndigoView with message display
- [ ] Add "Launch Indigo" button to main toolbar
- [ ] Implement window management (show/hide, keep on top)
- [ ] Create Message model and conversation display
- [ ] Add basic text input and send functionality

**Deliverable**: Beautiful floating window that can send/receive text messages

### Phase 2: Voice Input Integration (Week 1-2)
- [ ] Copy AudioRecorder from Scribe
- [ ] Copy WhisperService from Scribe
- [ ] Add WhisperKit dependency to Viewpoint
- [ ] Integrate microphone button in input area
- [ ] Implement record → transcribe → fill text field flow
- [ ] Add visual feedback during recording/transcription
- [ ] Handle permissions (mic access)

**Deliverable**: Can speak commands, transcription fills text field

### Phase 3: AI Service Integration (Week 2)
- [ ] Implement AIService with Vertex AI backend
- [ ] Create VertexAIClient for unified model access
- [ ] Add AI Settings tab with:
  - [ ] Google Cloud Project ID
  - [ ] Vertex AI Region
  - [ ] API Key/Service Account credentials (Keychain)
  - [ ] Model selection (Gemini 2.0 Flash, Gemini 1.5 Pro, Claude 3.5 Sonnet, Claude 3 Haiku)
  - [ ] Cost tracking display
- [ ] Build conversation context from history
- [ ] Implement streaming responses (text appears as AI "types")
- [ ] Parse AI responses for Jira operations

**Deliverable**: Can have conversations with Gemini or Claude (via Vertex AI) about Jira

### Phase 4: Jira Operations (Week 2-3)
- [ ] Connect AI intents to JiraService operations
- [ ] Implement search (JQL generation → execute → show results)
- [ ] Implement updates (log work, change status, etc.)
- [ ] Implement creation (parse → create issue → return key)
- [ ] Auto-refresh main window when data changes
- [ ] Show operation results in Indigo conversation

**Deliverable**: Fully functional natural language Jira operations

### Phase 5: Polish & UX (Week 3)
- [ ] Refine vibrancy/translucency effects
- [ ] Add animations for messages appearing
- [ ] Implement markdown rendering in AI responses
- [ ] Add copy button for AI responses
- [ ] Show issue links as clickable (opens in browser)
- [ ] Add keyboard shortcuts (⌘Return to send, ⌘K to focus input)
- [ ] Error handling and user-friendly messages
- [ ] Loading states and progress indicators
- [ ] Cost tracking display

**Deliverable**: Production-ready Indigo assistant

## Conversation Context Strategy

### What AI Knows
```swift
struct AIContext {
    // From conversation history
    let previousMessages: [Message]

    // From Viewpoint state
    let currentUser: String
    let selectedIssues: [JiraIssue]
    let currentFilters: IssueFilters
    let visibleIssues: [JiraIssue]

    // From configuration
    let availableProjects: [String]
    let availableSprints: [JiraSprint]
    let availableEpics: [String]

    // From recent operations
    let lastSearchResults: [JiraIssue]?
    let lastCreatedIssue: String?
}
```

### Multi-Turn Examples
```
User: "Find my bugs from last week"
AI: "I found 3 bugs you created in the last 7 days: SETI-820, SETI-818, SETI-815"

User: "Log 2 hours on the first one"  ← References "first one" from previous
AI: "Logged 2 hours on SETI-820"

User: "What about the second one?"     ← References "second one"
AI: "SETI-818 is 'Dashboard crashes on filter'. Would you like to log time on it?"
```

## Visual Polish Details

### Colors
- **Primary accent**: Indigo (#4F46E5)
- **User messages**: Indigo gradient
- **AI messages**: Translucent white/gray
- **Success**: Green
- **Warning**: Orange
- **Error**: Red

### Typography
- **Headers**: SF Pro Display, Bold
- **Messages**: SF Pro Text, Regular
- **Code/Issue keys**: SF Mono
- **Timestamps**: SF Pro Text, Small, Secondary

### Animations
- **Message appearance**: Slide up with fade-in
- **Recording pulse**: Subtle scale animation on mic button
- **Processing**: Typing indicator (three dots animating)
- **Window open**: Smooth scale + fade in from toolbar button

### Window Dimensions
- **Initial size**: 500w × 700h
- **Minimum size**: 400w × 500h
- **Resizable**: Yes
- **Position**: Remember last position, or center of screen on first launch

## Integration with Existing Code

### Main App Changes
```swift
// In ContentView.swift toolbar:
ToolbarItem(id: "indigo", placement: .automatic) {
    Button(action: { showIndigo.toggle() }) {
        Label("Launch Indigo", systemImage: "waveform.circle.fill")
    }
    .foregroundColor(.indigo)
}
```

### Window Management
```swift
// In ViewpointApp.swift:
@main
struct ViewpointApp: App {
    @StateObject var jiraService = JiraService()
    @StateObject var indigoManager = IndigoManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jiraService)
        }

        // Indigo window (on-demand)
        Window("Indigo", id: "indigo") {
            IndigoView()
                .environmentObject(jiraService)
                .environmentObject(indigoManager)
        }
        .defaultSize(width: 500, height: 700)
        .windowStyle(.hiddenTitleBar)
    }
}
```

### Auto-Refresh Main Window
```swift
// In IndigoViewModel after Jira operation:
await jiraService.fetchMyIssues()  // Refresh main list
await MainActor.run {
    addMessage(Message(
        text: "✓ Updated. Main window refreshed.",
        sender: .ai
    ))
}
```

## Whisper Integration

### Dependencies
Add to Package.swift or Xcode project:
- WhisperKit (same as Scribe uses)
- Model downloads automatically (~3GB first time)

### Performance Considerations
- WhisperKit runs locally on device (Neural Engine if available)
- First launch: Model download + setup (~1-2 minutes)
- Transcription: ~2-5 seconds for typical voice command
- Memory: ~500MB while active

### User Experience
1. First time clicking mic: "Downloading Whisper model (3GB, one-time)..."
2. Subsequent uses: Instant recording start
3. Visual feedback: Waveform or pulse animation while recording
4. Status: "Transcribing..." while processing

## Error Handling

### Graceful Failures
- **Whisper fails**: "Couldn't transcribe. Please type your command."
- **Claude API fails**: "AI service unavailable. Please try again."
- **Jira API fails**: "Couldn't complete operation: [specific error]"
- **No results**: "No issues found matching your criteria."

### User Guidance
- **Ambiguous query**: AI asks clarifying question
- **Invalid operation**: AI explains what went wrong
- **Missing permissions**: Clear instructions to fix

## Cost Management

### Display in Indigo
- Show estimated cost for current conversation
- Warning when approaching budget limits
- Model selection in Settings with pricing guidance:
  - Gemini 2.0 Flash: Fastest & cheapest
  - Gemini 1.5 Pro: Balanced performance & cost
  - Claude 3 Haiku (Vertex): Fast Claude model
  - Claude 3.5 Sonnet (Vertex): Best quality, highest cost

### Pricing (Approximate via Vertex AI)
- **Gemini 2.0 Flash**: ~$0.075/$0.30 per 1M tokens (input/output)
- **Gemini 1.5 Pro**: ~$1.25/$5.00 per 1M tokens
- **Claude 3 Haiku**: ~$0.25/$1.25 per 1M tokens
- **Claude 3.5 Sonnet**: ~$3.00/$15.00 per 1M tokens

### Optimization
- Default to Gemini 2.0 Flash for simple queries (JQL generation, basic searches)
- Use Gemini 1.5 Pro or Claude 3.5 Sonnet for complex operations (issue creation, multi-step tasks)
- Allow user to override model selection in Settings
- Prune conversation history after N messages to reduce token usage
- Cache common query patterns and responses

## Security & Privacy

### API Keys & Credentials
- Google Cloud credentials stored in Keychain (like Jira credentials)
- Vertex AI Project ID and Region stored in UserDefaults
- Never logged or transmitted except to Google Cloud Vertex AI
- Supports both API Key and Service Account authentication

### Whisper (Local)
- All transcription happens on-device
- Audio files immediately deleted after transcription
- No data sent to cloud for voice processing

### Conversation History
- Stored in memory only (not persisted to disk)
- Cleared when window closes (optional setting to persist)
- User can manually clear history

## Testing Strategy

### Unit Tests
- Message rendering
- Conversation history management
- Context building for AI

### Integration Tests
- Voice → transcription → text field
- AI response → Jira operation → main window refresh
- Multi-turn conversation context

### User Testing
- Voice accuracy with different accents
- AI understanding of common queries
- Window behavior (floating, resizing, positioning)

## Future Enhancements

### Advanced Voice
- Wake word support ("Hey Indigo...")
- Continuous listening mode
- Voice feedback (text-to-speech responses)

### Smarter AI
- Learn from user patterns
- Suggest common operations
- Proactive notifications ("You haven't logged time today")

### Collaboration
- Share conversations
- Templates for common queries
- Export chat history

## Success Metrics

1. **Adoption**: % of Jira operations done via Indigo
2. **Voice usage**: % of commands via voice vs typing
3. **Conversation length**: Average turns per session
4. **Accuracy**: % of commands executed correctly first try
5. **User satisfaction**: Feedback and usage patterns

## Open Questions

1. **Conversation persistence**: Save history between sessions or start fresh?
2. **Window hotkey**: Global shortcut to show/hide Indigo?
3. **Voice feedback**: Should AI responses be read aloud?
4. **Multi-window**: One Indigo per Viewpoint window or single global instance?

---

**Estimated Timeline**: 3 weeks for full implementation
**Key Dependencies**: WhisperKit, Anthropic API
**Primary Risk**: Voice transcription accuracy in noisy environments
**Mitigation**: Allow text editing after transcription, provide typing alternative
