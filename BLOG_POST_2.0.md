# Introducing Viewpoint 2.0: Your AI-Powered Jira Assistant for macOS

**December 3, 2025** • Build 20251203

After months of development and real-world testing, I'm thrilled to announce **Viewpoint 2.0** - a complete reimagining of how you interact with Jira on your Mac.

What started as a simple native Jira viewer has evolved into something much more powerful: an AI-enhanced productivity tool that understands natural language, works at the speed of thought, and stays out of your way until you need it.

---

## The Journey from 1.0 to 2.0

When I built Viewpoint 1.0, the goal was simple: create a fast, native macOS app for viewing Jira issues without the overhead of a web browser. And it worked! But as I used it daily, I kept thinking: *what if Jira could understand what I meant, not just what I typed?*

That question led to **Indigo** - Viewpoint's AI assistant - and everything changed.

---

## 🤖 Meet Indigo: Your Intelligent Jira Assistant

Imagine saying "close these three issues as done and add a comment saying 'shipped in v2.0'" and having it just... work. That's Indigo.

**Indigo isn't a chatbot.** It's an intelligent assistant that understands your Jira workspace:

- "Show me all open bugs in the Mobile project assigned to Sarah"
- "Log 2 hours to PROJ-123 and mark it as in progress"
- "Create a story called 'Add dark mode support' in the current sprint"
- "What changed in SETI-456 over the last week?"

The magic isn't just that it understands natural language - it's that it understands *your* Jira. It knows your projects, your epics, your sprints, your team members. You can say "assign these to Alex" and it knows which Alex. You can say "move this to the redesign epic" and it finds the right epic, even if you got the name slightly wrong.

### Voice Control

Sometimes typing is too much friction. With Indigo's voice transcription, you can literally *speak* your Jira updates:

*"Hey Indigo, show me what I worked on this week"*
*"Log 30 minutes to each of these and mark them done"*
*"Create a bug for that login issue we found"*

It's the closest thing to having a personal Jira assistant.

---

## ⚡ Quick Create from Anywhere

Here's a workflow I use dozens of times a day:

I'm reading code, I spot a bug. Instead of:
1. Opening my browser
2. Navigating to Jira
3. Finding the right project
4. Clicking "Create"
5. Filling out a form
6. Clicking "Submit"

I just click the menu bar icon and type: *"Login button doesn't work on Safari"*

Hit Enter. Done. Issue created, assigned to me, in my default project, with my default component. Two seconds, zero context switching.

**That's the power of Quick Create.** It's always there, it's blazing fast, and it uses smart defaults so you only type what matters: the problem you're solving.

---

## 🎯 Multi-Select & Bulk Operations

Ever needed to update 10 issues at once? In the browser, that's 10 tabs, 10 forms, 10 clicks.

In Viewpoint 2.0, you select the issues (Cmd+Click, just like Finder), and tell Indigo what to do:

*"Add the label 'needs-review' to all of these"*
*"Log 15 minutes to each"*
*"Close these as won't-fix and add a comment explaining why"*

The sliding drawer shows you exactly which issues you've selected, and Indigo handles the rest. It's batch processing that feels like magic.

---

## 📋 Beautiful Issue Details

Sometimes you need more than a list view. You need to see the *whole story*: description, comments, change history, time tracking.

Ask Indigo "show me details for PROJ-123" and a gorgeous Mac-native detail window appears with:

- **Details tab**: Full description, time tracking, components, all the metadata
- **Comments tab**: Every comment, with authors and timestamps
- **History tab**: Complete changelog - who changed what, when

Multiple windows can be open at once, they auto-refresh when you make changes, and they feel completely native to macOS. No browser required.

---

## 🔍 JQL Without the Pain

JQL (Jira Query Language) is powerful but arcane. Most people Google the syntax every time.

Version 2.0's **JQL Builder** makes it effortless:

- Type "pro" → autocomplete suggests "project"
- Hit space → see operators (=, !=, IN, NOT IN)
- Hit space again → see *your actual projects*
- Navigate with arrow keys, select with Enter

No memorization. No Google. No syntax errors. Just start typing and the app guides you.

The best part? **Indigo creates JQL too.** When you ask Indigo for something complex, you can see and edit the exact query it built. It's educational *and* practical.

---

## 🎨 Saved Views: Filters That Remember

We all have our go-to filters:
- "All my open bugs"
- "Current sprint stories"
- "Needs review this week"

Instead of rebuilding these every time, **save them as views**. One click brings back your exact filter configuration, no matter how complex.

Up to 20 saved views, accessible from the toolbar, with smart tracking so you always know which view you're in. It's like browser bookmarks, but for Jira filters.

---

## 💅 The Polish

Version 2.0 isn't just about new features - it's about making *everything* better:

- **Thicker, grabbable dividers** so resizing panes doesn't require pixel-perfect precision
- **Searchable epic filters** because scrolling through 50 epics is nobody's idea of fun
- **Multi-select everything** - epics, assignees, statuses - select as many as you want
- **Windows that stay put** - no more disappearing when you Cmd+Tab to another app
- **Instant startup** - the app loads immediately, fetches data on demand
- **Smart caching** - sprints, epics, summaries - everything persists so you never wait twice

---

## 🔧 Under the Hood

For the technically curious:

- **Modern Jira API**: Migrated to REST API v3 with proper pagination
- **Async/await throughout**: Swift 6 concurrency for smooth, responsive UI
- **Optimistic updates**: UI responds instantly, syncs in background
- **Parallel fetching**: Projects, sprints, and metadata load concurrently
- **Smart caching**: Per-project sprint cache, persistent epic summaries
- **Log rotation**: Automatic cleanup prevents unbounded disk usage
- **Date-based builds**: Build numbers now use YYYYMMDD format for instant identification

---

## 🚀 What's Next

Version 2.0 is a foundation. Some ideas for the future:

- **Keyboard shortcuts** for everything
- **Customizable views** with columns you choose
- **Offline mode** for working without internet
- **Team dashboards** to see what everyone's working on
- **Smart notifications** about issues you care about
- **Deeper AI integration** - predictive sprint planning, automated triage, smart suggestions

But those are for future versions. Right now, I'm focused on making 2.0 rock-solid based on your feedback.

---

## 📦 Download & Get Started

**Viewpoint 2.0** is available now.

**Requirements:**
- macOS 13.0 (Ventura) or later
- Jira Cloud account with API access

**What you'll need:**
- Jira base URL (e.g., yourcompany.atlassian.net)
- Email address
- API token ([create one here](https://id.atlassian.com/manage-profile/security/api-tokens))

First launch? The setup wizard walks you through everything in under a minute.

---

## 💬 Feedback Welcome

I built Viewpoint because I wanted a better way to work with Jira. Version 2.0 is the result of hundreds of hours of development, countless iterations, and real-world testing.

But it's never finished. If you have ideas, bugs, feature requests, or just want to chat about the future of productivity tools, I'm all ears.

**GitHub**: [github.com/verilysohail/viewpoint](https://github.com/verilysohail/viewpoint)
**Issues**: [Report a bug or suggest a feature](https://github.com/verilysohail/viewpoint/issues)

---

## 🎉 Thank You

To everyone who used version 1.x and provided feedback: this is for you. You helped shape what 2.0 became, and I'm incredibly grateful.

Here's to working smarter, not harder.

**— Sohail**
*December 3, 2025*

---

### Appendix: Key Features at a Glance

| Feature | Description |
|---------|-------------|
| **Indigo AI** | Natural language control for all Jira operations |
| **Quick Create** | Menu bar icon for instant issue creation |
| **Multi-Select** | Bulk operations on multiple issues at once |
| **Issue Details** | Native Mac windows with tabs for description, comments, history |
| **JQL Builder** | Intelligent autocomplete for building queries |
| **Saved Views** | Save and restore filter configurations |
| **Voice Control** | Speak your commands to Indigo |
| **Smart Defaults** | Configure defaults for quick issue creation |
| **Epic Search** | Searchable epic filter with summaries |
| **Auto-Refresh** | Detail windows update automatically after changes |
| **Date-Based Builds** | YYYYMMDD format for instant version identification |

---

*Viewpoint 2.0 (Build 20251203) • macOS 13.0+ • © 2025*
