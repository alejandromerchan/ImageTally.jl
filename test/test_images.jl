# test/test_images.jl
using FileIO
using ImageIO
using ImageMagick
using Colors
using FixedPointNumbers

const FIXTURES = joinpath(@__DIR__, "fixtures")

@testset "Image format support" begin

    @testset "JPEG loading" begin
        path = joinpath(FIXTURES, "small_rgb.jpg")
        img = FileIO.load(path)

        # Basic properties
        @test ndims(img) == 2
        @test size(img, 1) == 64
        @test size(img, 2) == 64

        # JPEG is RGB
        @test eltype(img) <: RGB

        # Session creation from JPEG
        h, w = size(img)
        sess = new_session(path, w, h)
        @test sess.image_width == w
        @test sess.image_height == h
        @test sess.image_path == path
    end

    @testset "PNG loading" begin
        path = joinpath(FIXTURES, "small_rgb.png")
        img = FileIO.load(path)

        @test ndims(img) == 2
        @test size(img, 1) == 64
        @test size(img, 2) == 64
        @test eltype(img) <: RGB

        # PNG is lossless — pixel values are exact
        # Top-left pixel: i=1,j=1 → red=0.8, green=mod(1,64)/64=1/64≈0.016, blue=0.5
        @test img[1, 1] ≈ RGB{N0f8}(0.8, 1 / 64, 0.5) atol = 0.01

        h, w = size(img)
        sess = new_session(path, w, h)
        @test total_count(sess) == 0
    end

    @testset "TIFF 8-bit RGB loading" begin
        path = joinpath(FIXTURES, "small_rgb.tif")
        img = FileIO.load(path)

        @test ndims(img) == 2
        @test size(img, 1) == 64
        @test size(img, 2) == 64
        @test eltype(img) <: RGB

        h, w = size(img)
        sess = new_session(path, w, h)
        @test sess.image_width == w
        @test sess.image_height == h
    end

    @testset "TIFF 8-bit grayscale loading" begin
        path = joinpath(FIXTURES, "small_gray8.tif")
        img = FileIO.load(path)

        @test ndims(img) == 2
        @test size(img, 1) == 64
        @test size(img, 2) == 64
        @test eltype(img) <: Gray

        # Grayscale images should still work for session creation
        h, w = size(img)
        sess = new_session(path, w, h)
        @test sess.image_width == w
        @test sess.image_height == h
    end

    @testset "TIFF 16-bit grayscale loading" begin
        path = joinpath(FIXTURES, "small_gray16.tif")
        img = FileIO.load(path)

        @test ndims(img) == 2
        @test size(img, 1) == 64
        @test size(img, 2) == 64

        # Must be 16-bit
        @test eltype(img) <: Gray{N0f16}

        h, w = size(img)
        sess = new_session(path, w, h)
        @test sess.image_width == w
        @test sess.image_height == h
    end

    @testset "BMP loading" begin
        path = joinpath(FIXTURES, "small_rgb.bmp")
        try
            img = FileIO.load(path)

            @test ndims(img) == 2
            @test size(img, 1) == 64
            @test size(img, 2) == 64

            h, w = size(img)
            sess = new_session(path, w, h)
            @test sess.image_width == w
            @test sess.image_height == h
        catch e
            @warn "BMP loading not available: $e"
        end
    end

    @testset "Coordinate round trip across formats" begin
        # Verify that coordinate conversion works correctly
        # regardless of image format
        for filename in ["small_rgb.png", "small_rgb.tif", "small_gray8.tif"]
            path = joinpath(FIXTURES, filename)
            img = FileIO.load(path)
            h, w = size(img)
            sess = new_session(path, w, h)

            # Add a point at the center
            add_point!(sess, Float64(w / 2), Float64(h / 2))
            @test length(sess.points) == 1
            @test sess.points[1].x ≈ 0.5 atol = 0.02
            @test sess.points[1].y ≈ 0.5 atol = 0.02

            # Round trip through save/load
            tmp = tempname() * ".toml"
            try
                save_session(sess, tmp)
                sess2 = load_session(tmp)
                @test sess2.points[1].x ≈ sess.points[1].x
                @test sess2.points[1].y ≈ sess.points[1].y
                @test sess2.image_width == w
                @test sess2.image_height == h
            finally
                isfile(tmp) && rm(tmp)
            end
        end
    end

end
