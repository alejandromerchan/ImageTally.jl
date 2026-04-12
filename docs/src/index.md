```@meta
CurrentModule = ImageTally
```

# ImageTally

**ImageTally.jl** is a Julia package for manually counting and categorizing objects in scientific images.
It provides an interactive point-and-click GUI (powered by [GLMakie](https://docs.makie.org/stable/)) and a
full programmatic API for scripting and batch workflows.

Typical use cases include counting insects on sticky traps, cells in microscopy images, plants in
aerial photographs, or any other discrete objects in high-resolution images.

## Features

- **Interactive GUI** — place, move, and delete markers with the mouse; zoom and pan with the scroll wheel.
- **Multiple tags** — define up to 10 named categories, each with its own color and marker shape.
- **Session persistence** — save and reload work-in-progress sessions as portable TOML files.
- **CSV export** — export all counted points with relative and pixel coordinates plus timestamps.
- **Programmatic API** — create and manipulate sessions entirely in code, no window required.
- **Multiple image formats** — JPEG, PNG, TIFF (8-bit and 16-bit),
  and BMP. Large images tested up to 18 megapixels.

## Getting started

See the [Getting Started](10-getting-started.md) page for installation instructions and a step-by-step walkthrough.

## API reference

The [Reference](95-reference.md) page lists all exported functions and types with their docstrings.

## Contributors

```@raw html
<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
```
