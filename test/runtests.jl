using Test
using Dates
using ImageTally

@testset "ImageTally.jl" begin
    include("test_coordinates.jl")
    include("test_session.jl")
    include("test_io.jl")
    include("test_images.jl")
    if get(ENV, "IMAGETALLY_TEST_GUI", "false") == "true"
        include("test_extension.jl")
    end
end
