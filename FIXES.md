# Jira API Fixes

## What Was Fixed

### 1. URL Encoding Issue (Main Problem)
**Problem**: The JQL query wasn't being properly URL-encoded, causing "unsupported URL" errors.

**Solution**: Changed from manual string encoding to using `URLComponents` with `URLQueryItem`, which properly handles all URL encoding automatically.

**Before**:
```swift
let urlString = "\(config.jiraBaseURL)/rest/api/3/search?jql=\(jql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&maxResults=100"
```

**After**:
```swift
var urlComponents = URLComponents(string: "\(config.jiraBaseURL)/rest/api/3/search")
urlComponents.queryItems = [
    URLQueryItem(name: "jql", value: jql),
    URLQueryItem(name: "maxResults", value: "100")
]
let url = urlComponents.url
```

### 2. Configuration File Path
**Problem**: When running from Xcode, the app couldn't find the `.env` file because the working directory is different from the project root.

**Solution**: Added multiple fallback paths to search for the `.env` file:
- Current directory
- Parent directory
- Project root (navigating up from DerivedData)
- Hardcoded development path

### 3. Better Error Logging
**Added**:
- Debug print statements showing the URL being requested
- JQL query logging
- HTTP response status codes
- Error response bodies from Jira API
- Configuration loading verification

## How to Test

### Option 1: Run in Xcode (Recommended)
1. Open `Viewpoint.xcodeproj` in Xcode
2. Press ⌘R to build and run
3. Check the Xcode console for debug output:
   - "Configuration loaded:" message
   - "Fetching issues from:" with the URL
   - "Response status:" showing HTTP status code
   - Number of issues fetched

### Option 2: Run from Command Line
```bash
swift run Viewpoint
```

## Debug Output You Should See

When the app starts successfully, you'll see console output like:
```
Configuration loaded:
  Base URL: https://verily.atlassian.net
  Email: smamdani@verily.health
  API Key present: true
  ENV file path checked: /Users/smamdani/code/viewpoint/.env

Fetching issues from: https://verily.atlassian.net/rest/api/3/search?jql=assignee%20%3D%20currentUser()&maxResults=100
JQL: assignee = currentUser()
Response status: 200
Successfully fetched X issues
```

## What Changed in the Code

### Files Modified:
1. **Viewpoint/Services/JiraService.swift**
   - `fetchMyIssues()`: Fixed URL encoding
   - `fetchSprintInfo()`: Fixed URL encoding
   - Added debug logging throughout

2. **Viewpoint/Config/Configuration.swift**
   - Added multiple .env file search paths
   - Added debug logging for configuration

## Common Issues & Solutions

### Still Getting "unsupported URL"?
- Check the Xcode console for the actual URL being generated
- Verify the Base URL in configuration is correct
- Make sure there are no extra spaces or characters in `.env`

### "No issues" showing up?
- Check console for HTTP status code
- 401 = Authentication failed (check API key)
- 403 = Permission denied (check Jira permissions)
- 404 = Endpoint not found (check Base URL)
- Check that you have issues assigned to you in Jira

### Configuration not loading?
- Look for "Configuration loaded:" in console
- Check which path it found the .env file at
- Verify .env file exists at that location
- Make sure .env has proper format (KEY = "value")

## Jira API Endpoints Used

1. **Search Issues**: `/rest/api/3/search`
   - Uses JQL to filter issues
   - Returns issues with all fields

2. **Get Boards**: `/rest/agile/1.0/board`
   - Agile API (different from core API)
   - Used to find board IDs

3. **Get Sprints**: `/rest/agile/1.0/board/{boardId}/sprint`
   - Agile API
   - Returns sprints for a specific board

## Next Steps

If you're still having issues:
1. Check the Xcode console for specific error messages
2. Verify your Jira API token hasn't expired
3. Test the Jira API directly with curl:
   ```bash
   curl -u "smamdani@verily.health:YOUR_API_KEY" \
     "https://verily.atlassian.net/rest/api/3/search?jql=assignee=currentUser()&maxResults=1"
   ```
