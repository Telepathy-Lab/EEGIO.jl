mutable struct SETChannels
    labels::Vector{String}
    type::Vector{String}
    ref::Vector{String}
    identifier::Vector{Int64}
    description::Vector{String}
    urchan::Vector{Any}
    X::Vector{Float64}
    Y::Vector{Float64}
    Z::Vector{Float64}
    theta::Vector{Float64}
    radius::Vector{Float64}
    sph_phi::Vector{Float64}
    sph_radius::Vector{Float64}
    sph_theta::Vector{Float64}
end

SETChannels() = SETChannels(
    String[],String[],String[],Int[],String[], Any[],
    Float64[],Float64[],Float64[],Float64[],Float64[],Float64[],Float64[],Float64[]
)

mutable struct SETHeader <: Header
    # Basic information
    setname::String
    trials::Int64
    pnts::Int64
    nbchan::Int64
    srate::Float64
    xmin::Float64
    xmax::Float64
    times::Vector{Float64}
    ref::Union{String, Int64}
    history::Union{String, Vector{String}}
    comments::String
    etc::Dict{String, Any}
    saved::Union{String, Bool}
    # Data file
    datfile::String
    # Chennel locations
    chanlocs::SETChannels
    urchanlocs::Dict{String, Any}
    chaninfo::Dict{String, Any}
    splinefile::String
    # Events and epochs
    event::Dict{String, Any}
    urevent::Dict{String, Any}
    epoch::Dict{String, Any}
    eventdescription::Vector{String}
    epochdescription::Vector{String}
    # ICA
    icasphere::Array
    icaweights::Array
    icawinv::Array
    icaact::Array
    icasplinefile::String
    icachansind::Vector{Int64}
    dipfit::Dict{String, Any}
    # Dataset membership
    subject::String
    group::String
    condition::String
    run::Int
    session::Int
    # Data rejection
    specdata::Array
    specicaact::Array
    stats::Dict{String, Any}
    reject::Dict{String, Any}
end

# This is extremally ugly, but can be updated afterwards, reducing the need for a huge constructor later
SETHeader() = SETHeader(
    "", 0, 0, 0, 0., 0., 0., Float64[], 0, String[], "", Dict(), false,
    "", SETChannels(), Dict(), Dict(), "", Dict(), Dict(), Dict(), String[], String[],
    zeros(0,0), zeros(0,0), zeros(0,0), zeros(0,0), "", Int64[], Dict(),
    "", "", "", 0, 0, zeros(0,0), zeros(0,0), Dict(), Dict()
)

mutable struct SET <: EEGData
    header::SETHeader
    data::Array
    path::String
    file::String
end

Base.show(io::IO, set::SETHeader) = print(io, "SET Header")
Base.show(io::IO, set::SETChannels) = print(io, "SET Channels")

function Base.show(io::IO, set::SET)
    print(io,
    "SET file ($(set.header.nbchan) channels, \
    duration: $(round((set.header.pnts/(set.header.srate*60)),digits=2)) min.)"
    )
end