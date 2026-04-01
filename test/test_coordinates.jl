@testset "Coordinate conversion" begin
    @testset "pixel_to_relative" begin
        # Center pixel
        @test pixel_to_relative(1728, 2592, 3456, 5184) == (0.5, 0.5)
        # Top-left corner
        @test pixel_to_relative(0, 0, 3456, 5184) == (0.0, 0.0)
        # Bottom-right corner
        @test pixel_to_relative(3456, 5184, 3456, 5184) == (1.0, 1.0)
        # Arbitrary point round trip
        x_rel, y_rel = pixel_to_relative(1234, 4567, 3456, 5184)
        @test x_rel ≈ 0.3570601851851852
        @test y_rel ≈ 0.8809799382716049
    end
    @testset "relative_to_pixel" begin
        # Center
        @test relative_to_pixel(0.5, 0.5, 3456, 5184) == (1728, 2592)
        # Top-left corner
        @test relative_to_pixel(0.0, 0.0, 3456, 5184) == (0, 0)
        # Bottom-right corner
        @test relative_to_pixel(1.0, 1.0, 3456, 5184) == (3456, 5184)
    end
    @testset "Round trip" begin
        for (x_px, y_px) in [(1234, 4567), (100, 200), (3000, 5000)]
            x_rel, y_rel = pixel_to_relative(x_px, y_px, 3456, 5184)
            x_back, y_back = relative_to_pixel(x_rel, y_rel, 3456, 5184)
            @test x_back == x_px
            @test y_back == y_px
        end
    end
    @testset "clamp_to_image" begin
        # Already valid
        @test clamp_to_image(0.5, 0.5) == (0.5, 0.5)
        # Over bounds
        @test clamp_to_image(1.05, 1.1) == (1.0, 1.0)
        # Under bounds
        @test clamp_to_image(-0.02, -0.1) == (0.0, 0.0)
        # Mixed
        @test clamp_to_image(1.05, -0.02) == (1.0, 0.0)
    end
end