# On-Device Testing with a Free (Personal Team) Apple Account

The app uses capabilities that require a paid Apple Developer Program account (iCloud, Push Notifications, Siri, etc.). To test on a physical device with a free Personal Team, you need to temporarily strip these capabilities.

**Warning**: Do NOT commit these changes. They disable core app functionality. This is only for local Spotlight/feature testing.

---

## Steps

### 1. Strip Entitlements from Signal (Main App)

Edit `Signal/Signal.entitlements` and replace its contents with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.default-data-protection</key>
	<string>NSFileProtectionComplete</string>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.$(SIGNAL_BUNDLEID_PREFIX).signal.group</string>
		<string>group.$(SIGNAL_BUNDLEID_PREFIX).signal.group.staging</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)$(SIGNAL_BUNDLEID_PREFIX).signal</string>
	</array>
</dict>
</plist>
```

This removes:
- `aps-environment` (Push Notifications)
- `com.apple.developer.associated-domains` (Associated Domains / Universal Links)
- `com.apple.developer.icloud-container-identifiers` (iCloud)
- `com.apple.developer.icloud-services` (iCloud)
- `com.apple.developer.in-app-payments` (Apple Pay)
- `com.apple.developer.ubiquity-kvstore-identifier` (iCloud KVS)
- `com.apple.developer.carplay-messaging` (CarPlay)
- `com.apple.developer.siri` (Siri)
- `com.apple.developer.usernotifications.communication` (Communication Notifications)
- `com.apple.developer.networking.carrier-constrained.*` (Carrier-Constrained Networking)

### 2. Strip Entitlements from SignalNSE (Notification Service Extension)

Edit `SignalNSE/SignalNSE.entitlements` and replace its contents with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.default-data-protection</key>
	<string>NSFileProtectionComplete</string>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.$(SIGNAL_BUNDLEID_PREFIX).signal.group</string>
		<string>group.$(SIGNAL_BUNDLEID_PREFIX).signal.group.staging</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)$(SIGNAL_BUNDLEID_PREFIX).signal</string>
	</array>
</dict>
</plist>
```

This removes:
- `com.apple.developer.networking.carrier-constrained.*` (Carrier-Constrained Networking)

### 3. Strip Entitlements from SignalShareExtension (Share Extension)

Edit `SignalShareExtension/SignalShareExtension.entitlements` and replace its contents with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.default-data-protection</key>
	<string>NSFileProtectionComplete</string>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.$(SIGNAL_BUNDLEID_PREFIX).signal.group</string>
		<string>group.$(SIGNAL_BUNDLEID_PREFIX).signal.group.staging</string>
	</array>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)$(SIGNAL_BUNDLEID_PREFIX).signal</string>
	</array>
</dict>
</plist>
```

This removes:
- `com.apple.developer.networking.carrier-constrained.*` (Carrier-Constrained Networking)

### 4. Configure Signing in Xcode

1. Open `Signal.xcworkspace` in Xcode
2. For **each** of the three targets (Signal, SignalNSE, SignalShareExtension):
   - Select the target in the project navigator
   - Go to **Signing & Capabilities** tab
   - Check **Automatically manage signing**
   - Select your **Personal Team** from the Team dropdown
3. If Xcode shows remaining capability errors in the Signing & Capabilities UI, click the **x** to remove any capabilities that are still listed (e.g., iCloud, Push Notifications, Siri)

### 5. Build and Run

1. Connect your iPhone via USB
2. Select your iPhone from the device picker at the top of Xcode
3. Press **Cmd+R** to build and run
4. On first install, you may need to go to **Settings > General > VPN & Device Management** on the phone and trust your developer certificate

### 6. What Won't Work

With these stripped entitlements, the following features will not function:
- Push notifications (no message delivery when app is backgrounded)
- Siri integration (voice commands, App Intents)
- iCloud backups
- Universal links (signal.me, signal.group, etc.)
- Apple Pay / donations
- CarPlay
- Communication notification categories (inline replies from lock screen)

Core messaging, Spotlight search, and general UI will still work.

### 7. Reverting

When done testing, discard all entitlement changes:

```bash
git checkout -- Signal/Signal.entitlements SignalNSE/SignalNSE.entitlements SignalShareExtension/SignalShareExtension.entitlements
```

Then switch the Team back to the production team and uncheck "Automatically manage signing" if it was previously unchecked.
