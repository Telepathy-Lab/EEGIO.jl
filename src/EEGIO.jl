module EEGIO

using Mmap

abstract type EEGData end
export EEGData

# BDF files
include("formats/BDF.jl")
include("load/load_bdf.jl")
include("save/save_bdf.jl")
export BDF, BDFHeader, read_bdf, write_bdf

end # module