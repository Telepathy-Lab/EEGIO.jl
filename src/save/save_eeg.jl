# TODO: Add saving into Int16
# TODO: Add checks if data (after resolution corrections) fits the Int16/Float32

function write_eeg(f::String, eeg::EEG)
    # Get the name for all three files
    file = split(f,"/")[end]
    filename = join(split(file,'.')[1:end-1],'.')
    
    # Write the header file
    open(filename*".vhdr", "w", lock = false) do fidh
        write_eeg_header(fidh, filename, eeg.header)
    end

    # Write the markers file
    open(filename*".vmrk", "w", lock = false) do fidm
        write_eeg_markers(fidm, filename, eeg.markers)
    end

    # Write the data file
    open(filename*".eeg", "w+", lock = false) do fidd
        write_eeg_data(fidd, eeg.header, eeg.data)
    end
end

# Writing the header information
function write_eeg_header(fid::IO, filename::String, header::EEGHeader)
    println(fid, """
    BrainVision Data Exchange Header File Version 1.0"
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

    println(fid, """
    [Binary Infos]
    BinaryFormat=IEEE_FLOAT_32
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
        1,\
        $(chns["unit"][i])\
        """)
    end

    println(fid, """

    [Comment]
    """)
end

# Writing the marker information
function write_eeg_markers(fid::IO, filename::String, markers::EEGMarkers)
    println(fid, """
    Brain Vision Data Exchange Marker File, Version 1.0
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
    ; Commas in type or description text are coded as "\\1".
    """)

    for i in eachindex(markers["number"])
        println(fid,"""Mk$(markers["number"][i])=\
        $(markers["type"][i]),\
        $(markers["description"][i]),\
        $(markers["position"][i]),\
        $(markers["duration"][i]),\
        $(markers["chanNum"][i])\
        """)
    end
end

# Writing the EEG data
function write_eeg_data(fid::IO, header::EEGHeader, data::Array)
    channels = length(header.channels["name"])
    samples = size(data)[1]

    raw = Mmap.mmap(fid, Matrix{Float32}, (channels, samples))

    convert_data!(raw, data, samples)

    finalize(raw)
end

# Writing data sample point (one row) at a time.
function convert_data!(raw::Array{Float32}, data::Array, samples::Integer)
    Threads.@threads for sample=1:samples
        @inbounds @views raw[:,sample] .= data[sample,:]
    end
end