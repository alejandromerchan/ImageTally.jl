# ImageTally

[![Stable Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://alejandromerchan.github.io/ImageTally.jl/stable)
[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://alejandromerchan.github.io/ImageTally.jl/dev)
[![Test workflow status](https://github.com/alejandromerchan/ImageTally.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/alejandromerchan/ImageTally.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/alejandromerchan/ImageTally.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/alejandromerchan/ImageTally.jl)
[![Lint workflow Status](https://github.com/alejandromerchan/ImageTally.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/alejandromerchan/ImageTally.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow Status](https://github.com/alejandromerchan/ImageTally.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/alejandromerchan/ImageTally.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![DOI](https://zenodo.org/badge/DOI/FIXME)](https://doi.org/FIXME)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)
[![All Contributors](https://img.shields.io/github/all-contributors/alejandromerchan/ImageTally.jl?labelColor=5e1ec7&color=c0ffee&style=flat-square)](#contributors)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

**ImageTally.jl** is a Julia package for manually counting and categorizing objects in scientific images. It provides an interactive GUI (via GLMakie) for point-and-click counting, as well as a programmatic API for scripting, batch processing, and data export.

Typical use cases include counting insects on traps, cells in microscopy images, plants in field photographs, or any other discrete objects in high-resolution images.

## Features

- **Interactive GUI** — left-click to place markers, right-click to delete, left-drag to move. Scroll or use the zoom buttons to zoom in/out; press `R` or click **Reset View** to restore the full image.
- **Multiple tags** — define up to 10 named categories (e.g., `"male"`, `"female"`, `"egg"`), each with its own color and marker shape.
- **Session persistence** — save and reload counting sessions as TOML files so work can be interrupted and resumed.
- **CSV export** — export all counted points with both relative (0–1) and pixel coordinates, plus timestamps.
- **Programmatic API** — create and manipulate sessions entirely in code, without opening a window.

## Installation

ImageTally.jl is not yet registered in the Julia General Registry. Install it directly from GitHub:

```julia
julia> # press ]
pkg> add https://github.com/alejandromerchan/ImageTally.jl
```

To use the interactive GUI, also install GLMakie and FileIO:

```julia
pkg> add GLMakie FileIO
```

> **Platform note:** The GLMakie-based GUI extension is officially tested on Linux only.
> It may work on macOS and Windows, but those platforms are not covered by the CI suite.

## Quick Start

### GUI (interactive counting)

```julia
using GLMakie   # must be loaded before ImageTally to activate the GUI extension
using ImageTally

# Launch the counter — image dimensions are read automatically
fig, sess = launch_counter("path/to/image.jpg")

# Or resume a previous session
fig, sess = launch_counter("path/to/image.jpg"; session="image_session.toml")
```

**Controls:**

| Action | Result |
| ------ | ------ |
| Left-click (empty area) | Add point with active tag |
| Left-drag (on a point) | Move that point |
| Right-click (on a point) | Delete that point |
| Scroll wheel | Zoom in / out |
| `- Zoom Out` / `Zoom In +` buttons | Zoom out / in (1.5× per click) |
| `R` key or `Reset View` button | Restore full-image view |

Use the control panel on the right to switch the active tag, adjust marker size, and save/load/export.

### Programmatic API

```julia
using ImageTally

# Create a session with custom tags
tags = [
    Tag("egg",         :red,    :circle),
    Tag("parasitized", :blue,   :utriangle),
    Tag("empty",       :gray,   :diamond),
]
sess = new_session("image.jpg", 4032, 3024; tags)

# Add points at pixel coordinates (integers or floats are both accepted)
add_point!(sess, 512, 300)         # uses the active tag ("egg")
set_active_tag!(sess, "parasitized")
add_point!(sess, 1024.0, 800.0)

# Query counts
count_by_tag(sess)   # Dict("egg" => 1, "parasitized" => 1, "empty" => 0)
total_count(sess)    # 2

# Save and reload
save_session(sess, "my_count.toml")
sess2 = load_session("my_count.toml")

# Export to CSV (id, tag, x_relative, y_relative, x_pixel, y_pixel, timestamp)
export_csv(sess, "my_count.csv")

# Human-readable summary
println(session_summary(sess))
```

When GLMakie is loaded, `new_session` can also infer image dimensions automatically:

```julia
using GLMakie, ImageTally
sess = new_session("image.jpg")                  # dimensions read from file
sess = new_session("image.jpg"; tags = tags)     # with custom tags
fig, sess = launch_counter(sess)                  # launch GUI from a pre-built session
```

## Documentation

- [Stable docs](https://alejandromerchan.github.io/ImageTally.jl/stable)
- [Development docs](https://alejandromerchan.github.io/ImageTally.jl/dev)

## How to Cite

If you use ImageTally.jl in your work, please cite using the reference given in [CITATION.cff](https://github.com/alejandromerchan/ImageTally.jl/blob/main/CITATION.cff).

## Contributing

If you want to make contributions of any kind, please first take a look at our [contributing guide directly on GitHub](docs/src/90-contributing.md) or the [contributing page on the website](https://alejandromerchan.github.io/ImageTally.jl/dev/90-contributing/).

---

### Contributors

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
