# Foldly

**Give it a fold.** A native macOS app that gently bends and frosts your desktop as you close your MacBook lid, with an interactive web playground.

## Install on macOS

[Download Foldly 0.1.0 preview](https://github.com/chappie1998/foldly/releases/tag/v0.1.0) · [Installation guide](INSTALL.md)

Requires an **Apple silicon MacBook** and **macOS 14 or newer**. Intel builds are not included. This repository and its release downloads are private; sign in with a GitHub account that has access.

1. Download `Foldly-0.1.0-macos-arm64.dmg` from the release assets.
2. Open the DMG and drag **Foldly.app** into **Applications**.
3. Eject the disk image and open **Foldly** from Applications.
4. Enable Foldly and approve its **Screen Recording** request in System Settings. If macOS asks, choose **Quit & Reopen**, then enable Foldly again.

This preview is ad-hoc signed, **not Developer ID signed or Apple-notarized**. macOS may block the first launch; see [first-launch approval](INSTALL.md#first-launch-approval) for Apple's normal per-app approval flow. A ZIP download is also available.

The visual effect begins below **105°**. Blur starts at the top, leaving the bottom sharp initially, and spreads down as the lid closes. Capture stays on while enabled and stops when paused or disabled. Frames stay in memory and are not saved or uploaded. Hardware lid sensing varies by MacBook; a manual angle control is available. Choose **Frost** for the soft, blurred effect.

## Build the native app

Install Apple's Command Line Tools, clone this repository, then run:

```sh
./native/build.sh
```

The app is created at `native/build/Foldly.app`, with a ZIP at `public/Foldly.zip`. See the [native development guide](native/README.md) for diagnostics, rendering tests, and sensor support.

## Run the web playground locally

```sh
npm run dev -- --host 0.0.0.0
```

The server uses port `5173` by default. Pass `--port 4173` to choose another port.

## Build and test

```sh
npm test
npm run build
```

The static build is written to `dist/`. When present, `public/Foldly.zip` is included so the download works. Set `BUILD_EXCLUDE_ZIP=1` only for a web-only build when disk space is constrained. Legacy `Bendy.zip` and `Hingely.zip` archives are never published.
