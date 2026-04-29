# Changelog

## v0.7.0-alpha - 2026-04-29

This alpha release expands OpenFlo from a basic flow cytometry workspace into a broader FlowJo-style analysis prototype with layout reporting, single-cell matrix import, signature scoring, richer plot modes, and substantial performance work.

### Layout Editor

- Added a FlowJo-inspired layout editor with a menu/ribbon toolbar, object tools, layout list, iteration controls, batch controls, and a right-side properties panel.
- Added draggable layout objects for plots, text, shapes, lines, and statistics table placeholders.
- Added direct selection, deselection, Delete-key deletion, context deletion, movement, z-order controls, and resize handles for layout items.
- Added page grid/page break rendering to represent printed pages, plus scrollbars that activate once plot content exists.
- Added layout zoom controls with magnifier buttons and preset percentage choices.
- Added layout PNG export and batch HTML image output.
- Added batch layout creation with sample iteration controls.
- Added plot properties for plot type, axis selection, grid display, ancestry thumbnails, axis font size, and axis color.
- Added layout plot overlays: dropping another sample or gate onto an existing plot adds it to the same graph with distinct colors instead of creating a second stacked plot.

### Plotting And Axes

- Added plot modes for contour, density, zebra, pseudocolor, heatmap statistic, dot plot, histogram, and CDF.
- Restored the histogram option on the Y-axis control so axes can switch into one-dimensional histogram display.
- Added density, dot plot, overlay dot plot, CDF, and raster image renderers.
- Added richer axis transform editing and automatic/focused range helpers.
- Improved default axis selection for flow data and single-cell signature score channels.
- Added plot-window mode controls and kept one-dimensional plots from exposing irrelevant Y-axis settings.

### Single-Cell Matrix Support

- Added delimited and Matrix Market single-cell matrix parsing.
- Added a signature selection dialog when importing single-cell matrices.
- Added bundled PBMC and default immune signature sets.
- Added custom/loaded signature support and signature merging.
- Added Seqtometry-style signature scoring and appended signature score channels.
- Added progress reporting while loading matrices and computing signatures.
- Added a single-cell demo downloader entry point.

### Layout Performance Fixes

- Reworked single-cell layout plot rendering so layout previews use a small two-channel sampled table instead of carrying the full gene matrix into every render.
- Kept single-cell layout plots in pseudocolor by default instead of forcing dot plot mode.
- Added fast bitset-based sampling for gated single-cell populations.
- Added channel index and signature channel caches to avoid repeated full gene-list scans.
- Optimized single-cell overlay plots so overlays sample the needed channels instead of rendering full matrices.
- Prevented incompatible stale flow gates/templates from being applied to single-cell matrices after deleting and reloading samples.
- Cleared layout snapshot and gate mask caches when deleting samples or gates.

### Workspace, Tables, And Gates

- Added JSON-backed `.openflo` workspace save/load support.
- Added table/statistics output for counts, percent parent, percent total, median, mean, and geometric mean.
- Added table export paths for text, CSV, and HTML with optional heat-map formatting.
- Added group gate propagation and compatibility checks across samples.
- Added cached gate masks to avoid repeated gate re-evaluation.
- Improved gate evaluation parallelism and histogram worker limits.
- Added support for additional gate tools and interaction refinements.

### Packaging And Verification

- Expanded the DMG packaging script to build a universal macOS app bundle, copy resources, generate icons, and customize the DMG window.
- Added bundled signature resources to the app package.
- Expanded smoke tests for FCS parsing, text/matrix parsing, signature scoring, and core rendering/gating logic.
