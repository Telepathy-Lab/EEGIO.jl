using Test
using TestItemRunner

@run_package_tests

include("./test_formats.jl")
include("./test_load.jl")
include("./test_save.jl")
include("./test_utils.jl")