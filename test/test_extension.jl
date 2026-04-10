# test/test_extension.jl
#
# Integration tests for the GLMakie extension.
# These require GLMakie and FileIO to be loaded so the extension fires.
# No display is needed — only new_session is tested here (no GUI window opened).

using GLMakie
using FileIO

@testset "GLMakie extension" begin

    # Helper: write a synthetic PNG (h × w pixels) and return its path.
    function synthetic_image(h, w)
        img = fill(GLMakie.RGB(1.0f0, 0.0f0, 0.0f0), h, w)
        path = tempname() * ".png"
        FileIO.save(path, img)
        return path
    end

    @testset "new_session(path) — reads dimensions from file" begin
        path = synthetic_image(480, 640)   # height=480, width=640
        try
            sess = new_session(path)

            @test sess.image_path == path
            @test sess.image_width == 640
            @test sess.image_height == 480
            @test length(sess.tags) == 1          # default_tags → one tag
            @test sess.active_tag == sess.tags[1].name
            @test isempty(sess.points)
            @test sess.marker_size == DEFAULT_MARKER_SIZE
        finally
            isfile(path) && rm(path)
        end
    end

    @testset "new_session(path; tags) — custom tags preserved" begin
        path = synthetic_image(300, 500)
        tags = [Tag("egg", :red, :circle), Tag("parasitized", :blue, :utriangle)]
        try
            sess = new_session(path; tags = tags)

            @test sess.image_width == 500
            @test sess.image_height == 300
            @test length(sess.tags) == 2
            @test sess.tags[1].name == "egg"
            @test sess.tags[2].name == "parasitized"
            @test sess.active_tag == "egg"
        finally
            isfile(path) && rm(path)
        end
    end

    @testset "new_session(path) — non-square image" begin
        # Portrait orientation
        path = synthetic_image(1000, 200)
        try
            sess = new_session(path)
            @test sess.image_width == 200
            @test sess.image_height == 1000
        finally
            isfile(path) && rm(path)
        end
    end

    @testset "new_session(path) — file not found" begin
        @test_throws ArgumentError new_session("/nonexistent/path/image.jpg")
    end

    @testset "new_session(path) — empty tags rejected" begin
        path = synthetic_image(100, 100)
        try
            @test_throws ArgumentError new_session(path; tags = Tag[])
        finally
            isfile(path) && rm(path)
        end
    end

    @testset "launch_counter(sess) — file not found" begin
        # Build a session pointing at a path that no longer exists.
        path = synthetic_image(100, 100)
        sess = new_session(path)
        rm(path)   # delete the file so launch_counter should throw
        @test_throws ArgumentError launch_counter(sess)
    end

end
