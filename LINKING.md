# Device Linking

## Overview

Noise supports multi-device usage through a primary/secondary device model. A user registers one device as their **primary** device, and can then **link** additional devices as secondary devices to the same account.

## iPhone vs iPad Behavior

### iPhone (Primary Only in Production)

In production builds, iPhones can only register as **primary** devices. The option to link an iPhone as a secondary device is not exposed to users.

- On launch, an unregistered iPhone is directed to the **registration** flow (`AppDelegate.swift:918`).
- The mode-switch button (to toggle between registration and linking) is hidden on iPhones in production builds.

### iPad (Linking by Default)

iPads default to the **linking** flow, allowing them to be added as secondary devices to an existing account.

- On launch, an unregistered iPad is directed to **secondary provisioning** (`AppDelegate.swift:916`).
- iPad users can also switch modes and register as a primary device if desired (`RegistrationSplashViewController.swift:40`).

### Practical Result

- You **can** have an iPhone (primary) and an iPad (secondary) active on the same account.
- You **cannot** link two iPhones to the same account in production builds.

## How It's Enforced

### Client-Side

The mode-switch button on the registration splash screen is gated by:

```swift
// RegistrationSplashViewController.swift:40
let canSwitchModes = UIDevice.current.isIPad || BuildFlags.linkedPhones
```

`BuildFlags.linkedPhones` is only enabled for internal/dev builds (`BuildFlags.swift:32`):

```swift
public static let linkedPhones = build <= .internal
```

This means linked phones are available for testing in internal builds but disabled in production.

### Server-Side

The server enforces a maximum number of linked devices per account. If the limit is exceeded, the server returns HTTP 411, surfaced to the user via `DeviceLimitExceededError`.

## Device Identity

- **Primary devices** always have device ID `1` (see `DeviceId.swift`).
- **Secondary/linked devices** are assigned higher device IDs.
- The registration state distinguishes between primary states (`.registered`, `.reregistering`) and linked states (`.provisioned`, `.relinking`).

## Provisioning Flow

When linking a new device:

1. The secondary device displays a QR code.
2. The primary device scans the QR code and sends a `LinkingProvisioningMessage`.
3. The secondary device completes provisioning and receives an account backup via Link'n'Sync (`LinkAndSyncManager`).
