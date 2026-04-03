# CarPlay Development Guide

## Testing in the Simulator

### Enable CarPlay Display

In the Simulator app: **I/O > External Displays > CarPlay**

This opens a CarPlay window alongside the phone simulator. Noise will appear as "Messages" in CarPlay (standard for apps using the `com.apple.developer.carplay-messaging` entitlement).

### Disable CarPlay Display

**I/O > External Displays > Disabled**

### CLI Alternative

You can also toggle CarPlay via AppleScript:

```bash
# Enable
osascript -e '
tell application "Simulator" to activate
delay 0.3
tell application "System Events"
    tell process "Simulator"
        click menu item "CarPlay" of menu of menu item "External Displays" of menu "I/O" of menu bar 1
    end tell
end tell'

# Disable
osascript -e '
tell application "Simulator" to activate
delay 0.3
tell application "System Events"
    tell process "Simulator"
        click menu item "Disabled" of menu of menu item "External Displays" of menu "I/O" of menu bar 1
    end tell
end tell'
```

Note: AppleScript requires accessibility permissions for System Events.

### Screenshot the CarPlay Display

```bash
xcrun simctl io booted screenshot --display=TVOut carplay.png
```

## Architecture

The CarPlay integration uses the UIScene lifecycle with two scene delegates:

- **`NoiseWindowSceneDelegate`** — Manages the main phone window (`UIWindowSceneSessionRoleApplication`)
- **`NoiseCarPlaySceneDelegate`** — Manages the CarPlay interface (`CPTemplateApplicationSceneSessionRoleApplication`)

Both are registered in `Signal/Signal-Info.plist` under `UIApplicationSceneManifest`.

### Key Files

| File | Purpose |
|------|---------|
| `Signal/CarPlay/NoiseCarPlaySceneDelegate.swift` | CarPlay scene connection/disconnection |
| `Signal/CarPlay/CarPlayConversationListController.swift` | Conversation list (up to 20 threads) |
| `Signal/CarPlay/CarPlayMessageController.swift` | Message display (up to 15 messages) |
| `Signal/AppLaunch/NoiseWindowSceneDelegate.swift` | Main window scene delegate |
| `Signal/AppLaunch/AppDelegate.swift` | App initialization, defers window creation to scene delegate |

### How It Works

1. `AppDelegate.didFinishLaunchingWithOptions` runs all non-window initialization (database, logging, background tasks) and stores a `PendingLaunchState`
2. `NoiseWindowSceneDelegate.scene(_:willConnectTo:)` creates the main `OWSWindow` and calls `appDelegate.connectWindow(_:)` to finish setup
3. When CarPlay connects, `NoiseCarPlaySceneDelegate.templateApplicationScene(_:didConnect:)` sets up the conversation list as the root template
4. Tapping a conversation pushes a `CarPlayMessageController` showing recent messages
5. Replying uses SiriKit (`INSendMessageIntent`) via the Intents Extension

### Prerequisites

- `com.apple.developer.carplay-messaging` entitlement (already in entitlements files)
- Apple CarPlay entitlement approval (via the CarPlay developer portal) for App Store distribution
