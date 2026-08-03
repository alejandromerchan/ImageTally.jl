# src/scale.jl
# Scale calibration: unit handling, setting and clearing a calibration, and
# converting between pixel and real-world distances.

# -----------------------------------------------------------------------
# Unit handling
# -----------------------------------------------------------------------

"""
Aliases accepted for the canonical units in `VALID_UNITS`, looked up in lower
case. The canonical units appear as their own aliases so that case variants
("MM", "Micron") normalise too.
"""
const UNIT_ALIASES = Dict{String,String}(
    "nm" => "nm",
    "nanometer" => "nm",
    "nanometers" => "nm",
    "nanometre" => "nm",
    "nanometres" => "nm",
    "μm" => "μm",
    "um" => "μm",
    "micron" => "μm",
    "microns" => "μm",
    "micrometer" => "μm",
    "micrometers" => "μm",
    "micrometre" => "μm",
    "micrometres" => "μm",
    "mm" => "mm",
    "millimeter" => "mm",
    "millimeters" => "mm",
    "millimetre" => "mm",
    "millimetres" => "mm",
    "cm" => "cm",
    "centimeter" => "cm",
    "centimeters" => "cm",
    "centimetre" => "cm",
    "centimetres" => "cm",
    "m" => "m",
    "meter" => "m",
    "meters" => "m",
    "metre" => "m",
    "metres" => "m",
    "in" => "in",
    "inch" => "in",
    "inches" => "in",
)

"""
The MICRO SIGN (U+00B5) and the GREEK SMALL LETTER MU (U+03BC) render
identically but are different codepoints. Unicode NFKC normalisation maps the
former onto the latter, so U+03BC is the canonical form ImageTally stores.

Written as escapes on purpose: the two characters are indistinguishable on
screen, so literals here would be unreviewable and one stray copy-paste away
from being wrong.
"""
const MICRO_SIGN = '\u00b5'
const GREEK_SMALL_LETTER_MU = '\u03bc'

"""
    normalize_unit(unit) -> String

Return the canonical form of a length unit.

Surrounding whitespace is stripped, the MICRO SIGN (U+00B5) is rewritten to the
GREEK SMALL LETTER MU (U+03BC), and common aliases (`um`, `micron`,
`millimetre`, `inches`, …) are mapped to their entry in `VALID_UNITS`,
case-insensitively. A unit already in `VALID_UNITS` is returned unchanged.

Anything else is returned as given, with a warning. This is deliberate: a scale
bar is not the only reference object in practice, and a session calibrated
against a grid square or a body length is legitimate. The warning exists so an
unintended unit does not pass silently, not to block one.

Accepts any `AbstractString` — unit strings often arrive as a `SubString` from
`split` or from parsed input.

# Examples
```julia
normalize_unit("mm")        # "mm"
normalize_unit(" um ")      # "μm"
normalize_unit("Microns")   # "μm"
normalize_unit("Inches")    # "in"
```

# Throws
- `ArgumentError` if the unit is empty or only whitespace.
"""
function normalize_unit(unit::AbstractString)
    stripped = strip(unit)
    isempty(stripped) && throw(ArgumentError("Scale unit must not be empty"))

    # Always applied: the two micro codepoints must never split one user's data
    # into two groups with no visible cause.
    canonical = replace(String(stripped), MICRO_SIGN => GREEK_SMALL_LETTER_MU)

    canonical in VALID_UNITS && return canonical

    alias = get(UNIT_ALIASES, lowercase(canonical), nothing)
    isnothing(alias) || return alias

    @warn "Unrecognised unit \"$canonical\" — recognised units are: $(join(VALID_UNITS, ", ")). Storing it as given."
    return canonical
end

# -----------------------------------------------------------------------
# Setting and clearing a calibration
# -----------------------------------------------------------------------

"""
    scale_pixel_distance(session) -> Float64

Return the Euclidean distance in pixels between the two scale points, or `0.0`
when the session has no scale.

The distance is derived from the stored relative endpoints and the image
dimensions rather than stored, so it cannot drift out of agreement with them.

# Examples
```julia
session = new_session("moths.jpg", 1000, 1000)
set_scale!(session, 100.0, 100.0, 200.0, 100.0, 2.0, "mm")
scale_pixel_distance(session)   # 100.0
```
"""
function scale_pixel_distance(session::CountSession)
    session.has_scale || return 0.0
    dx = (session.scale_point_2[1] - session.scale_point_1[1]) * session.image_width
    dy = (session.scale_point_2[2] - session.scale_point_1[2]) * session.image_height
    return sqrt(dx^2 + dy^2)
end

"""
    set_scale!(session, x1_px, y1_px, x2_px, y2_px, real_distance, unit) -> Nothing

Calibrate the session by declaring that the segment between two pixel
coordinates spans `real_distance` in `unit`.

The endpoints are given in pixel coordinates, matching `add_point!`, and are
converted to relative coordinates and clamped to the image before being stored.
Calling this on an already-calibrated session replaces the calibration.

The unit is canonicalised by [`normalize_unit`](@ref), which warns — but does
not throw — for a unit outside `VALID_UNITS`.

# Examples
```julia
# A 100 px scale bar that is 2 mm long
set_scale!(session, 100.0, 900.0, 200.0, 900.0, 2.0, "mm")
set_scale!(session, 100, 900, 200, 900, 2, "mm")
```

# Throws
- `ArgumentError` if `real_distance` is not positive.
- `ArgumentError` if `unit` is empty.
- `ArgumentError` if the two points are coincident after clamping — a zero pixel
  distance makes every conversion undefined. Two distinct points outside the
  image can clamp to the same location, so the check happens after clamping.
"""
function set_scale!(
    session::CountSession,
    x1_px::Real,
    y1_px::Real,
    x2_px::Real,
    y2_px::Real,
    real_distance::Real,
    unit::AbstractString,
)
    real_distance > 0 ||
        throw(ArgumentError("Scale distance must be positive, got $real_distance"))

    canonical_unit = normalize_unit(unit)

    p1 = clamp_to_image(
        pixel_to_relative(x1_px, y1_px, session.image_width, session.image_height)...,
    )
    p2 = clamp_to_image(
        pixel_to_relative(x2_px, y2_px, session.image_width, session.image_height)...,
    )

    p1 == p2 && throw(
        ArgumentError(
            "Scale points must not be coincident — both clamp to ($(p1[1]), $(p1[2])) in relative coordinates, giving a zero pixel distance",
        ),
    )

    session.scale_point_1 = p1
    session.scale_point_2 = p2
    session.scale_real_distance = Float64(real_distance)
    session.scale_unit = canonical_unit
    session.has_scale = true

    return nothing
end

"""
    clear_scale!(session) -> Nothing

Remove the session's scale calibration, resetting every scale field to its
default. Points, tags, and every other field are left untouched. Calling this on
a session with no scale is a no-op, not an error.

# Examples
```julia
clear_scale!(session)
session.has_scale   # false
```
"""
function clear_scale!(session::CountSession)
    session.has_scale = false
    session.scale_real_distance = 0.0
    session.scale_unit = ""
    session.scale_point_1 = (0.0, 0.0)
    session.scale_point_2 = (0.0, 0.0)
    return nothing
end

# -----------------------------------------------------------------------
# Conversions
# -----------------------------------------------------------------------

"""
    require_scale(session, what)

Throw an `ArgumentError` naming `what` if `session` has no scale calibration.
"""
function require_scale(session::CountSession, what::String)
    session.has_scale ||
        throw(ArgumentError("$what requires a scale calibration — call set_scale! first"))
    return nothing
end

"""
    pixels_to_real(session, px_distance) -> Float64

Convert a distance in pixels to the session's real-world unit.

# Examples
```julia
# 100 px calibrated as 2.0 mm
pixels_to_real(session, 50.0)   # 1.0
```

# Throws
- `ArgumentError` if the session has no scale calibration.
"""
function pixels_to_real(session::CountSession, px_distance::Real)
    require_scale(session, "pixels_to_real")
    return Float64(px_distance) * session.scale_real_distance /
           scale_pixel_distance(session)
end

"""
    real_to_pixels(session, real_distance) -> Float64

Convert a distance in the session's real-world unit to pixels. The exact inverse
of [`pixels_to_real`](@ref).

# Examples
```julia
# 100 px calibrated as 2.0 mm
real_to_pixels(session, 1.0)   # 50.0
```

# Throws
- `ArgumentError` if the session has no scale calibration.
"""
function real_to_pixels(session::CountSession, real_distance::Real)
    require_scale(session, "real_to_pixels")
    return Float64(real_distance) * scale_pixel_distance(session) /
           session.scale_real_distance
end
