using Dates

"""
    default_tags() -> Vector{Tag}

Return a default set of two tags to use when no tags are specified.
"""
function default_tags()
    return [Tag("object", :red, :circle)]
end

"""
    new_session(image_path, width, height; tags=default_tags()) -> CountSession

Create a new counting session for the given image.

# Examples
```julia
session = new_session("moths.jpg", 3456, 5184)
session = new_session("moths.jpg", 3456, 5184; tags=[Tag("male", :blue, :circle), Tag("female", :red, :utriangle)])
```
"""
function new_session(
    image_path::String,
    width::Int,
    height::Int;
    tags::Vector{Tag} = default_tags(),
)
    isempty(tags) && throw(ArgumentError("Session must have at least one tag"))
    return CountSession(
        image_path,
        width,
        height,
        tags,
        CountPoint[],
        1,
        tags[1].name,
        12.0,
    )
end

"""
    add_point!(session, x_px, y_px) -> CountPoint

Add a new point at the given pixel coordinates using the active tag.
Coordinates are converted to relative and clamped to valid range.

# Examples
```julia
add_point!(session, 1728.0, 2592.0)
```
"""
function add_point!(session::CountSession, x_px::Float64, y_px::Float64)
    x_rel, y_rel = pixel_to_relative(x_px, y_px, session.image_width, session.image_height)
    x_rel, y_rel = clamp_to_image(x_rel, y_rel)
    point =
        CountPoint(session.next_id, x_rel, y_rel, session.active_tag, string(Dates.now()))
    push!(session.points, point)
    session.next_id += 1
    return point
end

"""
    delete_point!(session, id) -> Bool

Delete the point with the given id. Returns true if found and deleted,
false if no point with that id exists.

# Examples
```julia
delete_point!(session, 1)
```
"""
function delete_point!(session::CountSession, id::Int)
    idx = findfirst(p -> p.id == id, session.points)
    isnothing(idx) && return false
    deleteat!(session.points, idx)
    return true
end

"""
    move_point!(session, id, x_px, y_px) -> Bool

Move the point with the given id to new pixel coordinates.
Returns true if found and moved, false if no point with that id exists.

# Examples
```julia
move_point!(session, 1, 1800.0, 2600.0)
```
"""
function move_point!(session::CountSession, id::Int, x_px::Float64, y_px::Float64)
    idx = findfirst(p -> p.id == id, session.points)
    isnothing(idx) && return false
    x_rel, y_rel = pixel_to_relative(x_px, y_px, session.image_width, session.image_height)
    x_rel, y_rel = clamp_to_image(x_rel, y_rel)
    old = session.points[idx]
    session.points[idx] = CountPoint(old.id, x_rel, y_rel, old.tag, old.timestamp)
    return true
end

"""
    find_nearest_point(session, x_px, y_px; threshold=50.0) -> Union{CountPoint, Nothing}

Find the nearest point to the given pixel coordinates within the threshold distance.
Returns nothing if no point is within the threshold.

# Examples
```julia
point = find_nearest_point(session, 1728.0, 2592.0)
```
"""
function find_nearest_point(
    session::CountSession,
    x_px::Float64,
    y_px::Float64;
    threshold::Float64 = 50.0,
)
    isempty(session.points) && return nothing

    nearest = nothing
    min_dist = Inf

    for point in session.points
        px, py =
            relative_to_pixel(point.x, point.y, session.image_width, session.image_height)
        dist = sqrt((px - x_px)^2 + (py - y_px)^2)
        if dist < min_dist
            min_dist = dist
            nearest = point
        end
    end

    return min_dist <= threshold ? nearest : nothing
end

"""
    count_by_tag(session) -> Dict{String, Int}

Return a dictionary with the count of points for each tag.

# Examples
```julia
count_by_tag(session)  # Dict("male" => 5, "female" => 3)
```
"""
function count_by_tag(session::CountSession)
    counts = Dict(tag.name => 0 for tag in session.tags)
    for point in session.points
        counts[point.tag] = get(counts, point.tag, 0) + 1
    end
    return counts
end

"""
    set_active_tag!(session, tag_name) -> Nothing

Set the active tag by name. Throws ArgumentError if tag doesn't exist.

# Examples
```julia
set_active_tag!(session, "female")
```
"""
function set_active_tag!(session::CountSession, tag_name::String)
    any(t -> t.name == tag_name, session.tags) ||
        throw(ArgumentError("Tag \"$tag_name\" not found in session tags"))
    session.active_tag = tag_name
    return nothing
end
