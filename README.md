# Foldly

A dependency-free interactive playground for Foldly, a macOS companion that gives the desktop a physical fold as a MacBook lid closes.

## Run locally

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

## Native companion

The macOS companion lives in [`native/`](native/README.md). Build the app and create the downloadable archive from the repository root:

```sh
./native/build.sh
```
