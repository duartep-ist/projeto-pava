include("ExceptionalExtended.jl")
using .ExceptionalExtended

exceptional_module = ExceptionalExtended

include("Tests.jl")
include("TestsExtended.jl")

println("The implementation successfully passed all tests!")
