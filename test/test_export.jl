# test/test_export.jl
# CSV export: both schemas, RFC 4180 escaping, and a round trip through a real
# CSV parser.
using Dates: Dates, DateTime
using CSV: CSV

# A session built by hand rather than by add_point!, so the timestamps are
# fixed and the exported bytes can be compared against a literal string.
const STAMP_1 = DateTime(2026, 3, 14, 9, 26, 53)
const STAMP_2 = DateTime(2026, 3, 14, 9, 27, 4)

@testset "CSV export" begin

    function fixed_session(; kwargs...)
        return CountSession(;
            image_path = "moths.jpg",
            image_width = 1000,
            image_height = 800,
            tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)],
            points = [
                CountPoint(1, 0.5, 0.5, "male", STAMP_1),
                CountPoint(2, 0.1, 0.25, "female", STAMP_2),
            ],
            next_id = 3,
            active_tag = "male",
            kwargs...,
        )
    end

    # 100 px calibrated as 2.0 mm, so a pixel is exactly 0.02 mm and every
    # expected real value below is a round number.
    function calibrate!(session, unit = "mm")
        set_scale!(session, 0.0, 0.0, 100.0, 0.0, 2.0, unit)
        return session
    end

    # Run `body` with a temporary .csv path, removing it afterwards.
    function with_csv(body)
        path = tempname() * ".csv"
        try
            body(path)
        finally
            isfile(path) && rm(path)
        end
    end

    # Helper for the original add_point!-built session used by the pre-existing
    # field-by-field assertions.
    function counted_session()
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("moths.jpg", 3456, 5184; tags = tags)
        add_point!(session, 1728.0, 2592.0)
        add_point!(session, 1000.0, 1000.0)
        set_active_tag!(session, "female")
        add_point!(session, 2000.0, 3000.0)
        return session
    end

    @testset "no scale — byte-identical to the v0.1.0 format" begin
        with_csv() do path
            export_csv(fixed_session(), path)

            # Written out in full on purpose. An uncalibrated session must
            # export exactly the bytes every earlier ImageTally wrote, so this
            # asserts the whole file, not a column count.
            expected = """
            id,tag,x_relative,y_relative,x_pixel,y_pixel,timestamp
            1,male,0.5,0.5,500,400,2026-03-14T09:26:53
            2,female,0.1,0.25,100,200,2026-03-14T09:27:04
            """
            @test read(path, String) == expected
        end
    end

    @testset "no scale — fields of a counted session" begin
        with_csv() do path
            export_csv(counted_session(), path)
            @test isfile(path)

            lines = readlines(path)
            @test lines[1] == "id,tag,x_relative,y_relative,x_pixel,y_pixel,timestamp"
            @test length(lines) == 4

            fields = split(lines[2], ",")
            @test fields[1] == "1"
            @test fields[2] == "male"
            @test parse(Float64, fields[3]) ≈ 0.5
            @test parse(Float64, fields[4]) ≈ 0.5
            @test parse(Int, fields[5]) == 1728
            @test parse(Int, fields[6]) == 2592

            @test split(lines[4], ",")[2] == "female"
        end
    end

    @testset "with scale — header and column order" begin
        with_csv() do path
            export_csv(calibrate!(fixed_session()), path)

            @test readlines(path)[1] ==
                  "id,tag,x_relative,y_relative,x_pixel,y_pixel,x_real,y_real,unit,timestamp"
        end
    end

    @testset "with scale — whole file" begin
        with_csv() do path
            export_csv(calibrate!(fixed_session()), path)

            expected = """
            id,tag,x_relative,y_relative,x_pixel,y_pixel,x_real,y_real,unit,timestamp
            1,male,0.5,0.5,500,400,10.0,8.0,mm,2026-03-14T09:26:53
            2,female,0.1,0.25,100,200,2.0,4.0,mm,2026-03-14T09:27:04
            """
            @test read(path, String) == expected
        end
    end

    @testset "with scale — real values match pixels_to_real" begin
        session = calibrate!(fixed_session())

        with_csv() do path
            export_csv(session, path)
            rows = readlines(path)[2:end]

            for (point, line) in zip(session.points, rows)
                fields = split(line, ",")
                x_px, y_px = relative_to_pixel(
                    point.x,
                    point.y,
                    session.image_width,
                    session.image_height,
                )

                @test parse(Float64, fields[7]) == pixels_to_real(session, x_px)
                @test parse(Float64, fields[8]) == pixels_to_real(session, y_px)
            end

            # The round numbers the calibration was chosen for: 100 px is
            # 2.0 mm, so 500 px is 10.0 mm and 400 px is 8.0 mm.
            first_row = split(rows[1], ",")
            @test parse(Float64, first_row[7]) == 10.0
            @test parse(Float64, first_row[8]) == 8.0
        end
    end

    @testset "with scale — unit column is the canonical string" begin
        # Calibrated in "um"; every row must read "μm" (U+03BC).
        session = calibrate!(fixed_session(), "um")
        @test session.scale_unit == "μm"

        with_csv() do path
            export_csv(session, path)
            rows = readlines(path)[2:end]

            @test length(rows) == 2
            for line in rows
                @test split(line, ",")[9] == "μm"
            end
        end
    end

    @testset "clear_scale! returns to the no-scale schema" begin
        session = calibrate!(fixed_session())
        clear_scale!(session)

        with_csv() do path
            export_csv(session, path)

            expected = """
            id,tag,x_relative,y_relative,x_pixel,y_pixel,timestamp
            1,male,0.5,0.5,500,400,2026-03-14T09:26:53
            2,female,0.1,0.25,100,200,2026-03-14T09:27:04
            """
            @test read(path, String) == expected
        end
    end

    @testset "empty session with a scale — header only" begin
        session = calibrate!(
            CountSession(;
                image_path = "empty.jpg",
                image_width = 1000,
                image_height = 800,
                active_tag = "object",
            ),
        )

        with_csv() do path
            export_csv(session, path)

            lines = readlines(path)
            @test length(lines) == 1
            @test lines[1] ==
                  "id,tag,x_relative,y_relative,x_pixel,y_pixel,x_real,y_real,unit,timestamp"
        end
    end

    @testset "escaping" begin
        @testset "csv_escape leaves ordinary values bare" begin
            for plain in ["male", "μm", "2026-03-14T09:26:53", "grid square", ""]
                @test ImageTally.csv_escape(plain) == plain
            end
        end

        @testset "csv_escape quotes and doubles" begin
            @test ImageTally.csv_escape("eggs, parasitized") == "\"eggs, parasitized\""
            @test ImageTally.csv_escape("he said \"hi\"") == "\"he said \"\"hi\"\"\""
            @test ImageTally.csv_escape("two\nlines") == "\"two\nlines\""
            @test ImageTally.csv_escape("two\rlines") == "\"two\rlines\""
        end

        @testset "hostile tags and unit round-trip through a parser" begin
            comma_tag = "eggs, parasitized"
            quote_tag = "he said \"hi\""

            session = CountSession(;
                image_path = "moths.jpg",
                image_width = 1000,
                image_height = 800,
                tags = [Tag(comma_tag, :blue, :circle), Tag(quote_tag, :red, :rect)],
                points = [
                    CountPoint(1, 0.5, 0.5, comma_tag, STAMP_1),
                    CountPoint(2, 0.1, 0.25, quote_tag, STAMP_2),
                ],
                next_id = 3,
                active_tag = comma_tag,
            )
            # A free-form unit with both a space and a comma — normalize_unit
            # keeps it as given, with a warning.
            @test_logs (:warn,) set_scale!(
                session,
                0.0,
                0.0,
                100.0,
                0.0,
                2.0,
                "grid squares, small",
            )

            with_csv() do path
                export_csv(session, path)
                table = CSV.File(path)

                @test length(table) == 2
                @test table.tag[1] == comma_tag
                @test table.tag[2] == quote_tag
                @test all(table.unit .== "grid squares, small")
                # The columns after the escaped fields still line up.
                @test table.x_pixel == [500, 100]
                @test table.timestamp[1] == STAMP_1
            end
        end
    end

    @testset "round trip through CSV.read" begin
        @testset "no scale" begin
            with_csv() do path
                export_csv(fixed_session(), path)
                table = CSV.read(path, CSV.Tables.columntable)

                @test collect(keys(table)) ==
                      [:id, :tag, :x_relative, :y_relative, :x_pixel, :y_pixel, :timestamp]
                @test length(table.id) == 2
                @test table.id == [1, 2]
                @test table.tag == ["male", "female"]
                @test table.x_relative == [0.5, 0.1]
                @test table.y_pixel == [400, 200]
                @test table.timestamp == [STAMP_1, STAMP_2]
            end
        end

        @testset "with scale" begin
            with_csv() do path
                export_csv(calibrate!(fixed_session()), path)
                table = CSV.read(path, CSV.Tables.columntable)

                @test collect(keys(table)) == [
                    :id,
                    :tag,
                    :x_relative,
                    :y_relative,
                    :x_pixel,
                    :y_pixel,
                    :x_real,
                    :y_real,
                    :unit,
                    :timestamp,
                ]
                @test length(table.id) == 2
                @test table.x_real == [10.0, 2.0]
                @test table.y_real == [8.0, 4.0]
                @test all(table.unit .== "mm")
                @test table.timestamp == [STAMP_1, STAMP_2]
            end
        end
    end

    @testset "export_csv errors" begin
        session = fixed_session()
        @test_throws ArgumentError export_csv(session, "/tmp/test.json")
        @test_throws ArgumentError export_csv(session, "/tmp/test.txt")

        # The extension check is the only error, calibrated or not.
        @test_throws ArgumentError export_csv(calibrate!(fixed_session()), "/tmp/test.txt")
    end

end
