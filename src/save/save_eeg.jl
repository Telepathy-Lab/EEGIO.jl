
function write_eeg(f::String, eeg::EEG; overwrite=false, method="mmap", forceFloat=false)
    # Get the name for all three files
    path, file = splitdir(f)
    filename, ext = splitext(file)
    
    fhdr = joinpath(path, filename*".vhdr")
    fmrk = joinpath(path, filename*".vmrk")
    feeg = joinpath(path, filename*".eeg")
    # Check if the files already exist
    if any(isfile.([fhdr, fmrk, feeg]))
        if overwrite
            rm.([fhdr, fmrk, feeg], force=true)
        else
            error("Some files already exist. Use `overwrite=true` to overwrite them.")
        end
    end

    # Write the header file
    open(fhdr, "w") do fidh
        write_eeg_header(fidh, filename, eeg.header, forceFloat)
    end

    # Write the markers file
    open(fmrk, "w") do fidm
        write_eeg_markers(fidm, filename, eeg.markers)
    end

    # Write the data file
    open(feeg, "w+", lock = false) do fidd
        write_eeg_data(fidd, eeg.header, eeg.data, method, forceFloat)
    end
end

# Writing the header information
function write_eeg_header(fid::IO, filename::String, header::EEGHeader, forceFloat::Bool)
    println(fid, """
    BrainVision Data Exchange Header File Version 1.0
    ; Data created by EEGIO.jl package, version: $version
    """)

    println(fid, """
    [Common Infos]
    Codepage=UTF-8
    DataFile=$(filename).eeg
    MarkerFile=$(filename).vmrk
    DataFormat=$(header.common["DataFormat"])
    ; Data orientation: MULTIPLEXED=ch1,pt1, ch2,pt1 ...
    DataOrientation=$(header.common["DataOrientation"])
    NumberOfChannels=$(header.common["NumberOfChannels"])
    ; Sampling interval in microseconds
    SamplingInterval=$(header.common["SamplingInterval"])
    """)

    if forceFloat || header.binary == Float32
        binary = "IEEE_FLOAT_32"
    else
        binary = "INT_16"
    end
    println(fid, """
    [Binary Infos]
    BinaryFormat=$binary
    """)

    println(fid, """
    [Channel Infos]
    ; Each entry: Ch<Channel number>=<Name>,<Reference channel name>,
    ; <Resolution in "Unit">,<Unit>, Future extensions..
    ; Fields are delimited by commas, some fields might be omitted (empty).
    ; Commas in channel names are coded as "\\1".\
    """)

    chns = header.channels
    for i in eachindex(chns["name"])
        println(fid,"""Ch$(chns["number"][i])=\
        $(chns["name"][i]),\
        $(chns["reference"][i]),\
        $(chns["resolution"][i]),\
        $(chns["unit"][i])\
        """)
    end

    coords = header.coords
    if !isempty(coords) && typeof(coords["theta"]) != Vector{String}
        println(fid, """

        [Coordinates]""")

        for i in eachindex(coords["number"])
            println(fid,"""Ch$(coords["number"][i])=\
            $(coords["radius"][i]),\
            $(coords["theta"][i]),\
            $(coords["phi"][i])\
            """)
        end
    end

    if length(header.comments) > 0
        println(fid, """

        [Comment]""")

        for i in eachindex(header.comments)
            println(fid, header.comments[i])
        end
    end
end

# Writing the marker information
function write_eeg_markers(fid::IO, filename::String, markers::EEGMarkers)
    println(fid, """
    BrainVision Data Exchange Marker File, Version 1.0
    """)

    println(fid, """
    [Common Infos]
    Codepage=UTF-8
    DataFile=$(filename).eeg
    """)

    println(fid, """
    [Marker Infos]
    ; Each entry: Mk<Marker number>=<Type>,<Description>,<Position in data points>,
    ; <Size in data points>, <Channel number (0 = marker is related to all channels)>
    ; Fields are delimited by commas, some fields might be omitted (empty).
    ; Commas in type or description text are coded as "\\1".""")
    for i in eachindex(markers.number)
        println(fid,"""Mk$(markers.number[i])=\
        $(markers.type[i]),\
        $(markers.description[i]),\
        $(markers.position[i]),\
        $(markers.duration[i]),\
        $(markers.chanNum[i])\
        """)
    end
end

# Writing the EEG data
function write_eeg_data(fid::IO, header::EEGHeader, data::Array, method::String, forceFloat::Bool)
    channels = length(header.channels["name"])
    samples = size(data)[1]


    if forceFloat
        binary = Float32
    else
        binary = header.binary
    end

    if method == "mmap"
        raw = Mmap.mmap(fid, Matrix{binary}, (channels, samples))
        write_data!(raw, data, header.channels["resolution"], samples)
        finalize(raw)
    elseif method == "sequential"
        buffer = Vector{binary}(undef, channels)
        for row in eachrow(data)
            write_data!(fid, buffer, row, header.channels["resolution"])
        end
    else
        error("Unknown writing method: $method")
    end

end

# Writing Float32 data sample point (one row) at a time.
function write_data!(raw::Array{Float32}, data::Array, resolution::Vector{Float64}, samples::Integer)
    Threads.@threads for sample=1:samples
        @inbounds @views raw[:,sample] .= data[sample,:] ./ resolution
    end
end

# Writing Int16 data sample point (one row) at a time.
function write_data!(raw::Array{Int16}, data::Array, resolution::Vector{Float64}, samples::Integer)
    Threads.@threads for sample=1:samples
        @inbounds @views raw[:,sample] .= round.(Int16, data[sample,:] ./ resolution)
    end
end

# Writing Float32 data in a sequential manner.
function write_data!(fid::IO, buffer::Vector{Float32}, data, resolution::Vector{Float64})
    @inbounds @views buffer .= data ./ resolution
    write(fid, buffer)
end

# Writing Int16 data in a sequential manner.
function write_data!(fid::IO, buffer::Vector{Int16}, data, resolution::Vector{Float64})
    @inbounds @views buffer .= round.(Int16, data ./ resolution)
    write(fid, buffer)
end