# ClickPaste for macOS

A menu bar utility that types the clipboard as keystrokes. Built for windows where paste is unavailable: virtual machines, VNC, remote consoles (iDRAC, iLO, IPMI, Proxmox) and similar.

## Usage

| Action | Result |
| --- | --- |
| Left-click the menu bar icon | Shows clipboard history |
| Click a history entry (or press `1`–`9`) | Pastes it into the app you were using |
| `⌥`-click a history entry, then click a window | Types that entry into the window |
| **Click Target Window to Type Clipboard…**, then click a window | Types the clipboard into that window |
| `⌃⌥V` | Types the clipboard into the focused window |
| `Esc` | Stops typing |
| Right-click the menu bar icon | Settings and quit |

History keeps the last 20 text clips. Clips that password managers mark as concealed or transient (1Password, Bitwarden and others, via [nspasteboard.org](http://nspasteboard.org) markers) are never recorded. History is kept in memory only unless **Remember History After Quit** is on.

Keystrokes are sent as real key codes mapped from the active keyboard layout, including physical Shift and Option presses, so they are recognized by VMs and remote sessions.

## Settings

- **Delay Between Keys**: 0–100 ms. Increase it if the target drops characters.
- **Delay Before Typing**: 250 ms–3 s.
- **Send Real Keypresses**: turn off to send Unicode text events (native Mac apps only).
- **Hotkey**: enables or disables `⌃⌥V`.
- **Remember History After Quit**: saves history to the app's preferences. Off by default.
- **Clear History**
- **Hide Menus From Screen Sharing**: keeps ClickPaste's menus, and the clipboard text in them, out of screen sharing and recordings. On by default. Mirrored and external displays still show them.
- **Launch at Login**

## Requirements

- macOS 13 or later
- Accessibility permission (System Settings → Privacy & Security → Accessibility)

## Build

Requires the Xcode Command Line Tools. No external dependencies.

```sh
./build.sh            # builds build/ClickPaste.app
./build.sh install    # also copies it to /Applications
NOTARY_PROFILE=<profile> ./build.sh release   # signed, notarized build/ClickPaste-<version>.zip
```

`release` signs with the first `Developer ID Application` identity in your keychain (override with `SIGN_ID`) and notarizes using a profile saved with `xcrun notarytool store-credentials`.

The app icon is drawn by `Icon/make-icon.swift`. After editing it, run `swift Icon/make-icon.swift` to regenerate `Icon/AppIcon.icns` and `Icon/preview.png`.

After rebuilding, macOS may revoke Accessibility access for the new binary. If so, remove ClickPaste from the Accessibility list and add it again.

## Installing a downloaded build

Download the zip from [Releases](https://github.com/sam-morin/ClickPaste-macOS/releases), unzip it, and move `ClickPaste.app` to `/Applications`. Release builds are signed with a Developer ID and notarized by Apple.
