# Foldly for macOS

Foldly is an independent native recreation inspired by [Adrian Abelarde's Bendy concept](https://x.com/adrianabelarde_/status/2097998552517759106). It folds the built-in MacBook desktop image as the lid closes. It is not the original app or an official binary from the concept's author.

## Build and run locally

Requirements: Apple silicon Mac, macOS 14 or newer, and Apple's Command Line Tools.

```sh
./native/build.sh
./native/build/Foldly.app/Contents/MacOS/Foldly --self-test
./native/build/Foldly.app/Contents/MacOS/Foldly --diagnose
open ./native/build/Foldly.app
```

The local build is ad-hoc signed. macOS may warn about an unsigned download when the zip is moved to another Mac. Build it from source locally or explicitly allow it in System Settings if you trust the source.

Foldly launches disabled. **Enable** arms capture according to the **Screen capture** setting. **Lid angle** is the default: capture starts below **105°** and stops at **107°** when reopening. Adjust **Start below** from **60–115°**, in whole degrees; capture always stops 2° above the chosen trigger to avoid repeated restarts from sensor jitter. **Always on** starts capture immediately and keeps one session running through folding and reopening. Both settings persist across launches, and the manual angle uses the same rules. Screen Recording permission is needed when capture first starts. The footer shows whether capture is off, starting, or active. It captures only the built-in display, explicitly excludes Foldly's own process, keeps frames in memory, and never writes or uploads them. Disable, Pause, sleep, display changes, sensor loss, and capture errors immediately hide the overlay and stop capture. Escape pauses while Foldly is focused; a global Escape monitor works only when macOS already permits it, and Foldly never requests Accessibility access. The menu bar Pause action remains available above the noninteractive overlay.

The display animates toward each sensor reading at a target of 60 fps, while capture supplies desktop updates at 30 fps. The visual fold remains flat at 107°, independently of the capture trigger. When angle-based capture stops, the last in-memory frame finishes easing open and is then cleared. Always on retains the frame for the next fold on a static desktop. Frost uses a cosine projection, soft edges, progressive blur, and a light tint. Reduce Motion is respected.

The overlay stays hidden throughout capture startup, so it cannot cover the initial macOS permission request. While capture runs, Foldly temporarily hides its effect when System Settings is foreground, an app-owned modal is present, or a visible dialog is detected from Apple's UserNotificationCenter, SecurityAgent, or CoreServicesUIAgent. It restores the effect when the dialog closes without restarting capture. Detection uses app identity and visible window metadata, not dialog text or Accessibility access. Other applications' arbitrary dialogs are not classified by this guard.

The optional finish sound is an original 0.76-second stereo swish and glass chord, bundled in `Resources/fold-finish.wav`. **Preview** plays it without enabling capture. Automatic playback is muted while a detected system prompt is visible. Recreate the asset with `xcrun swift native/Tools/GenerateFoldSound.swift native/Resources/fold-finish.wav` from the repository root.

## Lid-angle support

The sensor reader looks only for an Apple HID device with vendor `0x05AC`, usage page `0x20`, and usage `0x8A`, then reads feature report 1. This private hardware interface is not guaranteed by Apple and is absent or inaccessible on some MacBook generations. The settings screen reports actual availability; turn off **Follow MacBook lid** to use the manual 15–120° demo on unsupported hardware. Foldly polls the sensor while running and makes no zero-cost-idle claim.

## Renderer regression checks

Run `zsh native/Tests/run-motion-tests.sh` for configurable thresholds, both capture modes, preference persistence, startup/teardown ordering, and frame-rate-independent motion tests.

Run `zsh native/Tests/run-renderer-harness.sh` in a graphical macOS session. This uses the actual overlay controller with a generated four-color image, checks that its Metal view attaches to a nonzero-sized window, verifies colored pixels across 90 GPU frames, and checks reopening and reclosing without a new frame. It also injects a completion failure to verify immediate hide/clear. It does not request Screen Recording or capture your desktop.

Also run `zsh native/Tests/run-renderer-harness.sh --show --no-readback` and verify the folded red, green, blue, and white pattern is visible. This holds the window for 45 seconds and deliberately disables GPU readback: texture contents alone cannot prove that macOS presents the window correctly. The original black-screen bug rendered valid textures after attaching Metal to a zero-sized panel, but displayed a black surface. Foldly now creates the panel at the built-in display's size before attaching its Metal view.

The local build is ad-hoc signed, so recompiling can invalidate its existing Screen Recording grant. Refresh only Foldly's entry and approve the rebuilt app in System Settings when needed. This does not replace signing and notarization for distribution.

Add `--animate` to the visual command to cycle through the fold using the website’s 4.2-second rhythm. The no-readback run reports completed GPU frames over its initial three seconds.
