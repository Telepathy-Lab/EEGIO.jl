mutable struct BDFHeader
    idCodeNonASCII::Int32
    idCode::String
    subID::String
    recID::String
    startDate::String
    startTime::String
    nBytes::Int32
    versionDataFormat::String
    nDataRecords::Int32
    recordDuration::Int32
    nChannels::Int32
    chanLabels::Vector{String}
    transducer::Vector{String}
    physDim::Vector{String}
    physMin::Vector{Int32}
    physMax::Vector{Int32}
    digMin::Vector{Int32}
    digMax::Vector{Int32}
    prefilt::Vector{String}
    nSampRec::Vector{Int32}
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