# Headroom

A tiny native macOS menu bar utility for changing when the system menu bar hides.

The menu contains **Hide Menu Bar**, **Settings…**, **About Headroom**, and **Quit Headroom**. The mode selector offers the four macOS modes:

- Always
- On Desktop Only
- In Full Screen Only
- Never

Move the pointer away from the top edge after choosing a mode to see hiding. The main app always stays in menu-bar-only mode, so its popup remains available in desktop and fullscreen Spaces. Settings launches a separate desktop companion with its own Dock presence and a primary window. Closing Settings quits only the companion; the popup and automatic rules continue running. Settings does not opt into joining other apps' fullscreen Spaces.

## Custom fullscreen app settings

Open **Settings…** (Command–Comma) and choose **Open System Settings** to approve **Headroom**. On macOS 27, this permission is named **Device Control and Data Access** under Privacy & Security; on earlier macOS versions it is named **Accessibility**. This is separate from any permission granted to an earlier test probe. Each time Settings opens, it asks the menu bar process for a fresh, nonprompting permission check. The permission banner is hidden when access is granted. When access is missing, Settings shows a warning and an Open System Settings button; cached permission data is not shown as a fresh result. Manual menu bar changes work without Accessibility access.

- Normally, choosing a mode changes the default.
- With a readable fullscreen app in front, hold **Option (⌥)** to change the same selector to **Hide Menu Bar for App Name**. Choosing a mode saves that app's custom rule.
- In Settings, **Add App…** offers the same capability without a modifier key. Each rule has an editable mode (the four explicit macOS choices) and a remove button; removing a rule makes that app follow the default; **Undo Remove** restores the last removed rule.
- Rules apply only while their app is foreground and fullscreen. App rules take priority, so editing the default does not replace an active custom rule.
- Switching to an unmatched app, leaving fullscreen, disabling custom settings, removing the active rule, or quitting restores the default. A different external preference change is preserved when relinquishing an override.

Opening a menu does not change the setting. The target app is captured when the menu opens and checked again before saving a rule. Unknown fullscreen state does not count as windowed. A temporary unreadable state in the same app preserves the active override; moving to another app releases it.

The Settings window opens at 540 points wide, with General, Default Behaviour and App Rules sections and compact native controls. About Headroom is available from the menu bar, the Settings app menu, and the Settings footer. The content scrolls on smaller screens. General provides Launch at Login through SMAppService and a persistent menu bar icon switch. The window opens once when this feature is first launched. The Open System Settings button opens the permission pane directly; on macOS 27 its title is Device Control and Data Access (formerly Accessibility). If the main app is not listed, add Headroom.app there. Opening Settings only checks permission and does not prompt or navigate to System Settings.

## Build and run

Requires an Apple Silicon Mac, Xcode with its command-line tools selected, and a valid signing identity in Keychain. The build automatically selects a single available Developer ID Application identity; otherwise set MENU_BAR_SIGNING_IDENTITY to the certificate name or SHA-1. It refuses ad-hoc signing because permission grants would be tied to a single build. The build targets macOS 15 or later; the live setting mechanism has only been verified on macOS 27.2 (26B123).

```sh
git clone https://github.com/Oluwaseunus/menu-bar-toggle.git
cd menu-bar-toggle
zsh build.sh
open "Headroom.app"
```

The build compiles the Swift/AppKit source, creates an app bundle with a nested Settings companion, signs both locally, and runs 69 isolated checks. Generated bundles and build caches are ignored by Git. This local Apple Silicon preview is unsandboxed, Developer ID signed, and not notarized. Launch at Login is off by default and changes only when the user uses its switch. The app does not install itself in Applications. The build uses a stable signing identity so updates can satisfy the same designated requirement. Switching from an earlier ad-hoc build requires approving the newly signed main app once.

## State and error handling

The app observes foreground-app and Space changes, window focus/resize events, sleep/wake and session changes. It coalesces events for 150 ms and uses one-second fallback polling. AX reads run on a serial background queue with a timeout; results from an outdated foreground app are discarded. Only configured apps are inspected in the background; opening the menu explicitly checks the current app to offer a new rule.

The focused window's `AXFullScreen` value supplies fullscreen state. Unsupported attributes, timeouts and permission loss are handled without guessing. This string attribute is commonly implemented, but is not an SDK-defined fullscreen-state constant in the inspected headers. No private Space APIs are used by the app. Fullscreen does not establish exclusive Space occupancy or distinguish every Split View case.

Preferences are reread before changes and on event/poll refresh. Missing or conflicting preferences are not used as a guessed automation baseline. An explicit default selection can repair them.

Failed writes attempt to restore the exact previous values, including absent keys. Errors pause automatic changes and are reported in Settings and the status icon's tooltip. Changing a configuration retries evaluation. A recovery record tracks temporary overrides so a later launch can restore the baseline after an interrupted run, provided the recorded applied setting still matches. The isolated checks cover mode mapping, conflict detection, partial-write rollback, rule priority, default restoration and unknown states without changing system preferences.

## How it works

The app updates three preferences consistently:

| Preference | Domain |
| --- | --- |
| `_HIHideMenuBar` | Global |
| `AppleMenuBarVisibleInFullscreen` | Global |
| `AutoHideMenuBarOption` | `com.apple.controlcenter` |

It then posts `AppleInterfaceMenuBarHidingChangedNotification` and `AppleInterfaceFullScreenMenuBarVisibilityChangedNotification` through the distributed notification center. Custom app rules require Accessibility access; manual mode changes do not. No Automation permission is requested, and the app has no network code.

The preference names and notifications are undocumented. The approach was informed by [FreeSwitch's research](https://github.com/Having-Liu/FreeSwitch), then independently exercised in a reversible live test on macOS 27.2 on October 28, 2026. The user confirmed a visible show/hide change, and all original preference values were restored.

That test did not measure latency or prove Space preservation. A separate Accessibility probe subsequently read Brave's fullscreen exit/re-entry and app switches correctly. The native Settings add/edit/remove/undo flow has also been exercised. Multiple displays, Split View, other apps/OS versions, sleep/wake, and the complete automatic-switching flow still need live validation. The setting remains global across displays.

## Displays

Menu bar visibility and app rules apply system-wide across connected displays. Settings does not offer unsupported per-display controls.

Hiding the menu bar icon leaves the service and rules running. Reopen the main app from Finder to reach Settings. The Settings app menu also includes Quit Headroom.

## App identity

Headroom keeps the existing `love.oluwaseun.MenuBarToggle` bundle identifiers, preferences domain, and signing identity to preserve saved rules and permission continuity. The application bundle and user-facing branding are Headroom. The GitHub repository retains its existing URL.
