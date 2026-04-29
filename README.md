# OpenFlo

OpenFlo is an open source, Mac-first flow cytometry analysis app prototype. This first milestone focuses on the hard foundation: loading event tables, keeping millions of events responsive, rendering density plots, and evaluating gates with multi-core CPU work.

> - If you are trying to install from the precompiled .dmg - you will need to put the app into your applications folder, and then type:
> xattr -dr com.apple.quarantine /Applications/OpenFlo.app

## Current Scope

- Native macOS SwiftUI app targeting Apple Silicon.
- Pure Swift core with a columnar event table.
- Basic FCS reader for common FCS 2.0/3.x homogeneous numeric files.
- Multi-core 2D density histogram renderer.
- Rectangle/polygon gate evaluation backed by a compact bitset mask.
- FlowJo-style workspace workflow with group-applied gates, plot windows, layout reports, table/statistic output, and JSON-backed `.openflo` workspace saves.
- Layout Editor reports with draggable graph/text/shape/table items, sample iteration, batch layout generation, PNG export, and HTML image batches.
- Table Editor output for counts, parent/total percentages, median, mean, and geometric mean with optional heat-map formatting and text/CSV/HTML export.
- DMG packaging script using SwiftPM and `hdiutil`.

<img width="500" height="500" alt="ChatGPT Image Apr 24, 2026, 10_18_49 PM" src="https://github.com/user-attachments/assets/6e0ac627-6641-4ec9-9084-05d8ecd3c402" />

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
