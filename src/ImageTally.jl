module ImageTally

export Tag, CountPoint, CountSession
export pixel_to_relative, relative_to_pixel, clamp_to_image
export new_session, add_point!, delete_point!, move_point!
export find_nearest_point, count_by_tag, set_active_tag!
export default_tags

include("types.jl")
include("coordinates.jl")
include("session.jl")

end
