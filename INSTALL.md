# Install Foldly on macOS

## Requirements

- Apple silicon MacBook (M-series), macOS 14 Sonoma or newer.
- Screen Recording permission to render your desktop locally.

Intel Macs are not supported by this binary. Automatic lid tracking depends on whether your MacBook exposes its lid-angle sensor. If it does not, turn off **Follow MacBook lid** and use the manual angle slider. Foldly applies the effect only to the built-in display.

## Download and install

1. Quit any running copy of Foldly.
2. Open the [0.1.1 preview release](https://github.com/chappie1998/foldly/releases/tag/v0.1.1) and download **Foldly-0.1.1-macos-arm64.dmg** under **Assets**.
3. Open the DMG, then drag **Foldly.app** to the **Applications** shortcut. When updating an existing installation, replace the old app.
4. Eject the Foldly disk image. Open **Foldly** from Applications, so future launches use the same installed copy.

Alternatively, download **Foldly-0.1.1-macos-arm64.zip**, double-click to extract it, and move **Foldly.app** to Applications. The automatically generated GitHub “Source code” archives do not contain a compiled app.

## First-launch approval

This preview is ad-hoc signed. It has **not** been signed with an Apple Developer ID or notarized by Apple. If macOS blocks the app because the developer cannot be verified, and you trust this release:

1. Attempt to open the installed Foldly app once.
2. Open **System Settings → Privacy & Security**.
3. Find the message about Foldly and choose **Open Anyway**, then complete macOS's confirmation.

This creates an exception for this app. See [Apple's guidance on safely opening apps](https://support.apple.com/en-us/102445). No global Gatekeeper changes or quarantine-removal commands are needed. If macOS reports malware or that the app will damage your computer, do not override that warning.

## Enable the desktop effect

1. In Foldly, turn on **Enable**.
2. Approve **Foldly** under **System Settings → Privacy & Security → Screen Recording**. Newer macOS versions call this **Screen & System Audio Recording**.
3. If prompted, choose **Quit & Reopen**. Enable Foldly again after it relaunches.
4. Leave **Follow MacBook lid** on and close the lid below **105°**. Try **Frost** for blur that starts at the top and gradually moves downward, or choose Silk or Shade. The lower screen stays sharp at the start of the fold.

Foldly launches disabled. It uses one screen-capture session while enabled, including when the lid is open; **Pause**, **Disable**, or **Quit** stops capture. It captures the built-in display, excludes its own windows, keeps frames in memory, and does not save or upload them. Audio capture is disabled. The optional finish sound is a bundled sound effect.

Foldly is a menu bar app. Use its menu bar icon to reopen settings, pause, or quit. The custom capture-angle feature is deferred and is not included in this release.

## If permission keeps being requested

Changing or rebuilding an ad-hoc signed app can make macOS's old grant stale even when its toggle is on.

1. Quit all copies of Foldly and keep the release copy in **Applications**.
2. In Screen Recording settings, remove only Foldly's entry, then add `/Applications/Foldly.app` again and enable it.
3. Complete the normal macOS approval and relaunch the app.

If the stale entry cannot be refreshed in Settings, quit Foldly and run this scoped reset in Terminal, then reopen it and approve recording again:

```sh
tccutil reset ScreenCapture com.whiteduck.bendy
```

`com.whiteduck.bendy` is Foldly's retained internal bundle identifier. This command resets only Foldly's Screen Recording grant; it does not grant permission or reset other apps.

## Verify a download

The release includes `SHA256SUMS.txt`. Place it beside the DMG and ZIP, then run:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Both downloaded files should report `OK`. If you download only one archive, the other is reported missing; the archive you downloaded should still report `OK`.

## Build from source instead

Install Apple's Command Line Tools if needed:

```sh
xcode-select --install
```

Clone the public repository, then build:

```sh
git clone https://github.com/chappie1998/foldly.git
cd foldly
./native/build.sh
```

Move `native/build/Foldly.app` into Applications and follow the same first-launch and recording steps. Node.js is needed only for the web playground, not the native app. See the [native guide](native/README.md) for diagnostics and tests.

## Uninstall

Quit Foldly from its menu bar icon, move `/Applications/Foldly.app` to Trash, and remove its entry from Screen Recording settings if desired.
