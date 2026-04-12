# test/generate_fixtures.jl
# Run once to generate test fixture images:
#   julia --project=test test/generate_fixtures.jl

using FileIO
using ImageIO
using ImageMagick
using Colors
using FixedPointNumbers

function generate_fixtures(dir = joinpath(@__DIR__, "fixtures"))
    mkpath(dir)

    # 64x64 RGB checkerboard — visually distinct, covers all pixel positions
    img_rgb = [
        RGB{N0f8}((i + j) % 2 == 0 ? 0.8 : 0.2, Float32(mod(i * j, 64)) / 64, 0.5) for
        i = 1:64, j = 1:64
    ]

    save(joinpath(dir, "small_rgb.jpg"), img_rgb)
    save(joinpath(dir, "small_rgb.png"), img_rgb)
    save(joinpath(dir, "small_rgb.tif"), img_rgb)
    save(joinpath(dir, "small_rgb.bmp"), img_rgb)

    # 64x64 grayscale 8-bit TIFF — common in microscopy
    img_gray8 = Gray{N0f8}.(img_rgb)
    save(joinpath(dir, "small_gray8.tif"), img_gray8)

    # 64x64 grayscale 16-bit TIFF — common in scientific imaging
    img_gray16 = Gray{N0f16}.(img_rgb)
    save(joinpath(dir, "small_gray16.tif"), img_gray16)

    println("Generated fixtures in $dir:")
    for f in readdir(dir)
        path = joinpath(dir, f)
        println("  $f ($(filesize(path)) bytes)")
    end
end

generate_fixtures()
