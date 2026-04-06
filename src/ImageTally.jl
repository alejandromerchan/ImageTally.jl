module ImageTally

using Dates: Dates, DateTime
using TOML: TOML

export Tag, CountPoint, CountSession
export DEFAULT_MARKER_SIZE, MAX_TAGS
export pixel_to_relative, relative_to_pixel, clamp_to_image
export new_session, add_point!, delete_point!, move_point!
export find_nearest_point, count_by_tag, total_count
export set_active_tag!, set_marker_size!
export get_tag, has_tag, add_tag!, remove_tag!
export default_tags
export save_session, load_session, export_csv, session_summary
export launch_counter

include("types.jl")
include("coordinates.jl")
include("session.jl")
include("io.jl")

"""
    launch_counter(args...; kwargs...)

Launch the ImageTally graphical counting interface.
Requires GLMakie to be loaded first:
```julia
using GLMakie
using ImageTally
launch_counter("path/to/image.jpg")
```
"""
function launch_counter(args...; kwargs...)
    throw(
        ArgumentError(
            "launch_counter requires GLMakie to be loaded. " *
            "Run `using GLMakie` before calling this function.",
        ),
    )
end

end
