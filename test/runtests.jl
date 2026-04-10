using Test
using Dates
using ImageTally

@testset "ImageTally.jl" begin
    include("test_coordinates.jl")
    include("test_session.jl")
    include("test_io.jl")
    include("test_extension.jl")
end
