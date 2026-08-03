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

### Scale calibration

A session can record a scale: a segment of the image whose real-world length you
know — a scale bar, a ruler, a stage micrometer — from which pixel distances can
be converted into real units.

Calibrate with `set_scale!`, giving the two endpoints in pixel coordinates (the
same coordinates `add_point!` takes), the real-world distance between them, and
its unit:

```julia
# A scale bar running from (100, 900) to (200, 900) is 2 mm long
set_scale!(sess, 100.0, 900.0, 200.0, 900.0, 2.0, "mm")

sess.has_scale              # true
scale_pixel_distance(sess)  # 100.0
```

The endpoints are stored as relative coordinates (0.0–1.0), exactly like counted
points, so they survive any change in how the image is displayed. The pixel
distance is not stored: `scale_pixel_distance` derives it from the endpoints and
the image dimensions, so there is only one source of truth.

With a calibration in place, distances convert in both directions:

```julia
pixels_to_real(sess, 50.0)   # 1.0  — 50 px is 1 mm
real_to_pixels(sess, 1.0)    # 50.0 — 1 mm is 50 px
```

Both throw an `ArgumentError` if the session has no scale, so an uncalibrated
session cannot silently produce meaningless numbers.

Calling `set_scale!` again replaces the calibration. `clear_scale!` removes it,
leaving points and tags untouched:

```julia
clear_scale!(sess)
sess.has_scale   # false
```

`set_scale!` and `clear_scale!` are the only supported ways to change the
session's scale fields — assigning to `sess.scale_unit` or `sess.has_scale`
directly bypasses validation and can leave the session inconsistent.

#### Units

The recognised units are `nm`, `μm`, `mm`, `cm`, `m`, and `in`, available as
`VALID_UNITS`. Common spellings are canonicalised, case-insensitively, so `um`,
`Micron`, `microns`, and `micrometre` all become `μm`, and `inches` becomes `in`.

The micro prefix is stored as U+03BC (GREEK SMALL LETTER MU). The visually
identical U+00B5 (MICRO SIGN) is rewritten to it, which keeps one experiment's
data from splitting into two groups that look the same on screen.

A unit outside the list is accepted with a warning and stored as given. This is
deliberate: not every reference object is a scale bar, and calibrating against a
grid square or a body length is legitimate.

```julia
set_scale!(sess, 0.0, 0.0, 100.0, 0.0, 1.0, "grid square")  # warns, but calibrates
```

A calibration is saved and restored with the session — see below.

### Saving, loading, and exporting

```julia
# Save the full session to a TOML file
save_session(sess, "moths_session.toml")

# Reload from a TOML file
sess2 = load_session("moths_session.toml")

# Export counted points to CSV
export_csv(sess, "moths_counts.csv")
```

The TOML format preserves all session state (image path, dimensions, tags, points,
scale calibration, and settings) so a session can be resumed exactly where it was
left off. A session with no calibration writes no `[scale]` table at all, and
session files written by earlier versions of ImageTally load as uncalibrated.

#### The CSV schema

`export_csv` writes one of two schemas, chosen by whether the session has a
calibration. Without one it writes seven columns, exactly as every earlier
version of ImageTally did:

```text
id,tag,x_relative,y_relative,x_pixel,y_pixel,timestamp
```

With a calibration it writes ten, inserting `x_real`, `y_real`, and `unit`
before `timestamp` and leaving every existing column where it was:

```text
id,tag,x_relative,y_relative,x_pixel,y_pixel,x_real,y_real,unit,timestamp
```

`x_real` and `y_real` are the pixel coordinates converted through the
calibration. `unit` is the session's canonical unit repeated on every row — a
session calibrated in `um` exports `μm`. The unit is a column rather than a
suffix on the column names (`x_mm`) because a unit is free-form: `grid squares`
would make an unusable column name, and as data the unit survives any parse and
keeps rows pooled from differently calibrated images from silently mixing
dimensions.

The calibration endpoints themselves are not exported — they are metadata about
the measurement, not count data, and they live in the session TOML.

Values are written at full `Float64` precision, without rounding; formatting is
left to whatever reads the file. Tags, units, and timestamps are escaped per
RFC 4180, so a tag named `eggs, parasitized` round-trips through any standard
CSV reader instead of silently shifting the columns after it.

!!! warning "`x_real` and `y_real` are offsets, not positions"
    A scale converts **distances**, not positions. `x_real` is the distance
    from the left edge of the image and `y_real` the distance from its top, so
    the origin is the corner of the photograph — wherever the camera happened
    to be framed. That is arbitrary and not comparable between images. `y_real`
    increases downward, following the image convention rather than the
    mathematical one. Absolute values are therefore not meaningful;
    differences are.

So these are valid uses of `x_real` and `y_real`:

- the distance between two counted points;
- the extent of a bounding box around a group of points;
- an area, for a density calculation.

And this is not: treating the values as coordinates in any external reference
frame. Nothing in the data will contradict a reading of `x_real = 4.7 mm` as a
position rather than an offset, so it is worth being deliberate about it.

#### A worked example: density from the exported columns

Every quantity below is a *difference* of exported values, which is what makes
it well defined:

```julia
using CSV

rows = CSV.File("moths_counts.csv")
unit = first(rows.unit)          # "mm"

# Extent of the counted region — a difference, so the arbitrary origin cancels
width_real = maximum(rows.x_real) - minimum(rows.x_real)
height_real = maximum(rows.y_real) - minimum(rows.y_real)

density = length(rows) / (width_real * height_real)
println("$(round(density; digits = 3)) points per square $unit")
```

The distance between two counted points works the same way:

```julia
dx = rows.x_real[2] - rows.x_real[1]
dy = rows.y_real[2] - rows.y_real[1]
separation = sqrt(dx^2 + dy^2)   # in `unit`
```

Equivalently, without exporting: `pixels_to_real(sess, hypot(dx_px, dy_px))`.

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
| `set_scale!(sess, x1, y1, x2, y2, dist, unit)` | `dist` must be positive; `unit` must not be empty; the two points must not be coincident after clamping. A unit outside `VALID_UNITS` produces a `@warn` but still succeeds. |
| `pixels_to_real(sess, px)` | The session must have a scale calibration. |
| `real_to_pixels(sess, dist)` | The session must have a scale calibration. |
| `save_session` / `load_session` | Path must have a `.toml` extension; file must exist for loading. A `[scale]` table in the file must be complete and well-formed. |
| `export_csv` | Path must have a `.csv` extension. |

## Next steps

- See the [Reference](95-reference.md) page for the complete API documentation.
- See the [Contributing guide](90-contributing.md) if you want to contribute to the package.
