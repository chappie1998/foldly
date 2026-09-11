# Contributing to Foldly

Bug reports, hardware compatibility reports, and pull requests are welcome.

## Local setup

For the native app, use an Apple silicon Mac running macOS 14 or newer with Apple's Command Line Tools installed:

```sh
./native/build.sh
./native/build/Foldly.app/Contents/MacOS/Foldly --self-test
```

For the web playground, install Node.js and run `npm run dev`. There are no third-party package dependencies.

## Checks

For native rendering changes, run these in a graphical macOS session:

```sh
zsh native/Tests/run-gradient-tests.sh
zsh native/Tests/run-renderer-harness.sh
zsh native/Tests/run-motion-tests.sh
```

For web changes, run `npm test` and `npm run build`. Keep pull requests focused and describe the behavior changed and checks run.

## Reporting a bug

Include the Foldly version, macOS version, MacBook model, selected style, and whether you were using the lid sensor or manual angle. For permission errors, mention whether you installed a release or rebuilt locally; rebuilding can invalidate an ad-hoc signed app's previous grant. See [INSTALL.md](INSTALL.md#if-permission-keeps-being-requested).

Use a generated test pattern when possible. If you attach a screenshot, remove private desktop content first. Foldly should keep captured frames in memory, stop capture when paused or disabled, and hide its overlay during system permission prompts.

## License and attribution

Contributions are provided under the project's [MIT license](LICENSE). Keep the original concept attribution in the README. Include the source and license for any assets you add.
