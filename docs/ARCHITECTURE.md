# OpenFlo Architecture

## Performance Model

Flow cytometry data is naturally a table of events by channels. OpenFlo stores this as a structure-of-arrays:

```text
FSC-A: [Float, Float, Float, ...]
SSC-A: [Float, Float, Float, ...]
CD3:   [Float, Float, Float, ...]
```

This is better than an array of event objects because plotting and gating usually touch only two or a few channels at a time. Each channel is contiguous in memory, cache friendly, and easy to process in parallel.

For 1,000,000 events and 30 channels, `Float32` storage is about 120 MB before metadata and masks. A gate mask is a bitset, so 1,000,000 events need about 125 KB per population mask.

## Gating

Gates are stored as operations in a population tree. Each evaluated gate produces an `EventMask`, a compact `[UInt64]` bitset. Compound populations are boolean operations on masks:

- `and`: parent population plus child gate
- `or`: union of selected gates
- `not`: exclusion gates

The important rule is lazy evaluation: only recompute masks when the underlying data, transform, or gate geometry changes.

## Visualization

OpenFlo should not render millions of individual circles. The efficient path is rasterization:

1. Transform the two selected channels.
2. Bin events into a fixed 2D histogram, usually 512x512 or 1024x1024.
3. Color-map the bins into a bitmap.
4. Draw the bitmap and gate overlays in the UI.

This keeps interaction bounded by the image resolution rather than the number of events. For very large data, the app can cache histograms by population, axes, transforms, and plot size.

## GPU Acceleration

GPU acceleration matters most for:

- interactive pan/zoom over very large plots
- repeated transform plus binning at high resolution
- image compositing and multi-layer overlays

On Apple Silicon, Metal is the eventual native path. The current prototype uses multi-core CPU histogramming because it is simpler, deterministic, and already fast for common 1 to 10 million event workloads. The design keeps visualization isolated so a Metal histogram backend can replace the CPU backend later.

## Multi-Core CPU

The first implementation uses `DispatchQueue` workers to split event ranges across available CPU cores. Each worker creates a private histogram, then the partial histograms are reduced. This avoids atomic increments in the hot loop.

## File Formats

Milestone 1 reads common FCS files:

- FCS 2.0, 3.0, 3.1 style homogeneous `$DATATYPE`
- `F`, `D`, and common integer widths
- little-endian and big-endian byte order

FCS 3.2 mixed per-channel data types are part of the planned parser work.

## Packaging

SwiftPM produces the app executable. `scripts/package_dmg.sh` creates a minimal `.app` bundle and wraps it into a DMG with `hdiutil`. Public releases should add:

- Developer ID signing
- hardened runtime
- notarization
- stapling
