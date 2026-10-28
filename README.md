# Menu Bar Toggle

A tiny native macOS menu bar utility for changing when the system menu bar hides.

The menu contains **Hide Menu Bar**, with the four macOS modes and a checkmark beside the active mode, and **Quit Menu Bar Toggle**:

- Always
- On Desktop Only
- In Full Screen Only
- Never

Move the pointer away from the top edge after choosing a mode to see hiding. Opening or quitting the app preserves your selected setting. The app has no Dock icon.

## Build and run

Requires an Apple Silicon Mac and Xcode with its command-line tools selected. The build targets macOS 15 or later; the live setting mechanism has only been verified on macOS 27.2 (26B123).

```sh
git clone https://github.com/Oluwaseunus/menu-bar-toggle.git
cd menu-bar-toggle
zsh build.sh
open "Menu Bar Toggle.app"
```

The build compiles the Swift/AppKit source, creates an app bundle, signs it locally, and runs 15 isolated checks. Generated bundles and build caches are ignored by Git. This local preview is unsandboxed, ad-hoc signed, and not notarized. It creates no login item and does not install itself in Applications.

## State and error handling

The app rereads preferences before each change, when its menu opens, on setting notifications, after wake, and every two seconds. Missing or conflicting preferences leave all modes unchecked; selecting an explicit mode remains available.

Failed writes attempt to restore the exact previous values, including absent keys. Errors are reported with a sound and the status icon's tooltip. The isolated checks cover mode mapping, conflict detection, and rollback after a partial write without changing system preferences.

## How it works

The app updates three preferences consistently:

| Preference | Domain |
| --- | --- |
| `_HIHideMenuBar` | Global |
| `AppleMenuBarVisibleInFullscreen` | Global |
| `AutoHideMenuBarOption` | `com.apple.controlcenter` |

It then posts `AppleInterfaceMenuBarHidingChangedNotification` and `AppleInterfaceFullScreenMenuBarVisibilityChangedNotification` through the distributed notification center. No Accessibility or Automation permission is requested, and the app has no network code.

The preference names and notifications are undocumented. The approach was informed by [FreeSwitch's research](https://github.com/Having-Liu/FreeSwitch), then independently exercised in a reversible live test on macOS 27.2 on October 28, 2026. The user confirmed a visible show/hide change, and all original preference values were restored.

That test did not measure latency or prove Space preservation. Already-active fullscreen apps, multiple displays, external edits, sleep/wake, and other macOS versions still need live validation.
