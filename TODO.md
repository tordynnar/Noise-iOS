# TODO

## CarPlay: Scene Lifecycle Migration

### Problem

The CarPlay implementation (`Signal/CarPlay/`) is built but cannot be activated because Signal uses the traditional `UIApplicationDelegate` window management pattern — it creates and manages `self.window` directly in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.

CarPlay requires a `CPTemplateApplicationSceneDelegate`, which is part of the UIScene lifecycle. Attempting to add either:
- A `UIApplicationSceneManifest` in Info.plist, or
- An `application(_:configurationForConnecting:options:)` method in AppDelegate

...opts the entire app into scene lifecycle, which breaks the main window (black screen) because Signal never creates a `UIWindowSceneDelegate` to manage it.

### Root Cause

Signal's `AppDelegate` sets up `self.window = UIWindow(frame: ...)` directly (the pre-iOS 13 pattern). When scene lifecycle is enabled, iOS no longer calls `application(_:didFinishLaunchingWithOptions:)` for window setup — it expects a `UIWindowSceneDelegate` to create the window in `scene(_:willConnectTo:options:)`. Since Signal doesn't have one, no window appears.

### How to Fix

There are two approaches:

#### Option A: Migrate Signal to Scene Lifecycle (recommended, larger effort)

1. Create a `NoiseWindowSceneDelegate: UIWindowSceneDelegate` that:
   - Creates the main `UIWindow` in `scene(_:willConnectTo:options:)`
   - Moves window setup code from `AppDelegate.application(_:didFinishLaunchingWithOptions:)` into the scene delegate
   - Handles `sceneDidBecomeActive`, `sceneWillResignActive`, etc. (moving logic from the corresponding `UIApplicationDelegate` methods)

2. Add `UIApplicationSceneManifest` to `Signal/Signal-Info.plist` with both scene roles:
   ```xml
   <key>UIApplicationSceneManifest</key>
   <dict>
       <key>UIApplicationSupportsMultipleScenes</key>
       <false/>
       <key>UISceneConfigurations</key>
       <dict>
           <key>UIWindowSceneSessionRoleApplication</key>
           <array>
               <dict>
                   <key>UISceneConfigurationName</key>
                   <string>Default</string>
                   <key>UISceneDelegateClassName</key>
                   <string>$(PRODUCT_MODULE_NAME).NoiseWindowSceneDelegate</string>
                   <key>UISceneStoryboardFile</key>
                   <string>Launch Screen</string>
               </dict>
           </array>
           <key>CPTemplateApplicationSceneSessionRoleApplication</key>
           <array>
               <dict>
                   <key>UISceneConfigurationName</key>
                   <string>CarPlay</string>
                   <key>UISceneDelegateClassName</key>
                   <string>$(PRODUCT_MODULE_NAME).NoiseCarPlaySceneDelegate</string>
               </dict>
           </array>
       </dict>
   </dict>
   ```

3. Key areas in `AppDelegate` that need migration to the window scene delegate:
   - `Signal/AppLaunch/AppDelegate.swift` line ~128: `application(_:didFinishLaunchingWithOptions:)` — window creation and root view controller setup
   - Line ~1427: `refreshConnection(isAppActive:)` — foreground/background transitions
   - Line ~1770+: `applicationDidBecomeActive`, `applicationWillResignActive`, `applicationDidEnterBackground` — all state transition handlers
   - The `WindowManager` class (`Signal/src/WindowManager.swift`) manages multiple windows (main, calls, screen blocking) and would need to be adapted

4. Test thoroughly — Signal's window management is complex (multiple overlapping windows for calls, screen lock, etc.)

#### Option B: Use CPTemplateApplicationScene Notifications (simpler, limited)

Without migrating to scene lifecycle, CarPlay can still be partially supported by:

1. Registering for `CPTemplateApplicationScene` connection notifications directly
2. Using `CPInterfaceController` from the notification callbacks
3. This approach is less standard and may not pass App Store review for CarPlay

### Files Involved

- `Signal/CarPlay/NoiseCarPlaySceneDelegate.swift` — already implemented, ready to use once scene lifecycle works
- `Signal/CarPlay/CarPlayConversationListController.swift` — conversation list UI, ready
- `Signal/CarPlay/CarPlayMessageController.swift` — message display UI, ready
- `Signal/AppLaunch/AppDelegate.swift` — needs scene lifecycle migration (Option A)
- `Signal/src/WindowManager.swift` — manages multiple windows, needs adaptation (Option A)
- `Signal/Signal-Info.plist` — needs `UIApplicationSceneManifest` (Option A)

### Prerequisites

- Apple CarPlay entitlement approval (applied for via the CarPlay developer portal)
- `com.apple.developer.carplay-messaging` is already in the entitlements files

### Notes

- The CarPlay code compiles and is included in the build — it just can't be activated yet
- The SiriKit integration for CarPlay messaging works independently (Intents Extension handles "Hey Siri, send a message via Noise" in CarPlay without needing the template UI)
