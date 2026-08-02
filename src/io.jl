# src/io.jl
using TOML: TOML
using Dates: Dates, DateTime

# -----------------------------------------------------------------------
# Session format versioning
# -----------------------------------------------------------------------

"""
Session file format version written by this version of ImageTally.

Version history:
- `1` — implicit; written by ImageTally v0.1.0, which had no `format_version`
  key at all. Absence of the key means version 1.
- `2` — adds the `format_version` and `image_file_size` keys.

`load_session` accepts any version up to this one and rejects anything
higher, so a file written by a newer ImageTally fails loudly instead of
loading with fields silently dropped.
"""
const SESSION_FORMAT_VERSION = 2

"""
Format version assumed when a session file has no `format_version` key.
Every ImageTally v0.1.0 session file falls in this category.
"""
const LEGACY_SESSION_FORMAT_VERSION = 1

# -----------------------------------------------------------------------
# Session save / load
# -----------------------------------------------------------------------

"""
    save_session(session, path) -> Nothing

Save a `CountSession` to a TOML file at `path`. The session can be
reloaded with `load_session`. The image file is not saved — only its
path, dimensions, and size in bytes are recorded.

The size in bytes of the image file is recorded as `image_file_size` so
`load_session` can warn if the image has changed since the session was
saved. If the image file does not exist at save time, the key is omitted
rather than the save failing — a session is still worth saving without
its image.

Keys are written sorted, so a session file is reproducible and diffable.

# Examples
```julia
save_session(session, "my_count.toml")
```
"""
function save_session(session::CountSession, path::String)
    endswith(path, ".toml") ||
        throw(ArgumentError("Session file must have a .toml extension, got: $path"))

    data = Dict(
        "format_version" => SESSION_FORMAT_VERSION,
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

    # Omitted when the image is absent — the session is still valid without it.
    if isfile(session.image_path)
        data["image_file_size"] = filesize(session.image_path)
    end

    open(path, "w") do io
        TOML.print(io, data; sorted = true)
    end

    return nothing
end

"""
    require_key(data, key, path)

Return `data[key]`, or throw an `ArgumentError` naming the missing key and the
file it was expected in. Used instead of a bare index so a truncated or
hand-edited session file produces an actionable message rather than a raw
`KeyError`.
"""
function require_key(data::AbstractDict, key::String, path::String)
    haskey(data, key) ||
        throw(ArgumentError("Session file is missing required key \"$key\": $path"))
    return data[key]
end

"""
    check_image_file_size(session, expected_size)

Warn if the image file has changed size since the session was saved.

Silent when `expected_size` is `nothing` (a v0.1.0 file, which recorded no
size) or when the image file is not present — `load_session` has never
required the image to exist, and headless analysis where the session travels
without its image is supported. Never throws: a size mismatch is suspicious,
not invalid.
"""
function check_image_file_size(session::CountSession, expected_size)
    isnothing(expected_size) && return nothing
    isfile(session.image_path) || return nothing

    actual_size = filesize(session.image_path)
    actual_size == expected_size && return nothing

    @warn "Image file size does not match the saved session — the image may have been re-saved, edited, or replaced, and counted points may no longer correspond to it" image_path =
        session.image_path expected_size = expected_size actual_size = actual_size

    return nothing
end

"""
    load_session(path) -> CountSession

Load a `CountSession` from a TOML file previously saved with `save_session`.

Session files written by ImageTally v0.1.0 load unchanged: they carry no
`format_version` key, which is read as version 1. A file whose
`format_version` is newer than this ImageTally understands is rejected
rather than loaded with fields silently dropped.

The image file itself is not required to exist. If it does, and the session
recorded its size, a mismatch produces a warning — see
[`check_image_file_size`](@ref).

# Throws
- `ArgumentError` if the file does not exist or is not a `.toml` file.
- `ArgumentError` if `format_version` is newer than this version of ImageTally.
- `ArgumentError` if a required key is missing.

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

    # Absence of the key means version 1 — every v0.1.0 file.
    version = get(data, "format_version", LEGACY_SESSION_FORMAT_VERSION)
    version > SESSION_FORMAT_VERSION && throw(
        ArgumentError(
            "Session file format version $version is newer than this version of ImageTally supports (up to $SESSION_FORMAT_VERSION) — upgrade ImageTally to open it: $path",
        ),
    )

    # TODO: this does not check that `tags` is non-empty or that `active_tag`
    # names one of them. Both gaps are real, but tightening them here risks
    # rejecting session files that load today.
    tags = [
        Tag(t["name"], Symbol(t["color"]), Symbol(t["marker"])) for
        t in require_key(data, "tags", path)
    ]

    points = [
        CountPoint(p["id"], p["x"], p["y"], p["tag"], DateTime(p["timestamp"])) for
        p in require_key(data, "points", path)
    ]

    session = CountSession(;
        image_path = require_key(data, "image_path", path),
        image_width = require_key(data, "image_width", path),
        image_height = require_key(data, "image_height", path),
        tags = tags,
        points = points,
        next_id = isempty(points) ? 1 : maximum(p.id for p in points) + 1,
        active_tag = require_key(data, "active_tag", path),
        marker_size = require_key(data, "marker_size", path),
    )

    check_image_file_size(session, get(data, "image_file_size", nothing))

    return session
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
