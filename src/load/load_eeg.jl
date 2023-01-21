# TODO: cover cases when user wants to read vhdr or vmrk file instead of eeg
# TODO: read data and markers from files stated in vhdr file
# TODO: check correctness with other files
# TODO: Decide what to do with comment section - read it in or leave out?

"""
    read_eeg(f::String; kwargs...)

Read data from an EEG file.

Providing a string containing valid path to a .eeg, .vhdr, or .vmrk file will result in 
reading the data as a Float64 matrix (provided all files share their name). Behavior of 
the function can be altered through additional keyword arguments listed below. Please 
consult the online documentation for a more thorough explanation of different options.

## Arguments:
- `f::String`
    - Path to the EEG file (either .eeg, .vhdr, or .vmrk) to be read.

## Keywords:
- `onlyHeader::Bool=false`
    - Indicates whether to read the header information with data points or just the header.
- `onlyMarkers::Bool=false`
    - Indicates whether to read the data points or just the header and markers.
- `numPrecision::Type=Float64`
    - Specifies the numerical type of the data. Data points in EEG files are stored as 16-bit
      integers or 32-bit floats, therefore can be read as types with higher bit count per number.
      Possible tested options: `Float32`, `Float64`, `Int32`, `Int64`. Since there is no clear
      benefit (except amount of memory used) to using smaller number, the default is set to 
      `Float64`.
- `chanSelect::Union{Int, Range, Vector{Int}, String, Vector{String}, Regex, Symbol}=:All`
    - Specifies the subset of channels to read from the data. Depending on the provided value
      you can select different subsets of channels.
      Using integers (either single number, range, or a vector) will select channels by their
      position in the data (e.g. chanSelect=[1,4,8], will pick the first, fourth, and eighth).
      Using strings or regex expression will pick all the channels with matching names stored
      in the header.
      Finally, you can provide symbols :None or :All to read neither or every channel available.
      Default is set to :All.
- `chanIgnore::Union{Int, UnitRange, Vector{Int}, String, Vector{String}, Regex, Symbol}=:None`
    - Specifies the subset of channel to omit while reading the data.
      Uses the same selectors as `chanSelect` and picked values are subtracted from the set
      of electrodes chosen by `chanSelect`. Default is set to :None.
- `timeSelect::Union{Int, UnitRange, Tuple{AbstractFloat}, Symbol}=:All`
    - Specifies the part of the time course of the data to be read.
      Using integers will select samples with those indexes in the data.
      Using a tuple of floats will be interpreted as start and stop values in seconds
      and all samples that fit this time span will be read.
      Using Symbol :All will read every sample in the file. This is also the default.


Current implementation follows closely the specification formulated by [BrainVision]
(https://www.brainproducts.com/download/specification-of-brainvision-core-data-format-1-0/).
However the contents of the header and marker files can differ substantially, 
even if recorded with BrainVision hardware. If your files are not read properly, open an
issue on github and try to provide a sample dataset to reproduce the problem.
"""
function read_eeg(f::String; kwargs...)
    # Open file
    open(f) do fid
        read_eeg(fid; kwargs...)
    end
end

# Internal function called by public API and FileIO
function read_eeg(fid::IO; onlyHeader=false, onlyMarkers=false, numPrecision=Float64, 
    chanSelect=:All, chanIgnore=:None, timeSelect=:All)

    # Preserve the path and the name of file
    filepath = splitdir(split(strip(fid.name, ['<','>']), ' ', limit=2)[2])
    path = abspath(filepath[1])
    file = filepath[2]

    # Assume header file shares the same name and check it for proper extension
    fName = rsplit(file,'.', limit=2)[1]
    
    if isfile(joinpath(path, fName * ".vhdr"))
        header_file = fName * ".vhdr"
    elseif isfile(joinpath(path, fName * ".ahdr"))
        header_file = fName * ".ahdr"
    else
        error("Cannot find header file for $fName")
    end

    # Read the header
    header = read_eeg_header(joinpath(path, header_file))
    
    if onlyHeader
        markers = EEGMarkers([],[],[],[],[],[])
    else
        if isfile(joinpath(path, header.common["MarkerFile"]))
            markers = read_eeg_markers(joinpath(path, header.common["MarkerFile"]))
        else
            @warn "No marker file found under name $(header.common["MarkerFile"])"
            markers = EEGMarkers([],[],[],[],[],[])
        end
    end

    # Read only header or header and markers if user asked for it.
    if !(onlyHeader | onlyMarkers)
        data = read_eeg_data(fid, header, markers, numPrecision, chanSelect, chanIgnore, timeSelect)
    else
        data = Array{numPrecision}(undef, (0,0))
    end

    return EEG(header, markers, data, path, file)
end

# Read the info from vhdr file
# Parsing functions return the line they stopped at in a hackish attmpt to account
# for header files without empty line between sections.
"""
    read_eeg_header(::String)

Reader the EEG header based on the name of file. 
"""
function read_eeg_header(f::String)
    # Initialize empty header, because not all fields are present in files
    header = EEGHeader(Dict(), Any, Dict(), Dict(), String[])
    open(f) do fid
        while !eof(fid)
            line = readline(fid)
        
            if occursin(r"\[Common .nfos\]", line)
                header.common, line = parse_common(fid)
            end
        
            if occursin(r"\[Binary .nfos\]", line)
                header.binary = parse_binary(fid)
            end
        
            if occursin(r"\[Channel .nfos\]", line)
                header.channels, line = parse_channels(fid)
            end
        
            if occursin("[Coordinates]", line)
                header.coords, line = parse_coordinates(fid)
            end
        
            if occursin("[Comment]", line)
                header.comments = parse_comments(fid)
            end
        end
    end
    return header
end

# Functions to parse specfic parts of vhdr file
function parse_common(fid)
    info = Dict()
    line = readline(fid)
    while !isempty(line) && line[1] != '['
        if line[1] != ';'
            key, value = split(line, '=')
            if occursin(key, "NumberOfChannels") || occursin(key, "SamplingInterval")
                value = parse(Int, value)
            end
            info[key] = value
        end
        line = readline(fid)
    end
    return info, line
end

function parse_binary(fid)
    line = readline(fid)
    key, value = split(line, '=')
    if isequal(value, "INT_16")
        binary = Int16
    elseif isequal(value, "IEEE_FLOAT_32")
        binary = Float32
    else
        error("Binary format does not match any from the specification.")
    end
    return binary
end

function parse_channels(fid)
    channels = Vector{Vector{String}}()
    line = readline(fid)
    while !isempty(line) && line[1] != '['
        if line[1] != ';'
            push!(channels, split(line,['=',',']))
        end
        line = readline(fid)
    end
    channels = reduce(hcat,channels)
    chans = Dict(
        "number" => parse.(Int, replace.(channels[1,:],"Ch"=>"")),
        "name" => channels[2,:],
        "reference" => channels[3,:],
        "resolution" => parse.(Float64, replace(channels[4,:], "" => "1"))
    )
    if size(channels)[1] == 5
        chans["unit"] = channels[5,:]
    elseif size(channels)[1] == 4
        chans["unit"] = "µV"
    end
    return chans, line
end

function parse_coordinates(fid)
    coordinates = Vector{Vector{String}}()
    line = readline(fid)
    while !isempty(line) && line[1] != '['
        if line[1] != ';'
            push!(coordinates, split(line,['=',',']))
        end
        line = readline(fid)
    end
    coordinates = reduce(hcat,coordinates)
    coords = Dict(
        "number" => parse.(Int, replace.(coordinates[1,:],"Ch"=>"")),
        "radius" => parse.(Int, replace(coordinates[2,:], "" => "NaN")),
        "theta" => parse.(Int, replace(coordinates[3,:], "" => "NaN")),
        "phi" => parse.(Int, replace(coordinates[4,:], "" => "NaN"))
    )
    return coords, line
end

# Write all comments to a vector
function parse_comments(fid)
    comments = String[]
    while !eof(fid)
        push!(comments, readline(fid))
    end
    return comments
end

# Read markers from vmrk file
function read_eeg_markers(f::String)
    open(f) do fid
        while !eof(fid)
            line = readline(fid)
            if occursin(r"\[Marker .nfos\]", line)
                return parse_markers(fid)
            end
        end
    end
end

# Parse lines from vmrk file
function parse_markers(fid)
    markers = Vector{Vector{String}}()
    line = readline(fid)
    while !isempty(line)
        if line[1] != ';'
            push!(markers, split(line,['=',',']))
        end
        line = readline(fid)
    end
    if length(markers[1]) > 6
        date = pop!(markers[1])
    else
        date = ""
    end

    markers = reduce(hcat,markers)

    number = parse.(Int, replace.(markers[1,:],"Mk"=>""))
    type = markers[2,:]
    description = markers[3,:]
    position = parse.(Int, replace(markers[4,:], "" => "NaN"))
    duration = parse.(Int, replace(markers[5,:], "" => "NaN"))
    chanNum = parse.(Int, replace(markers[6,:], "" => "NaN"))

    return EEGMarkers(number, type, description, position, duration, chanNum, date)
end

# Read the sensor data from eeg file
function read_eeg_data(fid::IO, header::EEGHeader, markers::EEGMarkers, numPrecision, chanSelect, chanIgnore, timeSelect)
    if header.binary == Int16
        bytes = 2
    elseif header.binary == Float32
        bytes = 4
    end
    
    # Calculate the size of data (as it's not in the header)
    size = Int(position(seekend(fid))/bytes)
    seekstart(fid)

    # Total number of channels and samples
    nDataChannels = length(header.channels["name"])
    nDataSamples = Int64(size/nDataChannels)
    resolution = header.channels["resolution"]

    # Select a subset of channels/samples if user specified a narrower scope.
    chans = pick_channels(chanSelect, nDataChannels, header.channels["name"])
    chans = setdiff(chans, pick_channels(chanIgnore, nDataChannels, header.channels["name"]))
    nChannels = length(chans)

    samples = pick_samples(timeSelect, nDataSamples, header)
    nSamples = length(samples)

    # Update header and markers to match the subsets
    update_header!(header, chans)
    update_markers!(markers, samples)

    raw = Mmap.mmap(fid, Matrix{header.binary}, (nDataChannels, nDataSamples))
    data = Array{numPrecision}(undef, (nSamples, nChannels))

    convert_data!(raw, data, samples, chans, resolution)

    finalize(raw)
    return data
end


# Covert data to Float
function convert_data!(raw::Array, data::Array{T}, samples, chans, resolution) where T <: AbstractFloat
    Threads.@threads for (idx, sample) in collect(enumerate(samples))
        @inbounds @views data[idx,:] .= T.(raw[chans,sample]) .* resolution[chans]
    end
end

# Promote data to bigger Int
function convert_data!(raw::Array, data::Array{T}, samples, chans, resolution) where T <: Integer
    Threads.@threads for (idx, sample) in collect(enumerate(samples))
        @inbounds @views data[idx,:] .= round.(T, raw[chans,sample] .* resolution[chans])
    end
end

# Copy data as Float32 format
function convert_data!(raw::Array{Float32}, data::Array{Float32}, samples, chans, resolution)
    Threads.@threads for (idx, sample) in collect(enumerate(samples))
        @inbounds @views data[idx,:] .= raw[chans,sample] .* resolution[chans]
    end
end

# Copy data as Int16 format
function convert_data!(raw::Array{Int16}, data::Array{Int16}, samples, chans, resolution)
    Threads.@threads for (idx, sample) in collect(enumerate(samples))
        @inbounds @views data[idx,:] .= raw[chans,sample]
    end
end