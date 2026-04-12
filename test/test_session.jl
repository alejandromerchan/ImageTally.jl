# test/test_session.jl

@testset "Session management" begin

    @testset "Constants" begin
        @test DEFAULT_MARKER_SIZE == 12.0
        @test MAX_TAGS == 10
    end

    @testset "Tag constructor" begin
        # Valid tag
        tag = Tag("male", :blue, :circle)
        @test tag.name == "male"
        @test tag.color == :blue
        @test tag.marker == :circle

        # Empty name throws
        @test_throws ArgumentError Tag("", :blue, :circle)

        # Unknown marker warns but succeeds
        tag2 = @test_logs (:warn,) Tag("test", :red, :star5)
        @test tag2.marker == :star5

        # All documented valid markers are accepted without warning
        for m in VALID_MARKERS
            @test Tag("t", :red, m).marker == m
        end
    end

    @testset "new_session" begin
        session = new_session("test.jpg", 3456, 5184)

        @test session.image_path == "test.jpg"
        @test session.image_width == 3456
        @test session.image_height == 5184
        @test length(session.tags) == 1
        @test session.active_tag == session.tags[1].name
        @test isempty(session.points)
        @test session.next_id == 1
        @test session.marker_size == DEFAULT_MARKER_SIZE

        # Custom tags
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session2 = new_session("test.jpg", 3456, 5184; tags = tags)
        @test length(session2.tags) == 2
        @test session2.active_tag == "male"

        # Empty tags throws
        @test_throws ArgumentError new_session("test.jpg", 3456, 5184; tags = Tag[])

        # Too many tags throws
        too_many = [Tag("tag$i", :blue, :circle) for i = 1:(MAX_TAGS+1)]
        @test_throws ArgumentError new_session("test.jpg", 3456, 5184; tags = too_many)

        # Empty image_path throws
        @test_throws ArgumentError new_session("", 3456, 5184)

        # Non-positive width throws
        @test_throws ArgumentError new_session("test.jpg", 0, 5184)
        @test_throws ArgumentError new_session("test.jpg", -1, 5184)

        # Non-positive height throws
        @test_throws ArgumentError new_session("test.jpg", 3456, 0)
        @test_throws ArgumentError new_session("test.jpg", 3456, -1)
    end

    @testset "add_point!" begin
        session = new_session("test.jpg", 3456, 5184; tags = [Tag("male", :blue, :circle)])

        point = add_point!(session, 1728.0, 2592.0)

        @test point.id == 1
        @test point.x ≈ 0.5
        @test point.y ≈ 0.5
        @test point.tag == "male"
        @test point.timestamp isa Dates.DateTime
        @test length(session.points) == 1
        @test session.next_id == 2

        # Second point gets next id
        point2 = add_point!(session, 1000.0, 1000.0)
        @test point2.id == 2
        @test length(session.points) == 2

        # Integer coordinates are accepted (Real widening)
        point3 = add_point!(session, 1728, 2592)
        @test point3.x ≈ 0.5
        @test point3.y ≈ 0.5
    end

    @testset "delete_point!" begin
        session = new_session("test.jpg", 3456, 5184)
        add_point!(session, 1728.0, 2592.0)
        add_point!(session, 1000.0, 1000.0)

        # Delete existing point
        @test delete_point!(session, 1) == true
        @test length(session.points) == 1
        @test session.points[1].id == 2

        # Delete non-existing point
        @test delete_point!(session, 99) == false
        @test length(session.points) == 1
    end

    @testset "move_point!" begin
        session = new_session("test.jpg", 3456, 5184)
        add_point!(session, 1728.0, 2592.0)

        original_timestamp = session.points[1].timestamp

        # Move existing point
        @test move_point!(session, 1, 1800.0, 2600.0) == true
        @test session.points[1].x ≈ 1800.0 / 3456
        @test session.points[1].y ≈ 2600.0 / 5184

        # Tag and id preserved after move
        @test session.points[1].id == 1
        @test session.points[1].tag == session.active_tag

        # Timestamp preserved after move
        @test session.points[1].timestamp == original_timestamp

        # Move non-existing point
        @test move_point!(session, 99, 1000.0, 1000.0) == false
    end

    @testset "find_nearest_point" begin
        session = new_session("test.jpg", 3456, 5184)
        add_point!(session, 1728.0, 2592.0)    # center
        add_point!(session, 100.0, 100.0)       # top-left

        # Find near center
        nearest = find_nearest_point(session, 1730.0, 2595.0)
        @test !isnothing(nearest)
        @test nearest.id == 1

        # Find near top-left
        nearest2 = find_nearest_point(session, 105.0, 105.0)
        @test !isnothing(nearest2)
        @test nearest2.id == 2

        # Nothing within threshold — click far from all points
        @test isnothing(find_nearest_point(session, 3000.0, 100.0; threshold = 50.0))

        # Empty session returns nothing
        empty_session = new_session("test.jpg", 3456, 5184)
        @test isnothing(find_nearest_point(empty_session, 1728.0, 2592.0))
    end

    @testset "count_by_tag" begin
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("test.jpg", 3456, 5184; tags = tags)

        # Empty session — all tags present with zero count
        counts = count_by_tag(session)
        @test counts["male"] == 0
        @test counts["female"] == 0

        # Add some points
        add_point!(session, 1728.0, 2592.0)
        add_point!(session, 1000.0, 1000.0)
        set_active_tag!(session, "female")
        add_point!(session, 2000.0, 3000.0)

        counts = count_by_tag(session)
        @test counts["male"] == 2
        @test counts["female"] == 1
    end

    @testset "total_count" begin
        session = new_session("test.jpg", 3456, 5184)

        @test total_count(session) == 0

        add_point!(session, 1728.0, 2592.0)
        @test total_count(session) == 1

        add_point!(session, 1000.0, 1000.0)
        @test total_count(session) == 2

        delete_point!(session, 1)
        @test total_count(session) == 1
    end

    @testset "set_active_tag!" begin
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("test.jpg", 3456, 5184; tags = tags)

        set_active_tag!(session, "female")
        @test session.active_tag == "female"

        set_active_tag!(session, "male")
        @test session.active_tag == "male"

        # Invalid tag throws
        @test_throws ArgumentError set_active_tag!(session, "unknown")
    end

    @testset "set_marker_size!" begin
        session = new_session("test.jpg", 3456, 5184)

        set_marker_size!(session, 20.0)
        @test session.marker_size == 20.0

        set_marker_size!(session, 1.0)
        @test session.marker_size == 1.0

        # Integer size is accepted (Real widening)
        set_marker_size!(session, 20)
        @test session.marker_size == 20.0

        # Zero throws
        @test_throws ArgumentError set_marker_size!(session, 0.0)

        # Negative throws
        @test_throws ArgumentError set_marker_size!(session, -1.0)

        # Unusually large size warns
        @test_logs (:warn,) set_marker_size!(session, 201.0)
        @test session.marker_size == 201.0

        # Exactly 200 does not warn
        set_marker_size!(session, 200.0)
        @test session.marker_size == 200.0
    end

    @testset "get_tag" begin
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("test.jpg", 3456, 5184; tags = tags)

        tag = get_tag(session, "male")
        @test !isnothing(tag)
        @test tag.name == "male"
        @test tag.color == :blue
        @test tag.marker == :circle

        @test isnothing(get_tag(session, "unknown"))
    end

    @testset "has_tag" begin
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("test.jpg", 3456, 5184; tags = tags)

        @test has_tag(session, "male") == true
        @test has_tag(session, "female") == true
        @test has_tag(session, "unknown") == false
    end

    @testset "add_tag!" begin
        session = new_session("test.jpg", 3456, 5184)

        # Add a new tag
        tag = add_tag!(session, Tag("juvenile", :green, :diamond))
        @test tag.name == "juvenile"
        @test has_tag(session, "juvenile")
        @test length(session.tags) == 2

        # Duplicate tag throws
        @test_throws ArgumentError add_tag!(session, Tag("juvenile", :blue, :circle))

        # Fill up to MAX_TAGS
        for i = 2:(MAX_TAGS-1)
            add_tag!(session, Tag("tag$i", :blue, :circle))
        end
        @test length(session.tags) == MAX_TAGS

        # Exceeding MAX_TAGS throws
        @test_throws ArgumentError add_tag!(session, Tag("toomany", :red, :circle))
    end

    @testset "remove_tag!" begin
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("test.jpg", 3456, 5184; tags = tags)

        # Remove tag with no points
        @test remove_tag!(session, "female") == true
        @test !has_tag(session, "female")
        @test length(session.tags) == 1

        # Remove non-existing tag
        @test remove_tag!(session, "unknown") == false

        # Add points and try to remove their tag
        add_point!(session, 1728.0, 2592.0)
        @test_throws ArgumentError remove_tag!(session, "male")

        # Active tag switches when removed
        session2 = new_session(
            "test.jpg",
            3456,
            5184;
            tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)],
        )
        set_active_tag!(session2, "male")
        remove_tag!(session2, "male")
        @test session2.active_tag == "female"
    end

end

@testset "launch_counter fallback (no GLMakie)" begin
    # Before GLMakie is loaded the generic fallback should throw a helpful error.
    @test_throws ArgumentError launch_counter("any_path.jpg")
    @test_throws ArgumentError launch_counter(42)
end
