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
- `3` — adds the optional `[scale]` table and the top-level `next_id` key.
  Both are read with a default, so version 1 and 2 files load unchanged.

`load_session` accepts any version up to this one and rejects anything
higher, so a file written by a newer ImageTally fails loudly instead of
loading with fields silently dropped.
"""
const SESSION_FORMAT_VERSION = 3

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

`next_id` is written out rather than re-derived on load. Deriving it from
the highest point id means deleting the highest-numbered points and
reloading silently rewinds the counter, so new points reuse ids that a
previously exported CSV already refers to.

A `[scale]` table is written only when the session has a calibration, so a
session without one is structurally unchanged from a version-2 file apart
from the version number and `next_id`:

```toml
[scale]
real_distance = 1.0
unit = "mm"
point_1 = [0.123, 0.456]
point_2 = [0.789, 0.456]
```

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
        "next_id" => session.next_id,
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

    # Omitted entirely when there is no calibration, so the absence of the
    # table is what "no scale" looks like on disk — there is no second way to
    # say it and nothing to keep in step with `has_scale`.
    if session.has_scale
        data["scale"] = Dict(
            "real_distance" => session.scale_real_distance,
            "unit" => session.scale_unit,
            # TOML has no tuple type.
            "point_1" => collect(session.scale_point_1),
            "point_2" => collect(session.scale_point_2),
        )
    end

    open(path, "w") do io
        TOML.print(io, data; sorted = true)
    end

    return nothing
end

"""
    require_key(data, key, path; table = "")

Return `data[key]`, or throw an `ArgumentError` naming the missing key and the
file it was expected in. Used instead of a bare index so a truncated or
hand-edited session file produces an actionable message rather than a raw
`KeyError`.

`table` qualifies the key name in the message for keys that live in a sub-table,
so a missing `[scale]` key is reported as `"scale.unit"` rather than the
ambiguous `"unit"`.
"""
function require_key(data::AbstractDict, key::String, path::String; table::String = "")
    haskey(data, key) && return data[key]
    name = isempty(table) ? key : "$table.$key"
    throw(ArgumentError("Session file is missing required key \"$name\": $path"))
end

"""
    parse_scale_point(value, key, path) -> Tuple{Float64, Float64}

Convert a `[scale]` endpoint read from TOML into a relative-coordinate tuple.
Throws an `ArgumentError` — never a `BoundsError` or `MethodError` — when the
value is not a 2-element array of numbers, so a hand-edited `[scale]` table
fails the same way every other malformed session key does.
"""
function parse_scale_point(value, key::String, path::String)
    (value isa AbstractVector && length(value) == 2 && all(v -> v isa Real, value)) ||
        throw(
            ArgumentError(
                "Session file key \"scale.$key\" must be a 2-element array of relative coordinates, got: $value — $path",
            ),
        )
    return (Float64(value[1]), Float64(value[2]))
end

"""
    scale_fields(data, path) -> NamedTuple

Read the optional `[scale]` table into the `CountSession` scale keywords.

Returns the uncalibrated defaults when the table is absent, which is every
version 1 and version 2 session file. When it is present all four keys are
required and validated: a partial or malformed table is a corrupt file, not a
session with a half-set scale.

The unit is normalised on read, so a file written by an older ImageTally or
edited by hand carries a canonical unit in memory regardless of what is on disk.
"""
function scale_fields(data::AbstractDict, path::String)
    scale = get(data, "scale", nothing)
    isnothing(scale) && return (;
        has_scale = false,
        scale_real_distance = 0.0,
        scale_unit = "",
        scale_point_1 = (0.0, 0.0),
        scale_point_2 = (0.0, 0.0),
    )

    real_distance = require_key(scale, "real_distance", path; table = "scale")
    real_distance > 0 || throw(
        ArgumentError(
            "Session file key \"scale.real_distance\" must be positive, got $real_distance: $path",
        ),
    )

    unit = require_key(scale, "unit", path; table = "scale")

    return (;
        has_scale = true,
        scale_real_distance = Float64(real_distance),
        scale_unit = normalize_unit(unit),
        scale_point_1 = parse_scale_point(
            require_key(scale, "point_1", path; table = "scale"),
            "point_1",
            path,
        ),
        scale_point_2 = parse_scale_point(
            require_key(scale, "point_2", path; table = "scale"),
            "point_2",
            path,
        ),
    )
end

"""
    stored_next_id(data, points, path) -> Int

Return the id counter to load the session with.

Version 3 files store `next_id`; older files do not, and fall back to the value
derived from the points — `max(id) + 1` — which is what every version of
`load_session` has used. A stored value below the derived one would hand out ids
that already exist, so the derived value wins and the discrepancy is reported.
"""
function stored_next_id(data::AbstractDict, points::Vector{CountPoint}, path::String)
    derived = isempty(points) ? 1 : maximum(p.id for p in points) + 1
    stored = get(data, "next_id", derived)

    stored isa Integer || throw(
        ArgumentError(
            "Session file key \"next_id\" must be an integer, got: $stored — $path",
        ),
    )

    stored < derived &&
        @warn "Session file records a next_id below the highest point id — new points would reuse ids that already exist, so the derived value is used instead" path =
            path stored_next_id = stored derived_next_id = derived

    return max(stored, derived)
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

A `[scale]` table is optional: a file without one loads with `has_scale = false`
and the default scale fields, which is every version 1 and version 2 file. When
the table is present, all four of its keys are required and its unit is
canonicalised — see [`scale_fields`](@ref).

`next_id` is likewise optional, and falls back to the derived `max(id) + 1` for
older files — see [`stored_next_id`](@ref).

# Throws
- `ArgumentError` if the file does not exist or is not a `.toml` file.
- `ArgumentError` if `format_version` is newer than this version of ImageTally.
- `ArgumentError` if a required key is missing.
- `ArgumentError` if a `[scale]` table is present but incomplete or malformed.

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
        next_id = stored_next_id(data, points, path),
        active_tag = require_key(data, "active_tag", path),
        marker_size = require_key(data, "marker_size", path),
        scale_fields(data, path)...,
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
