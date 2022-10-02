mutable struct EEGHeader
    common::Dict
    binary::Type
    channels::Dict
    coords::Dict
    comments::Int64
end

mutable struct EEGMarkers
    markers::Dict
end

struct EEG
    header::EEGHeader
    markers::EEGMarkers
    data::Matrix
    path::String
    file::String
end