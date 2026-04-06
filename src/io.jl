# src/io.jl
using TOML: TOML
using Dates: Dates, DateTime

# -----------------------------------------------------------------------
# Session save / load
# -----------------------------------------------------------------------

"""
    save_session(session, path) -> Nothing

Save a `CountSession` to a TOML file at `path`. The session can be
reloaded with `load_session`. The image file is not saved — only its
path and dimensions are recorded.

# Examples
```julia
save_session(session, "my_count.toml")
```
"""
function save_session(session::CountSession, path::String)
    endswith(path, ".toml") ||
        throw(ArgumentError("Session file must have a .toml extension, got: $path"))

    data = Dict(
        "image_path" => session.image_path,
        "image_width" => session.image_width,
        "image_height" => session.image_height,
        "active_tag" => session.active_tag,
        "marker_size" => session.marker_size,
        "tags" => [
            Dict(
                "name" => t.name,
                "color" => string(t.color),
                "marker" => string(t.marker),
            ) for t in session.tags
        ],
        "points" => [
            Dict(
                "id" => p.id,
                "x" => p.x,
                "y" => p.y,
                "tag" => p.tag,
                "timestamp" => string(p.timestamp),
            ) for p in session.points
        ],
    )

    open(path, "w") do io
        TOML.print(io, data)
    end

    return nothing
end

"""
    load_session(path) -> CountSession

Load a `CountSession` from a TOML file previously saved with `save_session`.

# Examples
```julia
session = load_session("my_count.toml")
```
"""
function load_session(path::String)
    isfile(path) || throw(ArgumentError("Session file not found: $path"))
    endswith(path, ".toml") ||
        throw(ArgumentError("Session file must have a .toml extension, got: $path"))

    data = TOML.parsefile(path)

    tags = [Tag(t["name"], Symbol(t["color"]), Symbol(t["marker"])) for t in data["tags"]]

    points = [
        CountPoint(p["id"], p["x"], p["y"], p["tag"], DateTime(p["timestamp"])) for
        p in data["points"]
    ]

    return CountSession(
        data["image_path"],
        data["image_width"],
        data["image_height"],
        tags,
        points,
        isempty(points) ? 1 : maximum(p.id for p in points) + 1,
        data["active_tag"],
        data["marker_size"],
    )
end

# -----------------------------------------------------------------------
# CSV export
# -----------------------------------------------------------------------

"""
    export_csv(session, path) -> Nothing

Export the counted points to a CSV file at `path`. Each row represents
one counted point with its relative coordinates, pixel coordinates,
tag, and timestamp.

The CSV includes both relative (0.0-1.0) and absolute pixel coordinates
so the data is useful regardless of how the image is displayed.

# Examples
```julia
export_csv(session, "my_count.csv")
```
"""
function export_csv(session::CountSession, path::String)
    endswith(path, ".csv") ||
        throw(ArgumentError("Export file must have a .csv extension, got: $path"))

    open(path, "w") do io
        # Header
        println(io, "id,tag,x_relative,y_relative,x_pixel,y_pixel,timestamp")

        # One row per point
        for point in session.points
            x_px, y_px = relative_to_pixel(
                point.x,
                point.y,
                session.image_width,
                session.image_height,
            )
            println(
                io,
                "$(point.id),$(point.tag),$(point.x),$(point.y),$x_px,$y_px,$(point.timestamp)",
            )
        end
    end

    return nothing
end

"""
    session_summary(session) -> String

Return a human-readable summary of the session as a string.

# Examples
```julia
println(session_summary(session))
```
"""
function session_summary(session::CountSession)
    counts = count_by_tag(session)
    lines = [
        "Image: $(basename(session.image_path))",
        "Size: $(session.image_width) × $(session.image_height) pixels",
        "Total points: $(total_count(session))",
        "Counts by tag:",
    ]
    for tag in session.tags
        push!(lines, "  $(tag.name): $(counts[tag.name])")
    end
    return join(lines, "\n")
end
