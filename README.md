# OpenFlo

OpenFlo is an open source, Mac-first flow cytometry analysis app prototype. This first milestone focuses on the hard foundation: loading event tables, keeping millions of events responsive, rendering density plots, and evaluating gates with multi-core CPU work.

## Current Scope

- Native macOS SwiftUI app targeting Apple Silicon.
- Pure Swift core with a columnar event table.
- Basic FCS reader for common FCS 2.0/3.x homogeneous numeric files.
- Multi-core 2D density histogram renderer.
- Rectangle/polygon gate evaluation backed by a compact bitset mask.
- DMG packaging script using SwiftPM and `hdiutil`.

## Build

```sh
swift build -c release
```

## Run During Development

```sh
swift run OpenFlo
```

## Verify Core Logic

```sh
swift run OpenFloCoreSmokeTests
```

## Create a DMG

```sh
./scripts/package_dmg.sh
```

The unsigned DMG is written to `dist/OpenFlo.dmg`. For public distribution outside the App Store, the `.app` and `.dmg` should be signed and notarized with an Apple Developer ID certificate.

## Architecture Notes

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
