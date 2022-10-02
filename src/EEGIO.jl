module EEGIO

using Mmap

abstract type EEGData end
export EEGData

# BDF files
include("formats/BDF.jl")
include("load/load_bdf.jl")
include("save/save_bdf.jl")
export BDF, BDFHeader, read_bdf, write_bdf

# EEG files
include("formats/EEG.jl")
include("load/load_eeg.jl")
export EEG, EEGHeader, read_eeg

end # module