using Dates

"""
    Tag

Represents a user-defined counting category with visual properties.

# Fields
- `name::String`: Display name (e.g. "male", "female", "egg")
- `color::Symbol`: Marker color (e.g. :red, :blue)
- `marker::Symbol`: Marker shape (e.g. :circle, :utriangle)
"""
struct Tag
    name::String
    color::Symbol
    marker::Symbol
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
    CountSession

Holds all state for a single counting session.

# Fields
- `image_path::String`: Path to the image file
- `image_width::Int`: Original image width in pixels
- `image_height::Int`: Original image height in pixels
- `tags::Vector{Tag}`: Available counting categories
- `points::Vector{CountPoint}`: All counted points
- `next_id::Int`: Counter for generating unique point IDs
- `active_tag::String`: Currently selected tag name
- `marker_size::Float64`: Display size of markers
"""
mutable struct CountSession
    image_path::String
    image_width::Int
    image_height::Int
    tags::Vector{Tag}
    points::Vector{CountPoint}
    next_id::Int
    active_tag::String
    marker_size::Float64
end
