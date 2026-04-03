# Entitlements Reference

This document explains why each entitlement in the project is required, which code depends on it, and what breaks if it's removed.

---

## Signal (Main App) — `Signal/Signal.entitlements`

### aps-environment (Push Notifications)

**Value:** `development` (production in App Store build)

**Why it's needed:** Required for account registration with Signal's backend servers. The app registers an APNS push token during provisioning/login and uploads it to Signal's servers. The Notification Service Extension (NSE) uses push notifications to decrypt and display incoming messages in the background.

**Key files:**
- `Signal/Notifications/PushRegistrationManager.swift` — Registers with iOS for push tokens via `UIApplication.shared.registerForRemoteNotifications()`, handles VoIP push via `PKPushRegistry`
- `Signal/util/SyncPushTokensJob.swift` — Uploads push token to Signal backend via HTTP POST to `/api/v1/accounts/apn`
- `Signal/AppLaunch/AppDelegate.swift` (lines 1479-1537) — `didRegisterForRemoteNotificationsWithDeviceToken`, `didReceiveRemoteNotification` handlers; processes spam/pre-auth challenge tokens and triggers background message fetch
- `SignalNSE/NotificationService.swift` — `UNNotificationServiceExtension` that decrypts incoming messages and updates badge count within a 30-second window
- `SignalServiceKit/Util/APNSRotationStore.swift` — Tracks push token health, triggers rotation if stale

**What breaks without it:** Account registration fails. Background message delivery via push stops entirely. The NSE cannot process incoming notifications.

---

### com.apple.developer.associated-domains (Universal Links)

**Value:** `applinks:` for signal.art, signal.tube, signal.group, signal.me, signaldonations.org, signal.link

**Why it's needed:** Enables deep linking so that tapping Signal URLs in Safari, Messages, or other apps opens directly in Noise instead of a browser.

**Per-domain usage:**

| Domain | Purpose | Key File |
|--------|---------|----------|
| `signal.me` | Username lookup and phone number links (`signal.me/#p/+1234`, `signal.me/#eu/...`) | `SignalServiceKit/Usernames/Usernames+UsernameLink.swift`, `Signal/util/SignalDotMePhoneNumberLink.swift` |
| `signal.art` | Sticker pack sharing (`signal.art/addstickers/#pack_id=...&pack_key=...`) | `SignalServiceKit/Messages/Stickers/StickerPackInfo.swift` |
| `signal.group` | Group invite links (`signal.group/#base64url-encoded-proto`) | `SignalServiceKit/Groups/TSGroupModel.swift`, `SignalServiceKit/Groups/GroupManager.swift` |
| `signal.tube` | Proxy server configuration for censorship circumvention (`signal.tube/#proxy_host`) | `SignalServiceKit/Network/SignalProxy/SignalProxy.swift` |
| `signal.link` | Voice/video call invite links (`signal.link/call/#key=...`) | `SignalUI/Calls/CallLink.swift` |
| `signaldonations.org` | Return URL for Stripe 3D Secure and PayPal web authentication callbacks | `SignalServiceKit/Subscriptions/Donations/Stripe+3DSecure.swift`, `SignalServiceKit/Subscriptions/Donations/Paypal+WebAuthentication.swift` |

**URL routing entry point:** `Signal/URLs/UrlOpener.swift` — `parseOpenableUrl()` matches URLs to 8 handler types. `AppDelegate.swift` receives universal links via `application(_:continue:restorationHandler:)` for `NSUserActivityTypeBrowsingWeb`.

**What breaks without it:** All deep links open in Safari instead of the app. Group invites, username links, sticker packs, call links, and proxy configuration links require manual copy/paste. Donation payment callbacks (Stripe/PayPal) fail to return to the app.

---

### com.apple.developer.icloud-container-identifiers / icloud-services (iCloud)

**Value:** Container `iCloud.$(SIGNAL_BUNDLEID_PREFIX).signal`, service `CloudDocuments`

**Why it's needed:** Two purposes:

1. **Database backup/restore** — `Signal/iCloudBackup/CloudBackupManager.swift` copies the GRDB SQLite database to the iCloud ubiquity container (`fileManager.url(forUbiquityContainerIdentifier:)`). Supports automatic backups on a configurable interval (default 24h), keeps the 3 most recent backups, and allows restore on another device.

2. **SVR2 credential sync** (via `ubiquity-kvstore-identifier`) — `SignalServiceKit/SecureValueRecovery/SVRAuthCredentialStorageImpl.swift` stores Secure Value Recovery auth credentials in `NSUbiquitousKeyValueStore` under key `signal_svr2_credentials`. This allows re-registration on a new device without SMS verification (user still needs their PIN).

**What breaks without it:** Users cannot back up or restore their message database via iCloud. Re-registration on a new device requires SMS OTP verification instead of seamless PIN-based recovery.

---

### com.apple.developer.in-app-payments (Apple Pay)

**Value:** `merchant.$(SIGNAL_MERCHANTID)`

**Why it's needed:** Enables Apple Pay for in-app donations to Signal.

**Key files:**
- `SignalServiceKit/Subscriptions/Donations/DonationUtilities.swift` (line 262) — Creates `PKPaymentRequest` with `request.merchantIdentifier`
- `Signal/src/ViewControllers/Donations/DonateViewController.swift` — Presents `PKPaymentAuthorizationController`
- `Signal/src/ViewControllers/Donations/DonateViewController+PKPaymentAuthorizationControllerDelegate.swift` — Handles payment authorization callbacks
- `Signal/src/ViewControllers/Donations/DonateViewController+OneTimeApplePayDonation.swift` — One-time donation flow
- `Signal/src/ViewControllers/Donations/DonateViewController+MonthlyApplePayDonation.swift` — Recurring donation flow
- `Signal/src/ViewControllers/Donations/DonationViewsUtil+Gifting.swift` — Gift badge donations

**What breaks without it:** Apple Pay donation option is unavailable. Users can still donate via credit card (Stripe) or PayPal.

---

### com.apple.developer.siri (Siri)

**Value:** `true`

**Why it's needed:** Enables Siri voice commands, Shortcuts, and Apple Intelligence integration for messaging.

**Key files:**
- `Signal/AppIntents/NoiseSendMessageIntent.swift` — "Send a message with Noise" voice command
- `Signal/AppIntents/NoiseReadMessagesIntent.swift` — "Read messages in Noise" voice command
- `Signal/AppIntents/NoiseSearchMessagesIntent.swift` — "Search messages in Noise" voice command
- `Signal/AppIntents/NoiseSummarizeIntent.swift` — "Summarize conversation in Noise" for Apple Intelligence
- `Signal/AppIntents/NoiseShortcuts.swift` — Registers all shortcuts with the system for "Hey Siri" activation
- `SignalServiceKit/Notifications/UserNotificationsPresenter.swift` — Donates `INInteraction` objects so the system learns communication patterns
- `SignalServiceKit/Util/ThreadUtil.swift` — Builds `INSendMessageIntent` for outgoing messages
- `SignalServiceKit/Threads/ThreadSoftDeleteManager.swift` — Cleans up donated intents when threads are deleted

**What breaks without it:** Siri voice commands, Shortcuts integration, and Apple Intelligence message features are unavailable. Communication intent donations fail, reducing the system's ability to surface relevant contacts in share sheets and suggestions.

---

### com.apple.developer.usernotifications.communication (Communication Notifications)

**Value:** `true`

**Why it's needed:** Enables rich communication-style notifications where the sender's name and avatar appear prominently, with inline reply support.

**Key files:**
- `SignalServiceKit/Notifications/UserNotificationsPresenter.swift` (lines 189-202) — Enhances `UNNotificationContent` with `INSendMessageIntent` via `content.updating(from: intent)` to display sender identity
- `SignalServiceKit/Notifications/NotificationPresenterImpl.swift` — Creates `INSendMessageIntent` objects attached to notification content for conversation context
- `SignalServiceKit/Util/ThreadUtil.swift` — Builds intents with `INSendMessageIntentDonationMetadata` for group recipient counts

**What breaks without it:** Notifications fall back to basic style without sender avatars, prominent sender names, or communication-category features. Inline replies from the lock screen may be degraded.

---

### com.apple.developer.carplay-messaging (CarPlay)

**Value:** `true`

**Why it's needed:** Allows Noise to appear on the CarPlay dashboard for hands-free messaging while driving.

**Key files:**
- `Signal/CarPlay/NoiseCarPlaySceneDelegate.swift` — Implements `CPTemplateApplicationSceneDelegate`, manages CarPlay connection lifecycle and sets the root conversation list template
- `Signal/CarPlay/CarPlayConversationListController.swift` — Displays up to 20 recent conversations using `CPListTemplate`
- `Signal/CarPlay/CarPlayMessageController.swift` — Shows up to 15 recent messages in a conversation, integrates with Siri for voice replies via `INSendMessageIntent`

**Note:** This is a restricted entitlement requiring Apple approval. See `CARPLAY.md` for details.

**What breaks without it:** Noise does not appear on the CarPlay dashboard at all.

---

### com.apple.developer.networking.carrier-constrained.app-optimized (Carrier-Constrained Networking)

**Value:** `true`, category `messaging-8001`

**Why it's needed:** Declares to the system that this is a messaging app, enabling iOS to prioritize its network traffic on carrier-constrained connections (e.g., congested cellular networks, low data mode).

**Code references:** No direct API usage in the codebase. This is a system-level optimization — iOS reads the entitlement and adjusts network scheduling behavior automatically.

**What breaks without it:** The app may experience degraded network priority on constrained cellular connections. Messages could be delayed relative to other messaging apps that declare this entitlement.

---

### com.apple.security.application-groups (App Groups)

**Value:** `group.$(SIGNAL_BUNDLEID_PREFIX).signal.group`, `group.$(SIGNAL_BUNDLEID_PREFIX).signal.group.staging`

**Why it's needed:** Enables data sharing between the main app and its extensions (NSE, Share Extension).

**Key files:**
- `SignalServiceKit/Environment/TSConstants.swift` (line 192) — Defines group identifiers
- `SignalNSE/NSEContext.swift` (lines 32-46) — Accesses shared database directory via `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` and shared `UserDefaults(suiteName:)`
- `SignalShareExtension/ShareAppExtensionContext.swift` — Shares file access with main app

**What breaks without it:** The NSE cannot access the message database to decrypt and display notifications. The Share Extension cannot read conversations or send messages. The app is essentially broken for background notification processing.

---

### keychain-access-groups (Keychain Sharing)

**Value:** `$(AppIdentifierPrefix)$(SIGNAL_BUNDLEID_PREFIX).signal`

**Why it's needed:** Allows the main app and extensions to share keychain items (credentials, cryptographic keys).

**Key files:**
- `SignalServiceKit/Storage/SSKKeychainStorage.swift` — Implements `KeychainStorage` protocol using `SecItemCopyMatching`, `SecItemAdd`, `SecItemUpdate`, `SecItemDelete` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` protection
- `SignalServiceKit/SecureValueRecovery/SVRAuthCredentialStorageImpl.swift` — Stores SVR2 auth credentials in keychain

**What breaks without it:** Extensions cannot access authentication credentials. The app may fail to decrypt messages or authenticate with the server after backgrounding.

---

### com.apple.developer.default-data-protection (Data Protection)

**Value:** `NSFileProtectionComplete`

**Why it's needed:** Encrypts all app files so they are only accessible when the device is unlocked. Critical for a messaging app handling sensitive content.

**Key files:**
- `SignalServiceKit/Util/OWSFileSystem.swift` — Creates temp directories with `.complete` and `.completeUntilFirstUserAuthentication` protection levels
- `SignalServiceKit/Environment/AppSetup.swift` (lines 199-202) — Sets temporary directory to `.completeUntilFirstUserAuthentication` because "AFNetworking spools attachments in NSTemporaryDirectory(). If you receive a media message while the device is locked, the download will fail if the temporary directory is NSFileProtectionComplete."

**What breaks without it:** Message database and attachments are not encrypted at rest with the strongest available protection. Files could theoretically be accessed while the device is locked.

---

## SignalNSE — `SignalNSE/SignalNSE.entitlements`

The Notification Service Extension has a minimal entitlement set:

| Entitlement | Why |
|-------------|-----|
| Data Protection (`NSFileProtectionComplete`) | Encrypt extension files at rest |
| Carrier-Constrained Networking | System-level network priority for message fetching |
| App Groups | Access the shared database to decrypt incoming messages |
| Keychain Access Groups | Access shared authentication credentials |

---

## SignalShareExtension — `SignalShareExtension/SignalShareExtension.entitlements`

The Share Extension has the same minimal set as NSE:

| Entitlement | Why |
|-------------|-----|
| Data Protection (`NSFileProtectionComplete`) | Encrypt extension files at rest |
| Carrier-Constrained Networking | System-level network priority for sending shared content |
| App Groups | Access the shared database to read conversations and send messages |
| Keychain Access Groups | Access shared authentication credentials |
