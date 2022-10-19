mutable struct EEGHeader
    common::Dict
    binary::Type
    channels::Dict
    coords::Dict
    comments::Int64
end

mutable struct EEGMarkers
    number::Vector{Int32}
    type::Vector{String}
    description::Vector{String}
    position::Vector{Int32}
    duration::Vector{Int32}
    chanNum::Vector{Int32}
end

mutable struct EEG <: EEGData
    header::EEGHeader
    markers::EEGMarkers
    data::Matrix
    path::String
    file::String
end

Base.show(io::IO, eeg::EEGHeader) = print(io, "EEG Header")
Base.show(io::IO, eeg::EEGMarkers) = print(io, "EEG Markers")
Base.show(io::IO, eeg::EEG) = print(io, "EEG file")
Base.show(io::IO, ::Type{EEG}) = print(io, "EEG")