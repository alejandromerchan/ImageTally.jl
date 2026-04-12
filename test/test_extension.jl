# test/test_extension.jl
#
# Integration tests for the GLMakie extension.
# These require GLMakie and FileIO to be loaded so the extension fires.
# No display is needed — only new_session is tested here (no GUI window opened).

using GLMakie
using FileIO
using ColorTypes

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

    @testset "launch_counter(path) — file not found" begin
        @test_throws ArgumentError launch_counter("/nonexistent/path/image.jpg")
    end

    @testset "launch_counter(path) — success" begin
        path = synthetic_image(200, 300)   # height=200, width=300
        try
            fig, sess = launch_counter(path)
            @test fig isa GLMakie.Figure
            @test sess isa CountSession
            @test sess.image_path == path
            @test sess.image_width == 300
            @test sess.image_height == 200
            @test sess.active_tag == sess.tags[1].name
            @test isempty(sess.points)
        finally
            isfile(path) && rm(path)
            GLMakie.closeall()
        end
    end

    @testset "launch_counter(path; session=...) — resume session" begin
        path = synthetic_image(100, 100)
        sess_path = tempname() * ".toml"
        try
            # Build a session, add a point, save it, then resume via launch_counter.
            sess_orig = new_session(path)
            add_point!(sess_orig, 50.0, 50.0)
            save_session(sess_orig, sess_path)

            fig, sess = launch_counter(path; session = sess_path)
            @test fig isa GLMakie.Figure
            @test sess isa CountSession
            @test length(sess.points) == 1
            @test sess.points[1].tag == sess_orig.active_tag
        finally
            isfile(path) && rm(path)
            isfile(sess_path) && rm(sess_path)
            GLMakie.closeall()
        end
    end

    @testset "launch_counter(sess) — success" begin
        path = synthetic_image(150, 250)   # height=150, width=250
        tags = [Tag("egg", :red, :circle), Tag("larva", :blue, :utriangle)]
        try
            sess = new_session(path; tags = tags)
            add_point!(sess, 100.0, 75.0)
            fig, sess2 = launch_counter(sess)
            @test fig isa GLMakie.Figure
            @test sess2 === sess
            @test length(sess2.points) == 1
        finally
            isfile(path) && rm(path)
            GLMakie.closeall()
        end
    end

    # ── _normalize_image ─────────────────────────────────────────────────
    # Access the internal helper via the extension handle.

    @testset "_normalize_image — 2D array passes through unchanged" begin
        img2d = fill(Gray{N0f8}(0.5), 100, 200)
        result = ext._normalize_image(img2d)
        @test result === img2d   # exact same object, no copy
        @test ndims(result) == 2
        @test size(result) == (100, 200)
    end

    @testset "_normalize_image — 3D Colorant array (TIF loader layout)" begin
        # TiffImages loads single-channel files as Array{Gray{N0f8}, 3} of shape (H, W, 1).
        img3d = fill(Gray{N0f8}(0.7), 80, 120, 1)
        result = ext._normalize_image(img3d)
        @test ndims(result) == 2
        @test size(result) == (80, 120)
        @test result[1, 1] == Gray{N0f8}(0.7)
    end

    @testset "_normalize_image — 3D RGB Colorant array" begin
        img3d = fill(RGB{N0f8}(1, 0, 0), 60, 90, 1)
        result = ext._normalize_image(img3d)
        @test ndims(result) == 2
        @test size(result) == (60, 90)
        @test result[1, 1] == RGB{N0f8}(1, 0, 0)
    end

    @testset "_normalize_image — 3D raw numeric, C=1" begin
        img3d = ones(Float32, 50, 80, 1)
        result = ext._normalize_image(img3d)
        @test ndims(result) == 2
        @test size(result) == (50, 80)
        @test result[1, 1] == 1.0f0
    end

    @testset "_normalize_image — 3D raw numeric, C=3 → RGB matrix" begin
        img3d = zeros(Float32, 40, 60, 3)
        img3d[:, :, 1] .= 1.0f0   # red channel full
        result = ext._normalize_image(img3d)
        @test ndims(result) == 2
        @test size(result) == (40, 60)
        @test eltype(result) <: Colorant
        @test red(result[1, 1]) ≈ 1.0f0
        @test green(result[1, 1]) ≈ 0.0f0
    end

    @testset "_normalize_image — 3D raw numeric, C=4 → RGBA matrix" begin
        img3d = zeros(Float32, 30, 50, 4)
        img3d[:, :, 4] .= 0.5f0   # alpha channel
        result = ext._normalize_image(img3d)
        @test ndims(result) == 2
        @test size(result) == (30, 50)
        @test eltype(result) <: Colorant
        @test alpha(result[1, 1]) ≈ 0.5f0
    end

    # ── Zoom limit helpers ───────────────────────────────────────────────
    # The zoom math lives in GLMakieExt as _zoom_in_limits / _zoom_out_limits.
    # Access them via Base.get_extension so they can be tested without opening a window.

    ext = Base.get_extension(ImageTally, :GLMakieExt)

    @testset "_zoom_in_limits — shrinks view around center" begin
        # 100×80 view centered at (50, 40), factor 1.5 → each half-span ÷ 1.5
        xmin, xmax, ymin, ymax = ext._zoom_in_limits(0.0, 100.0, 0.0, 80.0)
        @test xmin ≈ 50.0 - 100.0 / (2 * 1.5)
        @test xmax ≈ 50.0 + 100.0 / (2 * 1.5)
        @test ymin ≈ 40.0 - 80.0 / (2 * 1.5)
        @test ymax ≈ 40.0 + 80.0 / (2 * 1.5)
    end

    @testset "_zoom_in_limits — center is preserved" begin
        xmin, xmax, ymin, ymax = ext._zoom_in_limits(10.0, 90.0, 5.0, 45.0)
        @test (xmin + xmax) / 2 ≈ 50.0
        @test (ymin + ymax) / 2 ≈ 25.0
    end

    @testset "_zoom_in_limits — successive steps keep shrinking" begin
        lims = (0.5, 200.5, 0.5, 100.5)
        for _ = 1:4
            lims = ext._zoom_in_limits(lims...)
        end
        xmin, xmax, ymin, ymax = lims
        @test (xmax - xmin) < 200.0   # view is now narrower than the full image
        @test (ymax - ymin) < 100.0
    end

    @testset "_zoom_out_limits — expands view around center" begin
        # Start zoomed in: view is [30,70]×[20,60] inside a 100×80 image.
        xmin, xmax, ymin, ymax = ext._zoom_out_limits(30.0, 70.0, 20.0, 60.0, 100.0, 80.0)
        @test xmin ≈ 50.0 - 40.0 * 1.5 / 2
        @test xmax ≈ 50.0 + 40.0 * 1.5 / 2
        @test ymin ≈ 40.0 - 40.0 * 1.5 / 2
        @test ymax ≈ 40.0 + 40.0 * 1.5 / 2
    end

    @testset "_zoom_out_limits — clamps to image bounds" begin
        # View already covers most of a 100×80 image; zooming out should not exceed bounds.
        xmin, xmax, ymin, ymax = ext._zoom_out_limits(0.5, 100.5, 0.5, 80.5, 100.0, 80.0)
        @test xmin >= 0.5
        @test xmax <= 100.5
        @test ymin >= 0.5
        @test ymax <= 80.5
    end

    @testset "_zoom_out_limits — fully zoomed out stays at image bounds" begin
        # At full image view, zoom-out must be a no-op (clamped on all sides).
        result = ext._zoom_out_limits(0.5, 100.5, 0.5, 80.5, 100.0, 80.0)
        @test result == (0.5, 100.5, 0.5, 80.5)
    end

    @testset "_zoom_out_limits — center preserved when not clamped" begin
        # View [50,150]×[50,150] centered at (100,100) inside a 1000×1000 image.
        # Zoom-out half-spans = 50*1.5 = 75, so new view [25,175]×[25,175] — no boundary hit.
        xmin, xmax, ymin, ymax =
            ext._zoom_out_limits(50.0, 150.0, 50.0, 150.0, 1000.0, 1000.0)
        @test (xmin + xmax) / 2 ≈ 100.0
        @test (ymin + ymax) / 2 ≈ 100.0
    end

end
