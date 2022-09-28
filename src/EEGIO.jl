module EEGIO

using Mmap

# BDF files
include("formats/BDF.jl")
include("load/load_bdf.jl")
include("save/save_bdf.jl")
export read_bdf, write_bdf

end # module