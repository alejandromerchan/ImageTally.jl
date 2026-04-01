# test/test_session.jl

@testset "Session management" begin

    @testset "new_session" begin
        session = new_session("test.jpg", 3456, 5184)

        @test session.image_path == "test.jpg"
        @test session.image_width == 3456
        @test session.image_height == 5184
        @test length(session.tags) == 1
        @test session.active_tag == session.tags[1].name
        @test isempty(session.points)
        @test session.next_id == 1

        # Custom tags
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session2 = new_session("test.jpg", 3456, 5184; tags=tags)
        @test length(session2.tags) == 2
        @test session2.active_tag == "male"

        # Empty tags throws
        @test_throws ArgumentError new_session("test.jpg", 3456, 5184; tags=Tag[])
    end

    @testset "add_point!" begin
        session = new_session("test.jpg", 3456, 5184;
            tags=[Tag("male", :blue, :circle)])

        point = add_point!(session, 1728.0, 2592.0)

        @test point.id == 1
        @test point.x ≈ 0.5
        @test point.y ≈ 0.5
        @test point.tag == "male"
        @test length(session.points) == 1
        @test session.next_id == 2

        # Second point gets next id
        point2 = add_point!(session, 1000.0, 1000.0)
        @test point2.id == 2
        @test length(session.points) == 2
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

        # Move existing point
        @test move_point!(session, 1, 1800.0, 2600.0) == true
        @test session.points[1].x ≈ 1800.0 / 3456
        @test session.points[1].y ≈ 2600.0 / 5184

        # Tag and id preserved after move
        @test session.points[1].id == 1
        @test session.points[1].tag == session.active_tag

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

        # Nothing within threshold
        @test isnothing(find_nearest_point(session, 3000.0, 100.0; threshold=50.0))

        # Empty session returns nothing
        empty_session = new_session("test.jpg", 3456, 5184)
        @test isnothing(find_nearest_point(empty_session, 1728.0, 2592.0))
    end

    @testset "count_by_tag" begin
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("test.jpg", 3456, 5184; tags=tags)

        # Empty session
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

    @testset "set_active_tag!" begin
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("test.jpg", 3456, 5184; tags=tags)

        set_active_tag!(session, "female")
        @test session.active_tag == "female"

        set_active_tag!(session, "male")
        @test session.active_tag == "male"

        # Invalid tag throws
        @test_throws ArgumentError set_active_tag!(session, "unknown")
    end

end