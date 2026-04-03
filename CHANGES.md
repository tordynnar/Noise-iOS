# Noise-iOS: Changes from Signal-iOS

This document details all modifications made to the Signal-iOS fork to create Noise-iOS.

---

## Phase 1: Rebranding (Signal → Noise)

### 1A. Bundle IDs & Product Name

**`Signal.xcodeproj/project.pbxproj`**
- `SIGNAL_BUNDLEID_PREFIX` changed from `org.whispersystems` to `com.noise` (4 occurrences, lines ~21420, 21679, 21943, 22044)
- `PRODUCT_NAME` changed from `Signal` to `Noise` (4 occurrences, lines ~21480, 21739, 22106, 22146)
- `INFOPLIST_KEY_NSHumanReadableCopyright` changed from `"Copyright © 2024 Signal Messenger, LLC"` to `"Copyright © 2024 Noise Messenger"` (4 occurrences)

**Entitlements** — No direct edits needed. All 6 entitlements files use `$(SIGNAL_BUNDLEID_PREFIX)` which resolves to the new `com.noise` prefix at build time:
- `Signal/Signal.entitlements`
- `Signal/Signal-AppStore.entitlements`
- `SignalNSE/SignalNSE.entitlements`
- `SignalNSE/SignalNSE-AppStore.entitlements`
- `SignalShareExtension/SignalShareExtension.entitlements`
- `SignalShareExtension/SignalShareExtension-AppStore.entitlements`

### 1B. Info.plist Updates

**`Signal/Signal-Info.plist`**
- All `NS*UsageDescription` strings: "Signal" → "Noise" (camera, microphone, contacts, Face ID, location, photos, Apple Music, local network)
- `LOGS_EMAIL`: `support@signal.org` → `support@noise.app`
- `CFBundleURLSchemes`: Added `noise` alongside existing `sgnl`

**`SignalNSE/Info.plist`**
- `CFBundleDisplayName`: `SignalNSE` → `NoiseNSE`

**`SignalShareExtension/Info.plist`**
- `CFBundleDisplayName`: `SignalSAE` → `NoiseSAE`

### 1C. Localized Strings

Bulk replacement across **42 `.strings` files** and **43 `.stringsdict` files** under `Signal/translations/`:
- All user-facing "Signal" → "Noise" in string values (keys preserved)
- `support@signal.org` → `support@noise.app` in all translation files

**`SignalShareExtension/SAEFailedViewController.swift:42`**
- `self.navigationItem.title = "Signal"` → `"Noise"`

### 1D. App Icon Colors (Blue → Red)

**Icon JSON gradient changes** — The icon uses Apple's `.icon` format where color is defined by JSON gradients, not in the SVG asset itself.

**`Signal/AppIcons/AppIcon.icon/icon.json`** (default icon)
- Light mode gradient: `display-p3:0.23137,0.27059,0.99216` → `display-p3:0.92000,0.22000,0.21000`; `srgb:0.12157,0.16471,0.99216` → `srgb:0.85000,0.11000,0.11000`
- Dark mode gradient: `display-p3:0.19216,0.49020,1.00000` → `display-p3:1.00000,0.30000,0.28000`; `srgb:0.15686,0.34118,1.00000` → `srgb:0.95000,0.22000,0.20000`

**Same pattern applied to alternate icon variants:**
- `Signal/AppIcons/AppIcon-white.icon/icon.json` — same blue→red shift
- `Signal/AppIcons/AppIcon-dark.icon/icon.json` — dark blue background→dark red, light blue logo→light red
- `Signal/AppIcons/AppIcon-chat.icon/icon.json` — cyan/blue→red (both light and dark gradients)
- `Signal/AppIcons/AppIcon-wave.icon/icon.json` — blue gradient→red, blue solid→red
- `Signal/AppIcons/AppIcon-bubbles.icon/icon.json` — blue solid→red, blue gradient→red (orange accent preserved)
- `Signal/AppIcons/AppIcon-weather.icon/icon.json` — dark blue gradients→dark red

**Icons left unchanged** (not blue-themed): `AppIcon-yellow`, `AppIcon-color`, `AppIcon-news`, `AppIcon-notes`, `AppIcon-dark-variant`

**Preview PNGs** — 7 raster preview images hue-shifted from blue to red using ImageMagick (`magick -modulate 100,100,167` = 120° hue rotation):
- `Signal/AppIcon.xcassets/AppIconPreview/default.imageset/Signal-180x180.png`
- `Signal/AppIcon.xcassets/AppIconPreview/white.imageset/SignalWhite-180x180.png`
- `Signal/AppIcon.xcassets/AppIconPreview/dark.imageset/SignalNight-180x180.png`
- `Signal/AppIcon.xcassets/AppIconPreview/chat.imageset/Chat-180x180.png`
- `Signal/AppIcon.xcassets/AppIconPreview/wave.imageset/Waves-180x180.png`
- `Signal/AppIcon.xcassets/AppIconPreview/bubbles.imageset/Bubbles-180x180.png`
- `Signal/AppIcon.xcassets/AppIconPreview/weather.imageset/Weather-180x180.png`

---

## Phase 2: Replace APNs with Polling

Since the new `com.noise` bundle ID does not match Signal's APN authentication key, push notifications will not arrive. Message delivery now relies on WebSocket (foreground) and aggressive background polling.

### 2A. Background Fetch Frequency

**`Signal/src/MessageFetchBGRefreshTask.swift`**
- Class docstring updated to describe polling-based message delivery
- Polling interval changed from `RemoteConfig.current.backgroundRefreshInterval` (default 24 hours) to `2 * 60` (2 minutes). iOS will throttle to ~15 minutes minimum.
- Added `processingTaskIdentifier` constant (`"MessageFetchBGProcessingTask"`)
- Added `BGProcessingTask` registration in `register(appReadiness:)` alongside existing `BGAppRefreshTask`
- `scheduleTask()` now schedules both a `BGAppRefreshTaskRequest` (every 2 minutes) and a `BGProcessingTaskRequest` (every 5 minutes, requires network)
- Added `performProcessingTask(_:)` handler with 120-second timeout (vs 27 seconds for refresh tasks)
- Extracted `logSchedulingError(_:taskType:)` helper

**`Signal/Signal-Info.plist`**
- Added `MessageFetchBGProcessingTask` to `BGTaskSchedulerPermittedIdentifiers` array

### 2B. Foreground & Background Delivery (unchanged)

The existing infrastructure already handles these cases:
- **Foreground**: WebSocket via `OWSChatConnection` with 30-second keepalive — no changes needed
- **Background**: `AppDelegate.refreshConnection(isAppActive:shouldRunCron:)` holds a background task for up to 180 seconds — no changes needed

---

## Phase 3: Siri & Apple Intelligence Integration

### 3A. Siri Entitlement

**`Signal/Signal.entitlements`** and **`Signal/Signal-AppStore.entitlements`**
- Added `com.apple.developer.siri` = `true`

### 3B. Enhanced Intent Donations

**`SignalServiceKit/Util/ThreadUtil.swift`**
- Removed `areIntentDonationsEnabled` guard (line ~474) — intents are now always donated, enabling Apple Intelligence to learn communication patterns
- `INSendMessageIntent` `content` parameter changed from `nil` to `message?.body` (line ~548) — actual message text is now included in intent donations for Apple Intelligence summarization

**`Signal/Signal-Info.plist`**
- Added `INSearchForMessagesIntent` and `INReadMessageIntent` to `NSUserActivityTypes`
- Added `NSSiriUsageDescription` key

### 3C. AppIntents Framework (new files)

All files created in `Signal/AppIntents/` and added to the main app target in `project.pbxproj`:

**`Signal/AppIntents/NoisePersonEntity.swift`**
- `AppEntity` wrapping a contact for Siri resolution
- `NoisePersonQuery` with `entities(for:)` and `suggestedEntities()` — fetches contacts via `TSContactThread` and `ContactManager`

**`Signal/AppIntents/NoiseConversationEntity.swift`**
- `AppEntity` wrapping a `TSThread` (contact or group)
- `NoiseConversationQuery` with `entities(for:)` and `suggestedEntities()` — enumerates visible threads via `ThreadFinder`

**`Signal/AppIntents/NoiseSendMessageIntent.swift`**
- `AppIntent` that sends a message to a conversation
- Takes `conversation: NoiseConversationEntity` and `message: String` parameters
- Uses `UnpreparedOutgoingMessage.build()` and `messageSenderJobQueueRef.add()` to send

**`Signal/AppIntents/NoiseReadMessagesIntent.swift`**
- `AppIntent` that reads recent messages from a conversation
- Takes `conversation` and optional `count` (default 5, max 20)
- Uses `InteractionFinder.enumerateRecentInteractions()` to fetch messages
- Returns formatted sender/content pairs

**`Signal/AppIntents/NoiseSearchMessagesIntent.swift`**
- `AppIntent` that searches messages by keyword
- Takes `query: String` and optional `conversation`
- Searches across all visible threads if no conversation specified (up to 50 threads, 10 results)

**`Signal/AppIntents/NoiseSummarizeIntent.swift`**
- `AppIntent` providing conversation content for Apple Intelligence summarization
- Returns up to 50 messages with participant list and conversation metadata

**`Signal/AppIntents/NoiseShortcuts.swift`**
- `AppShortcutsProvider` declaring Siri phrases for all intents:
  - "Send a message in Noise"
  - "Read my messages in Noise"
  - "Search messages in Noise"
  - "Summarize my Noise conversation"

### 3D. Project Configuration

**`Signal.xcodeproj/project.pbxproj`**
- Added `PBXFileReference` entries for all 7 AppIntents files (IDs `AAB0DA5C...` through `AA29639A...`)
- Added `PBXBuildFile` entries (IDs `BBB0DA5C...` through `BB29639A...`)
- Added `PBXGroup` `AppIntents` (ID `AA000000000000000000AIGI`) under the Signal folder
- Added all 7 files to the main app target's Sources build phase

---

## Phase 4: CarPlay Support

### 4A. Entitlement

**`Signal/Signal.entitlements`** and **`Signal/Signal-AppStore.entitlements`**
- Added `com.apple.developer.carplay-messaging` = `true`
- Note: This entitlement requires Apple approval via the CarPlay developer portal

### 4B. Scene Configuration

**`Signal/Signal-Info.plist`**
- Added `UIApplicationSceneManifest` with `CPTemplateApplicationSceneSessionRoleApplication` scene configuration
- Scene delegate class: `$(PRODUCT_MODULE_NAME).NoiseCarPlaySceneDelegate`

### 4C. CarPlay Implementation (new files)

All files created in `Signal/CarPlay/` and added to the main app target:

**`Signal/CarPlay/NoiseCarPlaySceneDelegate.swift`**
- Implements `CPTemplateApplicationSceneDelegate`
- Manages CarPlay connect/disconnect lifecycle
- Sets `CarPlayConversationListController` as root template on connect

**`Signal/CarPlay/CarPlayConversationListController.swift`**
- Creates a `CPListTemplate` showing up to 20 recent conversations
- Uses `ThreadFinder.enumerateVisibleThreads()` to populate the list
- Each item shows contact/group name and last message preview via `InteractionFinder`
- Tapping a conversation pushes `CarPlayMessageController`

**`Signal/CarPlay/CarPlayMessageController.swift`**
- Creates a `CPListTemplate` showing up to 15 recent messages in a conversation
- Messages displayed with sender name and body text
- "Reply with Siri" action item — delegates to SiriKit's `INSendMessageIntent` for voice dictation

### 4D. Project Configuration

**`Signal.xcodeproj/project.pbxproj`**
- Added `PBXFileReference` entries for 3 CarPlay files (IDs `CC00000000000000000000{11,12,13}`)
- Added `PBXBuildFile` entries (IDs `CC00000000000000000000{01,02,03}`)
- Added `PBXGroup` `CarPlay` (ID `CC000000000000000000CPLY`) under the Signal folder
- Added all 3 files to the main app target's Sources build phase

---

## Phase 5: Spotlight Indexing

### 5A. SpotlightIndexManager

**`Signal/Spotlight/SpotlightIndexManager.swift`** (new file)
- Singleton `SpotlightIndexManager.shared`
- `indexAllConversations()` — indexes up to 500 visible threads as `CSSearchableItem` objects with:
  - Title: contact/group name
  - Content description: last message preview
  - Content type: `UTType.message`
  - Author names for communication integration
  - 30-day expiration
  - Domain: `com.noise.conversations`
- `indexThread(_:)` — re-indexes a single thread on change
- `removeThread(uniqueId:)` — removes a thread from the index
- `threadId(from:)` — extracts thread uniqueId from a `CSSearchableItemActionType` user activity

### 5B. AppDelegate Integration

**`Signal/AppLaunch/AppDelegate.swift`**
- Added `import CoreSpotlight` (line ~6)
- Added `SpotlightIndexManager.shared.indexAllConversations()` call after app launch (line ~839)
- Added `CSSearchableItemActionType` case to the `application(_:continue:restorationHandler:)` switch (line ~1717):
  - Extracts thread uniqueId via `SpotlightIndexManager.threadId(from:)`
  - Opens the conversation via `SignalApp.shared.presentConversationAndScrollToFirstUnreadMessage()`

### 5C. Project Configuration

**`Signal.xcodeproj/project.pbxproj`**
- Added `PBXFileReference` for `SpotlightIndexManager.swift` (ID `DD0000000000000000000011`)
- Added `PBXBuildFile` (ID `DD0000000000000000000001`)
- Added `PBXGroup` `Spotlight` (ID `DD000000000000000000SPOT`) under the Signal folder
- Added to main app target's Sources build phase

---

## Phase 6: iCloud Backup

### 6A. Entitlements

**`Signal/Signal.entitlements`** and **`Signal/Signal-AppStore.entitlements`**
- `com.apple.developer.icloud-container-identifiers`: changed from empty array to `["iCloud.$(SIGNAL_BUNDLEID_PREFIX).signal"]`
- Added `com.apple.developer.icloud-services` = `["CloudDocuments"]`

### 6B. CloudBackupManager

**`Signal/iCloudBackup/CloudBackupManager.swift`** (new file)
- Singleton `CloudBackupManager.shared`
- **Settings** (stored in `UserDefaults`):
  - `isAutoBackupEnabled` — toggle for automatic backups
  - `lastBackupDate` — timestamp of most recent backup
  - `backupFrequencyHours` — interval between auto-backups (default 24 hours)
- **Backup** (`performBackup()`):
  - Copies `SDSDatabaseStorage.grdbDatabaseFileUrl` (GRDB SQLite database) to the iCloud ubiquity container (`Documents/Backups/`)
  - Also copies WAL and SHM files for consistency
  - Creates timestamped backup files (`noise-backup-YYYY-MM-DD_HH-mm-ss.sqlite`)
  - Automatically cleans up old backups, keeping the 3 most recent
- **Restore** (`restore(from:)`):
  - Replaces the local database with a selected backup file
  - App restart required after restore
- **Utilities**:
  - `availableBackups()` — lists backups with date and size
  - `isBackupDue()` — checks if auto-backup interval has elapsed
  - `isICloudAvailable` — checks for iCloud sign-in
  - `BackupInfo` struct with `displayDate` and `displaySize` formatters
  - `BackupError` enum with user-facing error descriptions

### 6C. Project Configuration

**`Signal.xcodeproj/project.pbxproj`**
- Added `PBXFileReference` for `CloudBackupManager.swift` (ID `EE0000000000000000000011`)
- Added `PBXBuildFile` (ID `EE0000000000000000000001`)
- Added `PBXGroup` `iCloudBackup` (ID `EE00000000000000000ICLUD`) under the Signal folder
- Added to main app target's Sources build phase

---

## Files Added

| File | Purpose |
|------|---------|
| `Signal/AppIntents/NoisePersonEntity.swift` | AppEntity for contacts (Siri resolution) |
| `Signal/AppIntents/NoiseConversationEntity.swift` | AppEntity for conversation threads |
| `Signal/AppIntents/NoiseSendMessageIntent.swift` | Siri intent: send messages |
| `Signal/AppIntents/NoiseReadMessagesIntent.swift` | Siri intent: read recent messages |
| `Signal/AppIntents/NoiseSearchMessagesIntent.swift` | Siri intent: search messages by keyword |
| `Signal/AppIntents/NoiseSummarizeIntent.swift` | Siri intent: summarize conversations |
| `Signal/AppIntents/NoiseShortcuts.swift` | AppShortcutsProvider with Siri phrases |
| `Signal/CarPlay/NoiseCarPlaySceneDelegate.swift` | CarPlay scene lifecycle |
| `Signal/CarPlay/CarPlayConversationListController.swift` | CarPlay conversation list UI |
| `Signal/CarPlay/CarPlayMessageController.swift` | CarPlay message display + reply |
| `Signal/Spotlight/SpotlightIndexManager.swift` | CoreSpotlight indexing of conversations |
| `Signal/iCloudBackup/CloudBackupManager.swift` | iCloud database backup/restore |

## Files Modified

| File | Changes |
|------|---------|
| `Signal.xcodeproj/project.pbxproj` | Bundle ID, product name, copyright, 12 new file references |
| `Signal/Signal-Info.plist` | Usage descriptions, URL schemes, scene manifest, Siri, BG tasks |
| `Signal/Signal.entitlements` | Siri, CarPlay, iCloud entitlements |
| `Signal/Signal-AppStore.entitlements` | Siri, CarPlay, iCloud entitlements |
| `SignalNSE/Info.plist` | Display name |
| `SignalShareExtension/Info.plist` | Display name |
| `SignalShareExtension/SAEFailedViewController.swift` | Nav title |
| `Signal/src/MessageFetchBGRefreshTask.swift` | Polling interval, BGProcessingTask |
| `Signal/AppLaunch/AppDelegate.swift` | CoreSpotlight import, Spotlight indexing, Spotlight continuation |
| `SignalServiceKit/Util/ThreadUtil.swift` | Intent donation: content + always-on |
| `Signal/AppIcons/AppIcon.icon/icon.json` | Blue → red gradients |
| `Signal/AppIcons/AppIcon-white.icon/icon.json` | Blue → red gradients |
| `Signal/AppIcons/AppIcon-dark.icon/icon.json` | Blue → red gradients |
| `Signal/AppIcons/AppIcon-chat.icon/icon.json` | Blue → red gradients |
| `Signal/AppIcons/AppIcon-wave.icon/icon.json` | Blue → red gradients |
| `Signal/AppIcons/AppIcon-bubbles.icon/icon.json` | Blue → red gradients |
| `Signal/AppIcons/AppIcon-weather.icon/icon.json` | Blue → red gradients |
| `Signal/AppIcon.xcassets/AppIconPreview/*/` | 7 preview PNGs hue-shifted |
| `Signal/translations/*/Localizable.strings` | 42 files: "Signal" → "Noise" |
| `Signal/translations/*/PluralAware.stringsdict` | 43 files: "Signal" → "Noise" |

## Known Limitations

- **Background message delivery**: iOS throttles `BGAppRefreshTask` to ~15 minutes at best. Messages will be delayed when the app is in the background. Real-time delivery only works via WebSocket when the app is in the foreground.
- **CarPlay entitlement**: Requires Apple approval via the CarPlay developer portal before the CarPlay interface will appear on devices.
- **AppIntents compilation**: The AppIntents files reference internal Signal types (`InteractionFinder`, `ThreadFinder`, `SDSDB`, etc.) and may require adjustments to match exact API signatures, which can vary across Signal releases.
- **iCloud backup**: Currently backs up only the main SQLite database file. Attachments (media) are not included. The app must be restarted after a restore.
- **Push notifications**: With the new `com.noise` bundle ID, APNs pushes from Signal's servers will silently fail. The push token is still registered (required for account registration) but will not receive wake-up pushes.
