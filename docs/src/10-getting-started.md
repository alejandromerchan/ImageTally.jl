# Getting Started

## Installation

ImageTally.jl is not yet registered in the Julia General Registry.
Install it directly from GitHub:

```julia
julia> # press ] to enter Pkg mode
pkg> add https://github.com/alejandromerchan/ImageTally.jl
```

To use the interactive GUI, also install GLMakie and FileIO:

```julia
pkg> add GLMakie FileIO
```

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
| `R` key | Reset the view |

### Control panel

The panel on the right side of the window provides:

- **Active tag indicator** — shows which tag will be used for new markers.
- **Tag buttons** — click a tag's button to make it the active tag.
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

Available marker shapes include `:circle`, `:rect`, `:diamond`, `:utriangle`,
`:dtriangle`, `:star5`, `:cross`, `:xcross`, and others supported by Makie.

## Programmatic API

All session operations are available without opening a window, which is useful for
scripting, batch processing, or building custom tools on top of ImageTally.

### Creating a session

```julia
using ImageTally

tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
sess = new_session("moths.jpg", 3456, 5184; tags)
```

When GLMakie is loaded, `new_session` can read image dimensions automatically:

```julia
using GLMakie, ImageTally

sess = new_session("moths.jpg"; tags)
```

### Adding, moving, and deleting points

All coordinates are in pixels relative to the top-left corner of the image.

```julia
# Add points — uses the currently active tag
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
add_tag!(sess, Tag("juvenile", :green, :star5))
has_tag(sess, "juvenile")   # true
get_tag(sess, "juvenile")   # Tag("juvenile", :green, :star5)
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

## Next steps

- See the [Reference](95-reference.md) page for the complete API documentation.
- See the [Contributing guide](90-contributing.md) if you want to contribute to the package.
