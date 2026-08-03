using Dates: Dates, DateTime

"""
Valid GLMakie marker symbols accepted by ImageTally.
"""
const VALID_MARKERS =
    (:circle, :utriangle, :dtriangle, :rect, :diamond, :xcross, :cross, :pentagon)

"""
Canonical length units recognised by ImageTally's scale calibration.

The micro prefix is U+03BC (GREEK SMALL LETTER MU), not the visually identical
U+00B5 (MICRO SIGN). Unicode NFKC normalisation maps U+00B5 onto U+03BC, so
U+03BC is the canonical form; [`normalize_unit`](@ref) rewrites the other one.

Units outside this set are accepted with a warning — see
[`normalize_unit`](@ref) — so unusual reference objects (a grid square, a body
length) are not blocked.
"""
const VALID_UNITS = ("nm", "μm", "mm", "cm", "m", "in")

"""
    Tag

Represents a user-defined counting category with visual properties.

# Fields
- `name::String`: Display name (e.g. "male", "female", "egg"). Must not be empty.
- `color::Symbol`: Marker color (e.g. `:red`, `:blue`, `:green`). GLMakie accepts any
  named color; commonly used values include `:red`, `:blue`, `:green`, `:orange`,
  `:purple`, `:cyan`, `:magenta`, `:yellow`, `:black`, `:white`, `:gray`.
- `marker::Symbol`: Marker shape (e.g. `:circle`, `:utriangle`). Known supported markers
  are $(VALID_MARKERS). A warning is issued for unrecognised symbols.

# Throws
- `ArgumentError` if `name` is empty.
"""
struct Tag
    name::String
    color::Symbol
    marker::Symbol

    function Tag(name::String, color::Symbol, marker::Symbol)
        isempty(name) && throw(ArgumentError("Tag name must not be empty"))
        marker in VALID_MARKERS ||
            @warn "Unknown marker :$marker — supported markers are: $(join(string.(":", collect(VALID_MARKERS)), ", "))"
        new(name, color, marker)
    end
end

"""
    CountPoint

Represents a single counted object in the image.

# Fields
- `id::Int`: Unique identifier
- `x::Float64`: Relative x position (0.0 to 1.0)
- `y::Float64`: Relative y position (0.0 to 1.0)
- `tag::String`: Name of the associated Tag
- `timestamp::DateTime
"""
struct CountPoint
    id::Int
    x::Float64
    y::Float64
    tag::String
    timestamp::DateTime
end

"""
    CountSession(; image_path, image_width, image_height, active_tag, kwargs...)

Holds all state for a single counting session.

Construct with keywords. `image_path`, `image_width`, `image_height`, and
`active_tag` are required; the rest default. Requiring those four means there
is no zero-argument constructor, so a session cannot be built without the
information needed to make it internally consistent. The positional
constructor is also available, but prefer the keyword form — it survives
new fields being added.

Field values are not validated here. Validation lives at the entry points
(`new_session`, `load_session`, and the mutating helpers), which is where the
context to produce a good error message exists.

# Required keywords
- `image_path::String`: Path to the image file
- `image_width::Int`: Original image width in pixels
- `image_height::Int`: Original image height in pixels
- `active_tag::String`: Currently selected tag name

# Optional keywords
- `tags::Vector{Tag} = default_tags()`: Available counting categories
- `points::Vector{CountPoint} = CountPoint[]`: All counted points
- `next_id::Int = 1`: Counter for generating unique point IDs
- `marker_size::Float64 = DEFAULT_MARKER_SIZE`: Display size of markers

# Scale calibration keywords

A session with `has_scale = false` — the default — carries no calibration and
behaves exactly as a session did before calibration existed.

- `has_scale::Bool = false`: Whether a scale calibration is set. This is the
  authoritative flag; the other scale fields are meaningless when it is `false`.
- `scale_real_distance::Float64 = 0.0`: Real-world distance between the two
  scale points, in `scale_unit`.
- `scale_unit::String = ""`: Unit of `scale_real_distance`, canonicalised by
  [`normalize_unit`](@ref). Known units are $(VALID_UNITS).
- `scale_point_1::Tuple{Float64,Float64} = (0.0, 0.0)`: First scale endpoint, in
  relative coordinates (0.0 to 1.0).
- `scale_point_2::Tuple{Float64,Float64} = (0.0, 0.0)`: Second scale endpoint, in
  relative coordinates (0.0 to 1.0).

The endpoints are stored relative, exactly like a `CountPoint`, so they survive
any change in how the image is displayed. The pixel distance between them is
**not** stored — it is derived by [`scale_pixel_distance`](@ref), so there is one
source of truth.

!!! warning "Do not mutate the scale fields directly"
    [`set_scale!`](@ref) and [`clear_scale!`](@ref) are the only supported ways
    to change any `scale_*` field or `has_scale`. Assigning to them directly
    bypasses validation and can leave the session inconsistent — for example a
    `has_scale = true` session whose endpoints are coincident, which makes every
    conversion undefined.

# Examples
```julia
session = CountSession(;
    image_path = "moths.jpg",
    image_width = 3456,
    image_height = 5184,
    active_tag = "object",
)
```
"""
Base.@kwdef mutable struct CountSession
    image_path::String
    image_width::Int
    image_height::Int
    tags::Vector{Tag} = default_tags()
    points::Vector{CountPoint} = CountPoint[]
    next_id::Int = 1
    active_tag::String
    marker_size::Float64 = DEFAULT_MARKER_SIZE
    has_scale::Bool = false
    scale_real_distance::Float64 = 0.0
    scale_unit::String = ""
    scale_point_1::Tuple{Float64,Float64} = (0.0, 0.0)
    scale_point_2::Tuple{Float64,Float64} = (0.0, 0.0)
end
