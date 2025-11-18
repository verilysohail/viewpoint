#!/bin/bash

# Script to create a proper Xcode project for Viewpoint

echo "Creating Xcode project for Viewpoint..."

# Create temporary directory for Xcode project creation
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

# Create a new Xcode project using a temporary Swift file
cat > main.swift << 'EOF'
import Cocoa
@main
class AppDelegate: NSApplicationDelegate {}
EOF

# We'll need to create the Xcode project manually through Xcode GUI
# This script provides the instructions

cd - > /dev/null

cat << 'EOF'

Unfortunately, creating an Xcode project file from scratch via command line is complex.
Here's the recommended approach:

OPTION 1: Create in Xcode (Recommended - 2 minutes)
=======================================================
1. Open Xcode
2. File → New → Project
3. Select "macOS" → "App"
4. Click "Next"
5. Fill in:
   - Product Name: Viewpoint
   - Team: (your team)
   - Organization Identifier: com.yourname
   - Interface: SwiftUI
   - Language: Swift
   - Uncheck "Use Core Data" and "Include Tests"
6. Click "Next"
7. Save in: /Users/smamdani/code/viewpoint (create new folder "ViewpointApp")
8. Click "Create"

9. Delete the default ContentView.swift and ViewpointApp.swift files

10. Add your source files:
    - Right-click on ViewpointApp folder in project navigator
    - Add Files to "ViewpointApp"
    - Select all files from the Viewpoint/ directory
    - Make sure "Copy items if needed" is UNCHECKED
    - Make sure "Create groups" is selected
    - Click "Add"

OPTION 2: Use the Swift Package (Current Setup)
===============================================
The current Package.swift already works! Just run:
   open Package.swift

This will open in Xcode and you can run it directly.

EOF

echo ""
read -p "Would you like me to provide detailed step-by-step instructions for Option 1? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    cat << 'EOF'

DETAILED STEP-BY-STEP INSTRUCTIONS:
====================================

1. Launch Xcode from Applications or Spotlight

2. In the welcome window, click "Create New Project"
   (Or if Xcode is already open: File → New → Project)

3. In the template chooser:
   - Top tabs: Select "macOS"
   - Template: Click on "App"
   - Click "Next" button

4. In the project options:
   Product Name: Viewpoint
   Team: <Select your development team or leave as None>
   Organization Identifier: com.smamdani (or your preferred identifier)
   Bundle Identifier: <auto-filled as com.smamdani.Viewpoint>
   Interface: SwiftUI (should be default)
   Language: Swift (should be default)
   Storage: None (should be default)
   [ ] Use Core Data (leave unchecked)
   [ ] Include Tests (leave unchecked)

   Click "Next"

5. Choose save location:
   Navigate to: /Users/smamdani/code/viewpoint
   Create new folder: "ViewpointApp"
   [ ] Create Git repository (leave unchecked, we already have one)
   Click "Create"

6. Xcode will create the project and open it

7. Delete the template files:
   In the left sidebar (Project Navigator):
   - Right-click on "ContentView.swift" → Delete → Move to Trash
   - Right-click on "ViewpointApp.swift" → Delete → Move to Trash
   - Right-click on "Assets.xcassets" (optional, keep if you want app icon later)

8. Add our source files:
   - Right-click on the "Viewpoint" folder (blue icon) in the navigator
   - Select "Add Files to 'Viewpoint'"
   - Navigate to: /Users/smamdani/code/viewpoint/Viewpoint
   - Select ALL the folders and files:
     • ViewpointApp.swift
     • ContentView.swift
     • Models folder
     • Services folder
     • Views folder
     • Config folder
   - IMPORTANT: UNCHECK "Copy items if needed"
   - Make sure "Create groups" is selected (not "Create folder references")
   - Under "Add to targets", make sure "Viewpoint" is checked
   - Click "Add"

9. Configure the project:
   - Click on the project name at the top of the navigator
   - Under "Deployment Info":
     • Minimum Deployments: macOS 13.0 or later
   - Under "Signing & Capabilities":
     • Select your team or choose "Sign to Run Locally"

10. Build and run:
    - Press Cmd+R or click the Play button
    - The app should build and launch!

EOF
fi

rm -rf "$TMP_DIR"
