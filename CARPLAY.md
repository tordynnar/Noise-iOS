# CarPlay Development Guide

## Entitlement Requirement

The `com.apple.developer.carplay-messaging` entitlement is required for Noise to appear on the CarPlay home screen. This is a **restricted entitlement** — Apple must approve it.

### Current Status

- The entitlement is declared in `Signal/Signal.entitlements` and `Signal/Signal-AppStore.entitlements`
- The scene lifecycle migration is complete and the code is ready
- **Blocking**: Apple must grant the CarPlay entitlement to the provisioning profile before the app will appear in CarPlay

### How to Get the Entitlement

1. Apply at [developer.apple.com/carplay](https://developer.apple.com/carplay/) (select the **Messaging** category)
2. Once approved, Apple adds `com.apple.developer.carplay-messaging` to your provisioning profile
3. Build with that provisioning profile (Automatic Signing with the approved team)

### Simulator Limitation

Xcode's "Sign to Run Locally" (used for simulator builds) **does not embed** the CarPlay entitlement into the binary, even though it's declared in the `.entitlements` file. This means the Noise icon will not appear on the CarPlay dashboard in the simulator until you build with a provisioning profile that includes the entitlement.

The CarPlay display itself can still be enabled for testing other CarPlay-capable apps.

## Testing in the Simulator

### Enable CarPlay Display

In the Simulator app: **I/O > External Displays > CarPlay**

This opens a CarPlay window alongside the phone simulator.

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

- `com.apple.developer.carplay-messaging` entitlement approved by Apple (see [Entitlement Requirement](#entitlement-requirement) above)
- Provisioning profile that includes the CarPlay entitlement
- Build with Automatic Signing using the approved team (not "Sign to Run Locally")
