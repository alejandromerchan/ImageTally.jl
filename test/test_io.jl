# test/test_io.jl
using Dates: Dates, DateTime

@testset "IO" begin

    # Helper to create a test session with known data
    function test_session()
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("moths.jpg", 3456, 5184; tags = tags)
        add_point!(session, 1728.0, 2592.0)
        add_point!(session, 1000.0, 1000.0)
        set_active_tag!(session, "female")
        add_point!(session, 2000.0, 3000.0)
        return session
    end

    @testset "save_session and load_session" begin
        session = test_session()
        path = tempname() * ".toml"

        try
            # Save
            save_session(session, path)
            @test isfile(path)

            # Load
            session2 = load_session(path)

            # Check metadata
            @test session2.image_path == session.image_path
            @test session2.image_width == session.image_width
            @test session2.image_height == session.image_height
            @test session2.active_tag == session.active_tag
            @test session2.marker_size == session.marker_size
            @test session2.next_id == 4

            # Check tags
            @test length(session2.tags) == 2
            @test session2.tags[1].name == "male"
            @test session2.tags[1].color == :blue
            @test session2.tags[1].marker == :circle
            @test session2.tags[2].name == "female"
            @test session2.tags[2].color == :red
            @test session2.tags[2].marker == :utriangle

            # Check points
            @test length(session2.points) == 3
            @test session2.points[1].id == 1
            @test session2.points[1].x ≈ 0.5
            @test session2.points[1].y ≈ 0.5
            @test session2.points[1].tag == "male"
            @test session2.points[1].timestamp isa DateTime

            @test session2.points[3].tag == "female"

            # Round trip — counts should match
            @test count_by_tag(session2) == count_by_tag(session)

        finally
            isfile(path) && rm(path)
        end
    end

    @testset "save_session errors" begin
        session = test_session()

        # Wrong extension
        @test_throws ArgumentError save_session(session, "/tmp/test.json")
        @test_throws ArgumentError save_session(session, "/tmp/test.txt")
    end

    @testset "load_session errors" begin
        # File not found
        @test_throws ArgumentError load_session("/tmp/nonexistent.toml")

        # Wrong extension
        @test_throws ArgumentError load_session("/tmp/test.json")
    end

    @testset "empty session round trip" begin
        session = new_session("empty.jpg", 1000, 800)
        path = tempname() * ".toml"

        try
            save_session(session, path)
            session2 = load_session(path)

            @test isempty(session2.points)
            @test session2.next_id == 1
            @test length(session2.tags) == 1
        finally
            isfile(path) && rm(path)
        end
    end

    # CSV export lives in test/test_export.jl.

    @testset "session_summary" begin
        session = test_session()
        summary = session_summary(session)

        @test occursin("moths.jpg", summary)
        @test occursin("3456", summary)
        @test occursin("5184", summary)
        @test occursin("3", summary)     # total points
        @test occursin("male", summary)
        @test occursin("female", summary)
        @test occursin("2", summary)     # male count
        @test occursin("1", summary)     # female count
    end

end
