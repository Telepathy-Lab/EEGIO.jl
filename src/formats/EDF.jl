mutable struct EDFHeader <: Header
    version::String
    patientID::String
    recordingID::String
    startDate::String
    startTime::String
    nBytes::Int64
    reserved44::String
    nDataRecords::Int64
    recordDuration::Float64
    nChannels::Int64
    chanLabels::Vector{String}
    transducer::Vector{String}
    physDim::Vector{String}
    physMin::Vector{Float64}
    physMax::Vector{Float64}
    digMin::Vector{Float64}
    digMax::Vector{Float64}
    prefilt::Vector{String}
    nSampRec::Vector{Int64}
    reserved32::Vector{String}
end

mutable struct EDF <: EEGData
    header::EDFHeader
    data::Vector
    path::String
    file::String
end

Base.show(io::IO, edf::EDFHeader) = print(io, "EDF Header")
function Base.show(io::IO, m::MIME"text/plain", edf::EDF) 
    print(io, 
    "EDF file ($(edf.header.nChannels) channels, \
    duration: $(round(edf.header.nDataRecords/60,digits=2)) min.)")
end