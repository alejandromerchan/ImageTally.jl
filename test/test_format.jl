# test/test_format.jl
# Session file format: backward compatibility, versioning, the image-size
# guard, and missing-key handling.
using Dates: Dates, DateTime
using TOML: TOML

@testset "Session format" begin

    FIXTURE_DIR = joinpath(@__DIR__, "fixtures")
    V0_1_0_SESSION = joinpath(FIXTURE_DIR, "v0_1_0_session.toml")

    """
    Write `data` to a temporary session file and return its path. Used to build
    files this ImageTally would not write itself — older versions, hand edits,
    and deliberately malformed tables.
    """
    function write_toml(data)
        path = tempname() * ".toml"
        open(path, "w") do io
            TOML.print(io, data; sorted = true)
        end
        return path
    end

    @testset "format version constants" begin
        @test SESSION_FORMAT_VERSION == 3
        @test ImageTally.LEGACY_SESSION_FORMAT_VERSION == 1
        @test SESSION_FORMAT_VERSION > ImageTally.LEGACY_SESSION_FORMAT_VERSION
    end

    # -------------------------------------------------------------------
    # Backward compatibility with ImageTally v0.1.0
    #
    # The fixture was written by the registered v0.1.0 and is committed
    # byte-for-byte. See the header of generate_fixtures.jl — it must never
    # be regenerated, so these tests are checking real released output, not
    # something the current code produced.
    # -------------------------------------------------------------------
    @testset "v0.1.0 session file" begin

        @test isfile(V0_1_0_SESSION)

        # The fixture is genuinely a version-1 file: no format_version key.
        raw = TOML.parsefile(V0_1_0_SESSION)
        @test !haskey(raw, "format_version")
        @test !haskey(raw, "image_file_size")

        session = load_session(V0_1_0_SESSION)

        @testset "metadata" begin
            @test session.image_path == "moths.jpg"
            @test session.image_width == 3456
            @test session.image_height == 5184
            @test session.active_tag == "female"
            @test session.marker_size == 18.0
            @test session.next_id == 6
        end

        @testset "tags" begin
            @test length(session.tags) == 3

            @test session.tags[1].name == "male"
            @test session.tags[1].color == :blue
            @test session.tags[1].marker == :circle

            @test session.tags[2].name == "female"
            @test session.tags[2].color == :red
            @test session.tags[2].marker == :utriangle

            @test session.tags[3].name == "juvenile"
            @test session.tags[3].color == :green
            @test session.tags[3].marker == :diamond
        end

        @testset "points" begin
            @test length(session.points) == 5
            @test [p.id for p in session.points] == [1, 2, 3, 4, 5]
            @test [p.tag for p in session.points] == ["male", "male", "female", "female", "juvenile"]
            @test all(p -> p.timestamp isa DateTime, session.points)

            # Coordinates survive as the relative values v0.1.0 stored.
            @test session.points[1].x ≈ 0.5
            @test session.points[1].y ≈ 0.5
            @test session.points[2].x ≈ 500 / 3456
            @test session.points[2].y ≈ 800 / 5184
            @test session.points[3].x ≈ 2000 / 3456
            @test session.points[3].y ≈ 3000 / 5184
            @test session.points[4].x ≈ 3455 / 3456
            @test session.points[4].y ≈ 5183 / 5184
            @test session.points[5].x == 0.0
            @test session.points[5].y == 0.0

            # Timestamps are all from the same generation run.
            @test session.points[1].timestamp <= session.points[5].timestamp
        end

        @testset "derived queries still work" begin
            @test total_count(session) == 5
            @test count_by_tag(session) == Dict("male" => 2, "female" => 2, "juvenile" => 1)
        end

        # image_path is a bare filename that does not exist — the guard must
        # stay quiet, and nothing else may warn either.
        @testset "loads without warnings" begin
            @test !isfile(session.image_path)
            @test_logs load_session(V0_1_0_SESSION)
        end

        # Loading a v0.1.0 file and re-saving it upgrades it in place.
        @testset "upgrades on re-save" begin
            path = tempname() * ".toml"
            try
                save_session(session, path)
                @test TOML.parsefile(path)["format_version"] == SESSION_FORMAT_VERSION

                reloaded = load_session(path)
                @test reloaded.image_path == session.image_path
                @test reloaded.next_id == session.next_id
                @test length(reloaded.points) == length(session.points)
            finally
                isfile(path) && rm(path)
            end
        end
    end

    # -------------------------------------------------------------------
    # Current format
    # -------------------------------------------------------------------
    @testset "round trip through format version $SESSION_FORMAT_VERSION" begin
        tags = [Tag("male", :blue, :circle), Tag("female", :red, :utriangle)]
        session = new_session("moths.jpg", 3456, 5184; tags = tags)
        add_point!(session, 1728.0, 2592.0)
        add_point!(session, 10.0, 20.0)
        set_active_tag!(session, "female")
        add_point!(session, 2000.0, 3000.0)
        set_marker_size!(session, 25.0)

        path = tempname() * ".toml"
        try
            save_session(session, path)

            raw = TOML.parsefile(path)
            @test raw["format_version"] == SESSION_FORMAT_VERSION

            loaded = load_session(path)

            @test loaded.image_path == session.image_path
            @test loaded.image_width == session.image_width
            @test loaded.image_height == session.image_height
            @test loaded.active_tag == session.active_tag
            @test loaded.marker_size == session.marker_size
            @test loaded.next_id == session.next_id

            @test length(loaded.tags) == length(session.tags)
            for (a, b) in zip(loaded.tags, session.tags)
                @test a.name == b.name
                @test a.color == b.color
                @test a.marker == b.marker
            end

            @test length(loaded.points) == length(session.points)
            for (a, b) in zip(loaded.points, session.points)
                @test a.id == b.id
                @test a.x == b.x
                @test a.y == b.y
                @test a.tag == b.tag
                @test a.timestamp == b.timestamp
            end
        finally
            isfile(path) && rm(path)
        end
    end

    @testset "TOML output is deterministic" begin
        session = new_session("moths.jpg", 100, 200)
        add_point!(session, 10.0, 20.0)

        path_a = tempname() * ".toml"
        path_b = tempname() * ".toml"
        try
            save_session(session, path_a)
            save_session(session, path_b)

            @test read(path_a, String) == read(path_b, String)

            # Sorted output means keys come out in sorted order. Only the
            # lines before the first sub-table header are top-level; keys
            # inside [[tags]] and [[points]] sort within their own table.
            lines = readlines(path_a)
            first_table =
                something(findfirst(l -> startswith(l, "["), lines), length(lines) + 1)
            keys_in_order =
                [split(l, " = ")[1] for l in lines[1:(first_table-1)] if occursin(" = ", l)]
            @test !isempty(keys_in_order)
            @test keys_in_order == sort(keys_in_order)
            @test "format_version" in keys_in_order
        finally
            isfile(path_a) && rm(path_a)
            isfile(path_b) && rm(path_b)
        end
    end

    # -------------------------------------------------------------------
    # Forward guard
    # -------------------------------------------------------------------
    @testset "rejects a newer format version" begin
        session = new_session("moths.jpg", 100, 200)
        path = tempname() * ".toml"
        try
            save_session(session, path)

            data = TOML.parsefile(path)
            data["format_version"] = SESSION_FORMAT_VERSION + 1
            open(path, "w") do io
                TOML.print(io, data; sorted = true)
            end

            @test_throws ArgumentError load_session(path)

            err = try
                load_session(path)
            catch e
                e
            end
            @test occursin("newer", err.msg)
            @test occursin("upgrade", err.msg)

            # A far-future version is rejected too.
            data["format_version"] = 999
            open(path, "w") do io
                TOML.print(io, data; sorted = true)
            end
            @test_throws ArgumentError load_session(path)

            # The current version and the legacy version are both accepted.
            data["format_version"] = SESSION_FORMAT_VERSION
            open(path, "w") do io
                TOML.print(io, data; sorted = true)
            end
            @test load_session(path) isa CountSession

            data["format_version"] = ImageTally.LEGACY_SESSION_FORMAT_VERSION
            open(path, "w") do io
                TOML.print(io, data; sorted = true)
            end
            @test load_session(path) isa CountSession
        finally
            isfile(path) && rm(path)
        end
    end

    # -------------------------------------------------------------------
    # Image file size guard
    # -------------------------------------------------------------------
    @testset "image file size guard" begin

        @testset "key absent — silent" begin
            # The v0.1.0 fixture recorded no size at all.
            @test_logs load_session(V0_1_0_SESSION)
        end

        @testset "key omitted when image is missing at save time" begin
            session = new_session("does_not_exist.jpg", 100, 200)
            path = tempname() * ".toml"
            try
                save_session(session, path)
                @test !haskey(TOML.parsefile(path), "image_file_size")
                @test_logs load_session(path)
            finally
                isfile(path) && rm(path)
            end
        end

        @testset "key present, image missing — silent" begin
            image = tempname() * ".png"
            path = tempname() * ".toml"
            try
                cp(joinpath(FIXTURE_DIR, "small_rgb.png"), image)
                session = new_session(image, 64, 64)
                save_session(session, path)
                @test TOML.parsefile(path)["image_file_size"] == filesize(image)

                # Session travels without its image — a supported workflow.
                rm(image)
                @test !isfile(image)
                @test_logs load_session(path)
            finally
                isfile(image) && rm(image)
                isfile(path) && rm(path)
            end
        end

        @testset "key present, size unchanged — silent" begin
            image = tempname() * ".png"
            path = tempname() * ".toml"
            try
                cp(joinpath(FIXTURE_DIR, "small_rgb.png"), image)
                session = new_session(image, 64, 64)
                save_session(session, path)

                @test_logs load_session(path)
            finally
                isfile(image) && rm(image)
                isfile(path) && rm(path)
            end
        end

        @testset "key present, size changed — warns" begin
            image = tempname() * ".png"
            path = tempname() * ".toml"
            try
                cp(joinpath(FIXTURE_DIR, "small_rgb.png"), image)
                session = new_session(image, 64, 64)
                add_point!(session, 32.0, 32.0)
                save_session(session, path)

                original_size = filesize(image)

                # Stand in for the image being re-saved, edited, or replaced.
                open(image, "a") do io
                    write(io, zeros(UInt8, 128))
                end
                @test filesize(image) != original_size

                loaded = @test_logs (:warn,) load_session(path)

                # A mismatch is suspicious, not invalid — the session loads.
                @test loaded isa CountSession
                @test length(loaded.points) == 1
                @test loaded.image_path == image
            finally
                isfile(image) && rm(image)
                isfile(path) && rm(path)
            end
        end
    end

    # -------------------------------------------------------------------
    # Missing required keys
    # -------------------------------------------------------------------
    @testset "missing required keys raise ArgumentError" begin
        required = [
            "image_path",
            "image_width",
            "image_height",
            "active_tag",
            "marker_size",
            "tags",
            "points",
        ]

        session = new_session("moths.jpg", 3456, 5184)
        add_point!(session, 100.0, 200.0)

        complete = tempname() * ".toml"
        try
            save_session(session, complete)
            full = TOML.parsefile(complete)

            for key in required
                truncated = tempname() * ".toml"
                try
                    data = copy(full)
                    delete!(data, key)
                    open(truncated, "w") do io
                        TOML.print(io, data; sorted = true)
                    end

                    # ArgumentError, not the raw KeyError a bare index gives.
                    @test_throws ArgumentError load_session(truncated)

                    err = try
                        load_session(truncated)
                    catch e
                        e
                    end
                    @test err isa ArgumentError
                    @test occursin(key, err.msg)
                    @test occursin(truncated, err.msg)
                finally
                    isfile(truncated) && rm(truncated)
                end
            end
        finally
            isfile(complete) && rm(complete)
        end
    end

    # -------------------------------------------------------------------
    # Scale calibration
    # -------------------------------------------------------------------
    @testset "scale calibration persistence" begin

        @testset "round trip with a scale set" begin
            session = new_session("moths.jpg", 1000, 2000)
            add_point!(session, 100.0, 200.0)
            set_scale!(session, 100.0, 100.0, 200.0, 100.0, 2.5, "mm")

            path = tempname() * ".toml"
            try
                save_session(session, path)

                # The table is laid out as documented.
                raw = TOML.parsefile(path)
                @test haskey(raw, "scale")
                @test raw["scale"]["real_distance"] == 2.5
                @test raw["scale"]["unit"] == "mm"
                @test raw["scale"]["point_1"] == [0.1, 0.05]
                @test raw["scale"]["point_2"] == [0.2, 0.05]

                loaded = load_session(path)

                @test loaded.has_scale == true
                @test loaded.scale_real_distance == session.scale_real_distance
                @test loaded.scale_unit == session.scale_unit
                @test loaded.scale_point_1 == session.scale_point_1
                @test loaded.scale_point_2 == session.scale_point_2

                # Which means the derived quantities survive too.
                @test scale_pixel_distance(loaded) ≈ scale_pixel_distance(session)
                @test pixels_to_real(loaded, 40.0) ≈ pixels_to_real(session, 40.0)
                @test real_to_pixels(loaded, 1.0) ≈ real_to_pixels(session, 1.0)
            finally
                isfile(path) && rm(path)
            end
        end

        @testset "an unrecognised unit survives a round trip" begin
            session = new_session("moths.jpg", 1000, 2000)
            @test_logs (:warn,) set_scale!(
                session,
                0.0,
                0.0,
                100.0,
                0.0,
                1.0,
                "grid square",
            )

            path = tempname() * ".toml"
            try
                save_session(session, path)
                loaded = @test_logs (:warn,) load_session(path)
                @test loaded.scale_unit == "grid square"
                @test loaded.has_scale == true
            finally
                isfile(path) && rm(path)
            end
        end

        @testset "round trip without a scale writes no [scale] table" begin
            session = new_session("moths.jpg", 1000, 2000)
            add_point!(session, 100.0, 200.0)

            path = tempname() * ".toml"
            try
                save_session(session, path)

                raw = TOML.parsefile(path)
                @test !haskey(raw, "scale")
                @test !occursin("[scale]", read(path, String))

                # Structurally a version-2 file apart from the version number
                # and the new next_id key.
                version_2_keys = [
                    "active_tag",
                    "image_height",
                    "image_path",
                    "image_width",
                    "marker_size",
                    "points",
                    "tags",
                ]
                @test sort(collect(keys(raw))) ==
                      sort([version_2_keys; "format_version"; "next_id"])

                loaded = load_session(path)
                @test loaded.has_scale == false
                @test loaded.scale_real_distance == 0.0
                @test loaded.scale_unit == ""
                @test loaded.scale_point_1 == (0.0, 0.0)
                @test loaded.scale_point_2 == (0.0, 0.0)
                @test scale_pixel_distance(loaded) == 0.0
            finally
                isfile(path) && rm(path)
            end
        end

        @testset "clearing a scale removes it from the file" begin
            session = new_session("moths.jpg", 1000, 2000)
            set_scale!(session, 0.0, 0.0, 100.0, 0.0, 1.0, "mm")
            clear_scale!(session)

            path = tempname() * ".toml"
            try
                save_session(session, path)
                @test !haskey(TOML.parsefile(path), "scale")
                @test load_session(path).has_scale == false
            finally
                isfile(path) && rm(path)
            end
        end

        @testset "the v0.1.0 fixture has no scale" begin
            session = @test_logs load_session(V0_1_0_SESSION)
            @test session.has_scale == false
            @test session.scale_real_distance == 0.0
            @test session.scale_unit == ""
            @test session.scale_point_1 == (0.0, 0.0)
            @test session.scale_point_2 == (0.0, 0.0)
        end

        @testset "a version-2 file has no scale" begin
            # A real version-2 file: what this ImageTally writes, minus the
            # keys version 2 did not have.
            session = new_session("moths.jpg", 1000, 2000)
            add_point!(session, 100.0, 200.0)
            saved = tempname() * ".toml"
            path = ""
            try
                save_session(session, saved)
                data = TOML.parsefile(saved)
                data["format_version"] = 2
                delete!(data, "next_id")
                path = write_toml(data)

                loaded = @test_logs load_session(path)
                @test loaded.has_scale == false
                @test loaded.scale_unit == ""
                @test length(loaded.points) == 1
                @test loaded.next_id == 2
            finally
                isfile(saved) && rm(saved)
                isfile(path) && rm(path)
            end
        end

        @testset "the unit is normalised on load" begin
            # A file written by an older or hand-edited source: the MICRO SIGN
            # (U+00B5) and the `um` alias both appear in the wild.
            for stored in ["µm", "um", " Microns "]
                session = new_session("moths.jpg", 1000, 2000)
                set_scale!(session, 0.0, 0.0, 100.0, 0.0, 1.0, "mm")

                saved = tempname() * ".toml"
                path = ""
                try
                    save_session(session, saved)
                    data = TOML.parsefile(saved)
                    data["scale"]["unit"] = stored
                    path = write_toml(data)

                    loaded = load_session(path)
                    @test loaded.scale_unit == "μm"
                    @test loaded.scale_unit in VALID_UNITS
                finally
                    isfile(saved) && rm(saved)
                    isfile(path) && rm(path)
                end
            end
        end

        @testset "a malformed [scale] table raises ArgumentError" begin
            session = new_session("moths.jpg", 1000, 2000)
            set_scale!(session, 0.0, 0.0, 100.0, 0.0, 1.0, "mm")

            saved = tempname() * ".toml"
            try
                save_session(session, saved)
                full = TOML.parsefile(saved)

                @testset "missing key $key" for key in [
                    "real_distance",
                    "unit",
                    "point_1",
                    "point_2",
                ]
                    data = copy(full)
                    data["scale"] = delete!(copy(full["scale"]), key)
                    path = write_toml(data)
                    try
                        @test_throws ArgumentError load_session(path)

                        err = try
                            load_session(path)
                        catch e
                            e
                        end
                        @test err isa ArgumentError
                        # Qualified, so it is clear which table is missing it.
                        @test occursin("scale.$key", err.msg)
                        @test occursin(path, err.msg)
                    finally
                        isfile(path) && rm(path)
                    end
                end

                @testset "bad point $key = $bad" for key in ["point_1", "point_2"],
                    bad in [[0.5], [0.1, 0.2, 0.3], Any[], [0.1, "x"], 0.5]

                    data = copy(full)
                    data["scale"] = merge(full["scale"], Dict(key => bad))
                    path = write_toml(data)
                    try
                        @test_throws ArgumentError load_session(path)

                        err = try
                            load_session(path)
                        catch e
                            e
                        end
                        @test err isa ArgumentError
                        @test occursin("scale.$key", err.msg)
                    finally
                        isfile(path) && rm(path)
                    end
                end

                @testset "non-positive real_distance $bad" for bad in [0.0, -1.0, -2.5]
                    data = copy(full)
                    data["scale"] = merge(full["scale"], Dict("real_distance" => bad))
                    path = write_toml(data)
                    try
                        @test_throws ArgumentError load_session(path)

                        err = try
                            load_session(path)
                        catch e
                            e
                        end
                        @test err isa ArgumentError
                        @test occursin("scale.real_distance", err.msg)
                        @test occursin("positive", err.msg)
                    finally
                        isfile(path) && rm(path)
                    end
                end
            finally
                isfile(saved) && rm(saved)
            end
        end
    end

    # -------------------------------------------------------------------
    # next_id
    # -------------------------------------------------------------------
    @testset "next_id persistence" begin

        @testset "round trips" begin
            session = new_session("moths.jpg", 1000, 2000)
            for i = 1:5
                add_point!(session, 100.0 * i, 100.0)
            end
            @test session.next_id == 6

            path = tempname() * ".toml"
            try
                save_session(session, path)
                @test TOML.parsefile(path)["next_id"] == 6
                @test load_session(path).next_id == 6
            finally
                isfile(path) && rm(path)
            end
        end

        @testset "does not regress when the highest points are deleted" begin
            # The reason next_id is stored rather than derived: ids already
            # written to an exported CSV must never be handed out twice.
            session = new_session("moths.jpg", 1000, 2000)
            for i = 1:5
                add_point!(session, 100.0 * i, 100.0)
            end
            delete_point!(session, 5)
            delete_point!(session, 4)
            @test maximum(p.id for p in session.points) == 3
            @test session.next_id == 6

            path = tempname() * ".toml"
            try
                save_session(session, path)
                reloaded = @test_logs load_session(path)
                @test reloaded.next_id == 6

                new_point = add_point!(reloaded, 500.0, 500.0)
                @test new_point.id == 6
            finally
                isfile(path) && rm(path)
            end
        end

        @testset "a stored value below the derived one warns and is ignored" begin
            session = new_session("moths.jpg", 1000, 2000)
            for i = 1:5
                add_point!(session, 100.0 * i, 100.0)
            end

            saved = tempname() * ".toml"
            path = ""
            try
                save_session(session, saved)
                data = TOML.parsefile(saved)
                data["next_id"] = 3   # would collide with points 3, 4, and 5
                path = write_toml(data)

                loaded = @test_logs (:warn,) load_session(path)
                @test loaded.next_id == 6
                @test add_point!(loaded, 500.0, 500.0).id == 6
            finally
                isfile(saved) && rm(saved)
                isfile(path) && rm(path)
            end
        end

        @testset "a non-integer value raises ArgumentError" begin
            session = new_session("moths.jpg", 1000, 2000)
            add_point!(session, 100.0, 100.0)

            saved = tempname() * ".toml"
            try
                save_session(session, saved)
                data = TOML.parsefile(saved)

                for bad in ["7", 7.5, [7]]
                    path = write_toml(merge(data, Dict("next_id" => bad)))
                    try
                        @test_throws ArgumentError load_session(path)

                        err = try
                            load_session(path)
                        catch e
                            e
                        end
                        @test err isa ArgumentError
                        @test occursin("next_id", err.msg)
                    finally
                        isfile(path) && rm(path)
                    end
                end
            finally
                isfile(saved) && rm(saved)
            end
        end

        @testset "a stored value equal to or above the derived one is used" begin
            session = new_session("moths.jpg", 1000, 2000)
            add_point!(session, 100.0, 100.0)

            saved = tempname() * ".toml"
            try
                save_session(session, saved)
                data = TOML.parsefile(saved)

                for stored in [2, 7, 100]
                    path = write_toml(merge(data, Dict("next_id" => stored)))
                    try
                        @test (@test_logs load_session(path)).next_id == stored
                    finally
                        isfile(path) && rm(path)
                    end
                end
            finally
                isfile(saved) && rm(saved)
            end
        end

        @testset "older files still derive it" begin
            # No next_id key at all: version 1 and version 2 behaviour.
            session = new_session("moths.jpg", 1000, 2000)
            for i = 1:3
                add_point!(session, 100.0 * i, 100.0)
            end

            saved = tempname() * ".toml"
            path = ""
            try
                save_session(session, saved)
                data = TOML.parsefile(saved)
                delete!(data, "next_id")
                data["format_version"] = 2
                path = write_toml(data)

                loaded = @test_logs load_session(path)
                @test loaded.next_id == 4
            finally
                isfile(saved) && rm(saved)
                isfile(path) && rm(path)
            end

            # And with no points, the derivation floors at 1.
            empty_session = new_session("moths.jpg", 1000, 2000)
            empty_path = ""
            try
                empty_path = tempname() * ".toml"
                save_session(empty_session, empty_path)
                data = TOML.parsefile(empty_path)
                delete!(data, "next_id")
                open(empty_path, "w") do io
                    TOML.print(io, data; sorted = true)
                end
                @test (@test_logs load_session(empty_path)).next_id == 1
            finally
                isfile(empty_path) && rm(empty_path)
            end

            # The v0.1.0 fixture derives 6 from its five points.
            @test load_session(V0_1_0_SESSION).next_id == 6
        end
    end

end
