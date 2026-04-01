"""
    pixel_to_relative(x_px, y_px, width, height) -> Tuple{Float64, Float64}

Convert pixel coordinates to relative coordinates (0.0 to 1.0).

# Examples
```julia
pixel_to_relative(1728, 2592, 3456, 5184)  # (0.5, 0.5)
```
"""
function pixel_to_relative(x_px::Real, y_px::Real, width::Int, height::Int)
    return (Float64(x_px) / width, Float64(y_px) / height)
end

"""
    relative_to_pixel(x_rel, y_rel, width, height) -> Tuple{Int, Int}

Convert relative coordinates (0.0 to 1.0) to pixel coordinates.

# Examples
```julia
relative_to_pixel(0.5, 0.5, 3456, 5184)  # (1728, 2592)
```
"""
function relative_to_pixel(x_rel::Float64, y_rel::Float64, width::Int, height::Int)
    return (round(Int, x_rel * width), round(Int, y_rel * height))
end

"""
    clamp_to_image(x_rel, y_rel) -> Tuple{Float64, Float64}

Clamp relative coordinates to valid image range (0.0 to 1.0).
Handles clicks slightly outside the image boundary.
"""
function clamp_to_image(x_rel::Float64, y_rel::Float64)
    return (clamp(x_rel, 0.0, 1.0), clamp(y_rel, 0.0, 1.0))
end