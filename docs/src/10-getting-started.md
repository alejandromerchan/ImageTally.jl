# Getting Started

## Installation

```julia
julia> # press ] to enter Pkg mode
pkg> add ImageTally
```

To use the interactive GUI, also install GLMakie and FileIO:

```julia
pkg> add GLMakie FileIO
```

### Supported image formats

Any format that FileIO can load is accepted: JPEG, PNG, TIF/TIFF, BMP, and others.
TIF files are fully supported, including multi-channel and single-channel variants that
some TIF loaders return as 3-dimensional arrays — ImageTally normalises these automatically
before display.

## Interactive GUI

The graphical counter requires GLMakie to be loaded **before** `ImageTally`.
GLMakie activates an extension inside the package that provides the GUI.

### Launching the counter

```julia
using GLMakie
using ImageTally

# Start a new session — image dimensions are read automatically from the file
fig, sess = launch_counter("path/to/image.jpg")
```

A window opens displaying the image on the left and a control panel on the right.
`launch_counter` returns the Makie `Figure` and the live `CountSession`; the
window stays interactive for as long as the Julia session is running.

### Mouse and keyboard controls

| Action | Result |
| ------ | ------ |
| Left-click on empty area | Place a marker with the active tag |
| Left-drag on an existing marker | Move that marker |
| Right-click on an existing marker | Delete that marker |
| Scroll wheel | Zoom in / out |
| `- Zoom Out` / `Zoom In +` buttons | Zoom out / in (1.5× per click) |
| `R` key or `Reset View` button | Restore the full-image view |

### Control panel

The panel on the right side of the window provides:

- **Active tag indicator** — shows which tag will be used for new markers.
- **Tag buttons** — click a tag's button to make it the active tag.
- **Zoom buttons** — `- Zoom Out`, `Reset View`, and `Zoom In +` buttons for explicit zoom control (each step is 1.5×). The scroll wheel and `R` key also work.
- **Marker size slider** — adjust the display size of all markers (5–40 px).
- **Counts display** — live per-tag and total counts.
- **Save session** — writes a `.toml` file next to the image (e.g. `image_session.toml`).
- **Load session** — reloads the TOML file saved alongside the current image.
- **Export CSV** — writes a `.csv` file next to the image (e.g. `image_counts.csv`).

### Resuming a previous session

```julia
using GLMakie, ImageTally

fig, sess = launch_counter("image.jpg"; session = "image_session.toml")
```

### Using custom tags

Define tags before launching to control names, colors, and marker shapes:

```julia
using GLMakie, ImageTally

tags = [
    Tag("egg",         :red,    :circle),
    Tag("parasitized", :blue,   :utriangle),
    Tag("empty",       :gray,   :diamond),
]
sess = new_session("image.jpg"; tags)
fig, sess = launch_counter(sess)
```

The eight supported marker shapes are `:circle`, `:utriangle`, `:dtriangle`,
`:rect`, `:diamond`, `:xcross`, `:cross`, and `:pentagon`.
Other Makie symbols are accepted with a runtime warning.

## Programmatic API

All session operations are available without opening a window, which is useful for
scripting, batch processing, or building custom tools on top of ImageTally.

### Creating a session

The base `new_session` requires the image dimensions in pixels.
There are two ways to supply them.

**Option 1 — with GLMakie (recommended):** loading GLMakie activates an extension
that adds a `new_session(path; tags)` overload. It reads the image file via FileIO
and extracts the dimensions automatically:

```julia
using GLMakie, ImageTally

tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
sess = new_session("moths.jpg"; tags)
```

**Option 2 — without GLMakie:** pass the dimensions explicitly. If you already know
them (e.g., from your imaging pipeline), pass them directly. Otherwise, use FileIO
to read them:

```julia
using FileIO, ImageTally

# size() on a loaded image returns (height, width)
img = FileIO.load("moths.jpg")
h, w = size(img)

tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
sess = new_session("moths.jpg", w, h; tags)
```

### Adding, moving, and deleting points

All coordinates are in pixels relative to the top-left corner of the image.

```julia
# Add points — uses the currently active tag
# Both integers and floats are accepted for pixel coordinates
add_point!(sess, 512, 300)
add_point!(sess, 512.0, 300.0)

# Switch active tag
set_active_tag!(sess, "female")
add_point!(sess, 1024.0, 800.0)

# Move a point by its id
move_point!(sess, 1, 520.0, 310.0)

# Delete a point by its id
delete_point!(sess, 2)

# Find the point nearest to a pixel location (within 50 px by default)
pt = find_nearest_point(sess, 515.0, 305.0)
```

### Querying counts

```julia
count_by_tag(sess)   # Dict("male" => 1, "female" => 0)
total_count(sess)    # 1
println(session_summary(sess))
```

### Managing tags

```julia
add_tag!(sess, Tag("juvenile", :green, :pentagon))
has_tag(sess, "juvenile")   # true
get_tag(sess, "juvenile")   # Tag("juvenile", :green, :pentagon)
remove_tag!(sess, "juvenile")
```

### Saving, loading, and exporting

```julia
# Save the full session to a TOML file
save_session(sess, "moths_session.toml")

# Reload from a TOML file
sess2 = load_session("moths_session.toml")

# Export counted points to CSV
# Columns: id, tag, x_relative, y_relative, x_pixel, y_pixel, timestamp
export_csv(sess, "moths_counts.csv")
```

The TOML format preserves all session state (image path, dimensions, tags, points, and
settings) so a session can be resumed exactly where it was left off.

### Input validation

ImageTally validates arguments at the boundary of the public API and throws
`ArgumentError` with a descriptive message for clearly invalid inputs:

| Call | What is checked |
| ---- | --------------- |
| `Tag(name, color, marker)` | `name` must not be empty. An unknown `marker` symbol produces a `@warn` but still succeeds. |
| `new_session(path, w, h)` | `path` must not be empty; `w` and `h` must be positive. |
| `set_active_tag!(sess, name)` | `name` must exist in the session's tag list. |
| `set_marker_size!(sess, size)` | `size` must be positive. Values above 200 produce a `@warn`. |
| `add_tag!(sess, tag)` | Tag name must not already exist; total tag count must not exceed `MAX_TAGS` (10). |
| `remove_tag!(sess, name)` | Cannot remove a tag that has counted points. |
| `save_session` / `load_session` | Path must have a `.toml` extension; file must exist for loading. |
| `export_csv` | Path must have a `.csv` extension. |

## Next steps

- See the [Reference](95-reference.md) page for the complete API documentation.
- See the [Contributing guide](90-contributing.md) if you want to contribute to the package.
