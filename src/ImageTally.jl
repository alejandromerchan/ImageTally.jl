module ImageTally

export Tag, CountPoint, CountSession
export DEFAULT_MARKER_SIZE, MAX_TAGS
export pixel_to_relative, relative_to_pixel, clamp_to_image
export new_session, add_point!, delete_point!, move_point!
export find_nearest_point, count_by_tag, total_count
export set_active_tag!, set_marker_size!
export get_tag, has_tag, add_tag!, remove_tag!
export default_tags

include("types.jl")
include("coordinates.jl")
include("session.jl")

end
