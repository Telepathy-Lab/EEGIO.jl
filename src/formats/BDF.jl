mutable struct BDFHeader
    idCodeNonASCII::Int
    idCode::String
    subID::String
    recID::String
    startDate::String
    startTime::String
    nBytes::Int
    versionDataFormat::String
    nDataRecords::Int
    recordDuration::Int
    nChannels::Int
    chanLabels::Vector{String}
    transducer::Vector{String}
    physDim::Vector{String}
    physMin::Vector{Int}
    physMax::Vector{Int}
    digMin::Vector{Int}
    digMax::Vector{Int}
    prefilt::Vector{String}
    nSampRec::Vector{Int}
    reserved::Vector{String}
end

mutable struct BDF <: EEGData
    header::BDFHeader
    data::Matrix
    path::String
    file::String
end

Base.show(io::IO, bdf::BDFHeader) = print(io, "BDF Header")
Base.show(io::IO, bdf::BDF) = print(io, "BDF file")
#Base.show(io::IO, m::MIME"text/plain", bdf::BDF) = print(io, "BDF file, length $(round(bdf.header.nDataRecords/60,digits=2)) min., $(bdf.header.nChannels) channels")

Base.show(io::IO, ::Type{BDF}) = print(io, "BDF")