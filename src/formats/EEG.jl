mutable struct EEGHeader
    common::Dict
    binary::Type
    channels::Dict
    coords::Dict
    comments::Vector{String}
end

mutable struct EEGMarkers
    number::Vector{Int}
    type::Vector{String}
    description::Vector{String}
    position::Vector{Int}
    duration::Vector{Int}
    chanNum::Vector{Int}
end

mutable struct EEG <: EEGData
    header::EEGHeader
    markers::EEGMarkers
    data::Matrix
    path::String
    file::String
end

function EEGHeader()
    
end

Base.show(io::IO, eeg::EEGHeader) = print(io, "EEG Header")
Base.show(io::IO, eeg::EEGMarkers) = print(io, "EEG Markers")
Base.show(io::IO, eeg::EEG) = print(io, "EEG file")
Base.show(io::IO, ::Type{EEG}) = print(io, "EEG")