# Codex Workflow for Jitouch

This document describes the workflow used when Codex edits, builds, restarts, and verifies the Jitouch app. Use it when moving to another Mac or another Codex session.

## One-Time Context for Codex

Send this project context to Codex at the start of a new session:

```text
Project path: /Users/Zhuanz/Documents/GitHub/Jitouch
Xcode project: /Users/Zhuanz/Documents/GitHub/Jitouch/jitouch/Jitouch/Jitouch.xcodeproj
Scheme: Jitouch
Debug build output: /Users/Zhuanz/Documents/GitHub/Jitouch/build/Debug
App path: /Users/Zhuanz/Documents/GitHub/Jitouch/build/Debug/Jitouch Modern.app

After every code change:
1. Build the app with xcodebuild.
2. Kill the running Jitouch Modern process.
3. Open the freshly built app.
4. If the change affects UI, inspect the app visually.
5. If the change affects gestures, check logs and verify that the gesture is recognized and dispatched.

Do not revert unrelated local changes.
Use apply_patch for manual file edits.
```

## Build and Relaunch

Run this after each code change:

```bash
xcodebuild \
  -project /Users/Zhuanz/Documents/GitHub/Jitouch/jitouch/Jitouch/Jitouch.xcodeproj \
  -scheme Jitouch \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CONFIGURATION_BUILD_DIR=/Users/Zhuanz/Documents/GitHub/Jitouch/build/Debug \
  build

killall "Jitouch Modern" 2>/dev/null || true
sleep 1
open "/Users/Zhuanz/Documents/GitHub/Jitouch/build/Debug/Jitouch Modern.app"
```

If the project is in a different folder on another Mac, replace every `/Users/Zhuanz/Documents/GitHub/Jitouch` path with the new project path.

## Why Codex Can Open and Click the App

There are two separate capabilities:

- Terminal commands: `xcodebuild`, `killall`, `open`, `log show`, `plutil`, `rg`.
- Desktop automation: clicking, typing, reading UI, and screenshots through the Codex Desktop `Computer Use` plugin.

If another Codex session only has terminal access, it can still build and open the app, but it cannot reliably click buttons or inspect the visible UI. In that case, ask it to use shell/log verification, or enable the `Computer Use` plugin in Codex Desktop.

## Gesture Debugging Flow

When gestures do not respond, verify the runtime in this order:

1. Confirm the app is running:

```bash
pgrep -afil "Jitouch Modern"
```

2. Confirm the settings file contains enabled gestures:

```bash
plutil -p ~/Library/Preferences/com.zhuanz.JitouchModern.plist
```

3. Check recent Jitouch logs:

```bash
/usr/bin/log show --style compact --last 3m \
  --predicate 'process == "Jitouch Modern" OR eventMessage CONTAINS[c] "Jitouch:"' \
  | tail -160
```

4. If system logs do not show enough detail, run the app binary directly for temporary stderr logs:

```bash
killall "Jitouch Modern" 2>/dev/null || true
"/Users/Zhuanz/Documents/GitHub/Jitouch/build/Debug/Jitouch Modern.app/Contents/MacOS/Jitouch Modern" 2>&1
```

While that command is running, perform the gesture. Look for logs like:

```text
Jitouch: first multitouch frame from trackpad
Jitouch: recognized trackpad gesture ...
Jitouch: dispatch gesture ... -> ...
Jitouch: no enabled command for gesture ...
```

Interpretation:

- No `first multitouch frame`: device registration or MultitouchSupport callback problem.
- Has `first multitouch frame`, but no `recognized ... gesture`: recognizer threshold/state-machine problem.
- Has `recognized ... gesture`, but `no enabled command`: settings/profile lookup problem.
- Has `dispatch gesture`, but nothing happens: command implementation, accessibility permission, or event posting problem.

## UI Verification Flow

For UI changes, use this sequence:

1. Build and relaunch with the command above.
2. Bring the app to front:

```bash
open "/Users/Zhuanz/Documents/GitHub/Jitouch/build/Debug/Jitouch Modern.app"
```

3. If Codex Desktop has `Computer Use`, ask it to inspect the app window, click the changed controls, and report visual issues.
4. If `Computer Use` is unavailable, manually inspect the app and send Codex a screenshot or describe what is wrong.

## Accessibility Permission

Gesture actions that post keyboard/mouse events usually require Accessibility permission.

On a new Mac:

1. Open System Settings.
2. Go to Privacy & Security > Accessibility.
3. Add and enable `Jitouch Modern.app`.
4. Restart the app:

```bash
killall "Jitouch Modern" 2>/dev/null || true
open "/Users/Zhuanz/Documents/GitHub/Jitouch/build/Debug/Jitouch Modern.app"
```

## Useful Current Project Notes

- Current app name: `Jitouch Modern`
- Current bundle id in the built app: `com.JitouchModern`
- Runtime settings are read from: `~/Library/Preferences/com.zhuanz.JitouchModern.plist`
- Old Jitouch reference source used for gesture behavior: `/Users/Zhuanz/Downloads/Jitouch-main`
- Original gesture implementation reference: `/Users/Zhuanz/Downloads/Jitouch-main/jitouch/Jitouch/Gesture.m`

## Prompt to Reuse

Paste this into a new Codex session:

```text
Read /Users/Zhuanz/Documents/GitHub/Jitouch/CODEX_WORKFLOW.md first.
For this Jitouch project, after every code change, build with xcodebuild, kill the old "Jitouch Modern" process, and open the newly built Debug app.
If UI changes are involved and Computer Use is available, inspect the visible app.
If gesture changes are involved, check Jitouch logs and verify whether the gesture is recognized and dispatched.
Do not stop after editing files; compile and relaunch the app.
```

