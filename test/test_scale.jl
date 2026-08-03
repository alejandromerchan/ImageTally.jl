# test/test_scale.jl
# Scale calibration: unit canonicalisation, setting and clearing a
# calibration, and pixel/real-world conversion.

@testset "Scale calibration" begin

    # The two micro codepoints, written as escapes — they are visually
    # identical, so a literal in a test would prove nothing.
    MICRO_SIGN = '\u00b5'     # U+00B5 MICRO SIGN
    MU = '\u03bc'             # U+03BC GREEK SMALL LETTER MU

    # A 1000x2000 image makes relative coordinates easy to read off by eye.
    calibrated_session() = begin
        session = new_session("moths.jpg", 1000, 2000)
        set_scale!(session, 100.0, 100.0, 200.0, 100.0, 2.0, "mm")
        session
    end

    # -------------------------------------------------------------------
    # Unit handling
    # -------------------------------------------------------------------
    @testset "VALID_UNITS" begin
        @test VALID_UNITS == ("nm", "μm", "mm", "cm", "m", "in")

        # The canonical micro unit uses U+03BC, not U+00B5.
        micro = VALID_UNITS[2]
        @test first(micro) == MU
        @test first(micro) != MICRO_SIGN
    end

    @testset "normalize_unit" begin
        normalize_unit = ImageTally.normalize_unit

        @testset "canonical units round-trip unchanged" begin
            for unit in VALID_UNITS
                @test normalize_unit(unit) == unit
                @test normalize_unit(unit) isa String
            end
        end

        @testset "micro sign is normalised to mu" begin
            with_micro_sign = string(MICRO_SIGN, "m")
            with_mu = string(MU, "m")

            # The two inputs are distinct strings to start with.
            @test with_micro_sign != with_mu

            @test normalize_unit(with_micro_sign) == with_mu
            @test normalize_unit(with_micro_sign) == normalize_unit(with_mu)
            @test normalize_unit(with_micro_sign) in VALID_UNITS

            # The stored characters really are the same codepoint afterwards.
            @test collect(normalize_unit(with_micro_sign)) ==
                  collect(normalize_unit(with_mu))
        end

        @testset "aliases" begin
            aliases = Dict(
                "um" => "μm",
                "micron" => "μm",
                "microns" => "μm",
                "micrometer" => "μm",
                "micrometers" => "μm",
                "micrometre" => "μm",
                "micrometres" => "μm",
                "nanometer" => "nm",
                "nanometers" => "nm",
                "nanometre" => "nm",
                "nanometres" => "nm",
                "millimeter" => "mm",
                "millimeters" => "mm",
                "millimetre" => "mm",
                "millimetres" => "mm",
                "centimeter" => "cm",
                "centimeters" => "cm",
                "centimetre" => "cm",
                "centimetres" => "cm",
                "meter" => "m",
                "meters" => "m",
                "metre" => "m",
                "metres" => "m",
                "inch" => "in",
                "inches" => "in",
            )

            for (alias, canonical) in aliases
                @test normalize_unit(alias) == canonical
                @test canonical in VALID_UNITS

                # Case-insensitively, and without warning.
                @test @test_logs normalize_unit(uppercase(alias)) == canonical
                @test normalize_unit(uppercasefirst(alias)) == canonical
            end

            # Case variants of the canonical units themselves.
            @test normalize_unit("MM") == "mm"
            @test normalize_unit("NM") == "nm"
            @test normalize_unit("CM") == "cm"
            @test normalize_unit("M") == "m"
            @test normalize_unit("IN") == "in"
            @test normalize_unit(string(uppercase(MU), "m")) == "μm"
            @test normalize_unit(string(uppercase(MICRO_SIGN), "M")) == "μm"
        end

        @testset "accepts any AbstractString" begin
            # The most likely non-String input: a SubString from split.
            piece = split("1.0 mm")[2]
            @test piece isa SubString
            @test normalize_unit(piece) == "mm"
            @test normalize_unit(piece) isa String

            @test normalize_unit(split("2.5 microns")[2]) == "μm"
            @test normalize_unit(SubString("xxmmxx", 3, 4)) == "mm"
        end

        @testset "whitespace is stripped" begin
            @test normalize_unit("  mm") == "mm"
            @test normalize_unit("mm  ") == "mm"
            @test normalize_unit("\t mm \n") == "mm"
            @test normalize_unit("  microns  ") == "μm"
        end

        @testset "empty input throws" begin
            @test_throws ArgumentError normalize_unit("")
            @test_throws ArgumentError normalize_unit("   ")
            @test_throws ArgumentError normalize_unit("\t\n ")

            err = try
                normalize_unit("")
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("empty", err.msg)
        end

        @testset "unrecognised units warn and are kept as given" begin
            # The deliberate escape hatch: unusual reference objects.
            for odd in ["grid square", "body length", "furlong", "px"]
                result = @test_logs (:warn,) normalize_unit(odd)
                @test result == odd
            end

            # The warning names the unit and lists the known ones.
            @test (@test_logs (:warn, r"furlong") normalize_unit("furlong")) == "furlong"
            @test (@test_logs (:warn, r"nm, μm, mm, cm, m, in") normalize_unit(
                "furlong",
            )) == "furlong"

            # Whitespace is still stripped on the way out.
            @test (@test_logs (:warn,) normalize_unit("  furlong  ")) == "furlong"

            # It must not throw.
            @test (@test_logs (:warn,) normalize_unit("wat")) isa String
        end
    end

    # -------------------------------------------------------------------
    # set_scale!
    # -------------------------------------------------------------------
    @testset "set_scale!" begin

        @testset "sets every field" begin
            session = new_session("moths.jpg", 1000, 2000)
            @test session.has_scale == false

            @test set_scale!(session, 100.0, 100.0, 200.0, 100.0, 2.0, "mm") === nothing

            @test session.has_scale == true
            @test session.scale_real_distance == 2.0
            @test session.scale_unit == "mm"

            # Pixel coordinates are converted to relative.
            @test session.scale_point_1 == (100 / 1000, 100 / 2000)
            @test session.scale_point_2 == (200 / 1000, 100 / 2000)

            # Nothing else is disturbed.
            @test isempty(session.points)
            @test session.next_id == 1
            @test session.marker_size == DEFAULT_MARKER_SIZE
        end

        @testset "integer coordinates and distance are accepted" begin
            session = new_session("moths.jpg", 1000, 2000)
            set_scale!(session, 100, 100, 200, 100, 2, "mm")
            @test session.scale_point_1 == (0.1, 0.05)
            @test session.scale_real_distance === 2.0
        end

        @testset "the unit is canonicalised" begin
            session = new_session("moths.jpg", 1000, 2000)
            set_scale!(session, 0.0, 0.0, 100.0, 0.0, 5.0, "  Microns ")
            @test session.scale_unit == "μm"

            # An unrecognised unit warns but calibrates.
            other = new_session("moths.jpg", 1000, 2000)
            @test_logs (:warn,) set_scale!(other, 0.0, 0.0, 100.0, 0.0, 1.0, "grid square")
            @test other.has_scale == true
            @test other.scale_unit == "grid square"
        end

        @testset "scale_pixel_distance" begin
            # Horizontal: 100 px across a 1000 px-wide image.
            session = new_session("moths.jpg", 1000, 2000)
            set_scale!(session, 100.0, 100.0, 200.0, 100.0, 2.0, "mm")
            @test scale_pixel_distance(session) ≈ 100.0

            # Vertical: 500 px down a 2000 px-tall image.
            set_scale!(session, 100.0, 100.0, 100.0, 600.0, 2.0, "mm")
            @test scale_pixel_distance(session) ≈ 500.0

            # Diagonal: a 3-4-5 triangle.
            set_scale!(session, 0.0, 0.0, 300.0, 400.0, 1.0, "mm")
            @test scale_pixel_distance(session) ≈ 500.0

            # Direction does not matter.
            reversed = new_session("moths.jpg", 1000, 2000)
            set_scale!(reversed, 300.0, 400.0, 0.0, 0.0, 1.0, "mm")
            @test scale_pixel_distance(reversed) ≈ 500.0

            # Zero without a calibration.
            @test scale_pixel_distance(new_session("moths.jpg", 1000, 2000)) == 0.0
        end

        @testset "non-positive real distance throws" begin
            session = new_session("moths.jpg", 1000, 2000)

            @test_throws ArgumentError set_scale!(session, 0.0, 0.0, 100.0, 0.0, 0.0, "mm")
            @test_throws ArgumentError set_scale!(session, 0.0, 0.0, 100.0, 0.0, -5.0, "mm")

            err = try
                set_scale!(session, 0.0, 0.0, 100.0, 0.0, -5.0, "mm")
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("positive", err.msg)

            # A rejected call leaves the session uncalibrated.
            @test session.has_scale == false
        end

        @testset "an empty unit throws" begin
            session = new_session("moths.jpg", 1000, 2000)
            @test_throws ArgumentError set_scale!(session, 0.0, 0.0, 100.0, 0.0, 1.0, "")
            @test_throws ArgumentError set_scale!(session, 0.0, 0.0, 100.0, 0.0, 1.0, "   ")
            @test session.has_scale == false
        end

        @testset "coincident points throw" begin
            session = new_session("moths.jpg", 1000, 2000)

            @test_throws ArgumentError set_scale!(
                session,
                100.0,
                100.0,
                100.0,
                100.0,
                1.0,
                "mm",
            )

            err = try
                set_scale!(session, 100.0, 100.0, 100.0, 100.0, 1.0, "mm")
            catch e
                e
            end
            @test err isa ArgumentError
            @test occursin("coincident", err.msg)
            @test session.has_scale == false
        end

        @testset "points that clamp to coincidence throw" begin
            session = new_session("moths.jpg", 1000, 2000)

            # Two genuinely different points, both off the same corner.
            @test_throws ArgumentError set_scale!(
                session,
                -50.0,
                -50.0,
                -10.0,
                -10.0,
                1.0,
                "mm",
            )

            # And off the opposite corner.
            @test_throws ArgumentError set_scale!(
                session,
                5000.0,
                9000.0,
                1200.0,
                2400.0,
                1.0,
                "mm",
            )

            @test session.has_scale == false
        end

        @testset "out-of-bounds points are clamped" begin
            session = new_session("moths.jpg", 1000, 2000)
            set_scale!(session, -100.0, -200.0, 5000.0, 9000.0, 1.0, "mm")

            @test session.scale_point_1 == (0.0, 0.0)
            @test session.scale_point_2 == (1.0, 1.0)

            # Clamping is applied before the distance is derived.
            @test scale_pixel_distance(session) ≈ sqrt(1000.0^2 + 2000.0^2)
        end

        @testset "calling it twice overwrites cleanly" begin
            session = new_session("moths.jpg", 1000, 2000)
            set_scale!(session, 0.0, 0.0, 100.0, 0.0, 2.0, "mm")
            set_scale!(session, 500.0, 1000.0, 500.0, 1200.0, 8.0, "μm")

            @test session.has_scale == true
            @test session.scale_real_distance == 8.0
            @test session.scale_unit == "μm"
            @test session.scale_point_1 == (0.5, 0.5)
            @test session.scale_point_2 == (0.5, 0.6)
            @test scale_pixel_distance(session) ≈ 200.0

            # No trace of the first calibration is left.
            @test pixels_to_real(session, 200.0) ≈ 8.0
        end

        @testset "a rejected overwrite leaves the old calibration intact" begin
            session = calibrated_session()
            before = (
                session.scale_real_distance,
                session.scale_unit,
                session.scale_point_1,
                session.scale_point_2,
            )

            @test_throws ArgumentError set_scale!(session, 0.0, 0.0, 500.0, 0.0, -1.0, "cm")

            @test session.has_scale == true
            @test (
                session.scale_real_distance,
                session.scale_unit,
                session.scale_point_1,
                session.scale_point_2,
            ) == before
        end
    end

    # -------------------------------------------------------------------
    # clear_scale!
    # -------------------------------------------------------------------
    @testset "clear_scale!" begin

        @testset "resets every scale field" begin
            session = calibrated_session()
            @test session.has_scale == true

            @test clear_scale!(session) === nothing

            @test session.has_scale == false
            @test session.scale_real_distance == 0.0
            @test session.scale_unit == ""
            @test session.scale_point_1 == (0.0, 0.0)
            @test session.scale_point_2 == (0.0, 0.0)
            @test scale_pixel_distance(session) == 0.0
        end

        @testset "leaves points and tags untouched" begin
            session = new_session(
                "moths.jpg",
                1000,
                2000;
                tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)],
            )
            add_point!(session, 100.0, 200.0)
            set_active_tag!(session, "female")
            add_point!(session, 300.0, 400.0)
            set_marker_size!(session, 25.0)
            set_scale!(session, 0.0, 0.0, 100.0, 0.0, 1.0, "mm")

            points_before = copy(session.points)
            tags_before = copy(session.tags)

            clear_scale!(session)

            @test session.points == points_before
            @test session.tags == tags_before
            @test session.active_tag == "female"
            @test session.next_id == 3
            @test session.marker_size == 25.0
            @test session.image_path == "moths.jpg"
            @test session.image_width == 1000
            @test session.image_height == 2000
        end

        @testset "is a no-op on a session with no scale" begin
            session = new_session("moths.jpg", 1000, 2000)
            add_point!(session, 100.0, 200.0)

            @test clear_scale!(session) === nothing
            @test clear_scale!(session) === nothing

            @test session.has_scale == false
            @test length(session.points) == 1
        end
    end

    # -------------------------------------------------------------------
    # Conversions
    # -------------------------------------------------------------------
    @testset "conversions" begin

        @testset "a known calibration produces known values" begin
            # 100 px == 2.0 mm
            session = calibrated_session()
            @test scale_pixel_distance(session) ≈ 100.0

            @test pixels_to_real(session, 100.0) ≈ 2.0
            @test pixels_to_real(session, 50.0) ≈ 1.0
            @test pixels_to_real(session, 250.0) ≈ 5.0
            @test pixels_to_real(session, 0.0) == 0.0

            @test real_to_pixels(session, 2.0) ≈ 100.0
            @test real_to_pixels(session, 1.0) ≈ 50.0
            @test real_to_pixels(session, 5.0) ≈ 250.0
            @test real_to_pixels(session, 0.0) == 0.0
        end

        @testset "integer arguments are accepted" begin
            session = calibrated_session()
            @test pixels_to_real(session, 50) ≈ 1.0
            @test real_to_pixels(session, 1) ≈ 50.0
            @test pixels_to_real(session, 50) isa Float64
            @test real_to_pixels(session, 1) isa Float64
        end

        @testset "the two are exact inverses" begin
            session = calibrated_session()
            for px in [0.0, 1.0, 12.5, 50.0, 100.0, 1234.5, 1.0e6]
                @test real_to_pixels(session, pixels_to_real(session, px)) ≈ px
            end
            for real in [0.0, 0.25, 1.0, 2.0, 37.5, 1.0e4]
                @test pixels_to_real(session, real_to_pixels(session, real)) ≈ real
            end
        end

        @testset "a diagonal calibration converts correctly" begin
            # A 3-4-5 diagonal: 500 px == 10 μm, so 50 px == 1 μm.
            session = new_session("moths.jpg", 1000, 2000)
            set_scale!(session, 0.0, 0.0, 300.0, 400.0, 10.0, "um")

            @test session.scale_unit == "μm"
            @test scale_pixel_distance(session) ≈ 500.0
            @test pixels_to_real(session, 50.0) ≈ 1.0
            @test real_to_pixels(session, 1.0) ≈ 50.0
        end

        @testset "both throw without a calibration" begin
            session = new_session("moths.jpg", 1000, 2000)

            @test_throws ArgumentError pixels_to_real(session, 50.0)
            @test_throws ArgumentError real_to_pixels(session, 1.0)

            for f in (pixels_to_real, real_to_pixels)
                err = try
                    f(session, 1.0)
                catch e
                    e
                end
                @test err isa ArgumentError
                @test occursin("set_scale!", err.msg)
            end

            # And again after a calibration is cleared.
            calibrated = calibrated_session()
            @test pixels_to_real(calibrated, 50.0) ≈ 1.0
            clear_scale!(calibrated)
            @test_throws ArgumentError pixels_to_real(calibrated, 50.0)
            @test_throws ArgumentError real_to_pixels(calibrated, 1.0)
        end
    end
end
