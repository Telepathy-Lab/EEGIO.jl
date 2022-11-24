# TODO: cover cases when user wants to read vhdr or vmrk file instead of eeg
# TODO: read data and markers from files stated in vhdr file
# TODO: check correctness with other files
# TODO: allow for selection of channels / timespan
# TODO: allow for different precision of output e.g. Float64

function read_eeg(f::String; onlyHeader=false)
    open(f) do fid
        read_eeg(fid, onlyHeader=onlyHeader)
    end
end

function read_eeg(fid::IO; onlyHeader=false)

    # Preserve the path and the name of file
    filepath = splitdir(split(strip(fid.name, ['<','>']), ' ', limit=2)[2])
    path = abspath(filepath[1])
    file = filepath[2]

    # Assume header file shares the same name and check it for proper extension
    fName = rsplit(file,'.', limit=2)[1]
    @info path, file, fName
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
        return header
    else
        if isfile(joinpath(path, header.common["MarkerFile"]))
            markers = read_eeg_markers(joinpath(path, header.common["MarkerFile"]))
        else
            @warn "No marker file found under name $(header.common["MarkerFile"])"
            markers = EEGMarkers([],[],[],[],[],[])
        end
        data = read_eeg_data(fid, header)
        return EEG(header, markers, data, path, file)
    end
end

# Read the info from vhdr file
# Parsing functions return the line they stopped at in a hackish attmpt to account
# for header files without empty line between sections.
"""
    read_eeg_header(::String)

Reader the EEG header based on the name of file. 
"""
function read_eeg_header(f::String)
    header = EEGHeader(Dict(), Any, Dict(), Dict(), 0)
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
                @info "$line"
                header.comments = parse_comments(fid)
                #println("Header contains additionally $(header.comments) lines of comments.")
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
                value = parse(Int32, value)
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
        "number" => parse.(Int32, replace.(channels[1,:],"Ch"=>"")),
        "name" => channels[2,:],
        "reference" => channels[3,:],
        "resolution" => parse.(Float32, replace(channels[4,:], "" => "1"))
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
        "number" => parse.(Int32, replace.(coordinates[1,:],"Ch"=>"")),
        "radius" => parse.(Float64, replace(coordinates[2,:], "" => "NaN")),
        "theta" => parse.(Float64, replace(coordinates[3,:], "" => "NaN")),
        "phi" => parse.(Float64, replace(coordinates[4,:], "" => "NaN"))
    )
    return coords, line
end

# Count how big is the comment section
function parse_comments(fid)
    comment_lines = 0
    while !eof(fid)
        comment_lines += 1
        line = readline(fid)
    end
    return comment_lines
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
    if length(markers[1]) > 6#length(markers[2])
        date = pop!(markers[1])
    end

    markers = reduce(hcat,markers)

    number = parse.(Int32, replace.(markers[1,:],"Mk"=>""))
    type = markers[2,:]
    description = markers[3,:]
    position = parse.(Int32, replace(markers[4,:], "" => "NaN"))
    duration = parse.(Int32, replace(markers[5,:], "" => "NaN"))
    chanNum = parse.(Int32, replace(markers[6,:], "" => "NaN"))

    return EEGMarkers(number, type, description, position, duration, chanNum)
end

# Read the sensor data from eeg file
function read_eeg_data(fid::IO, header::EEGHeader)
    if header.binary == Int16
        bytes = 2
    elseif header.binary == Float32
        bytes = 4
    end
    
    size = Int32(position(seekend(fid))/bytes)
    seekstart(fid)

    channels = length(header.channels["name"])
    samples = Int64(size/channels)
    resolution = header.channels["resolution"]

    raw = Mmap.mmap(fid, Matrix{header.binary}, (channels, samples))
    data = Array{Float32}(undef, (samples, channels))

    convert_data!(raw, data, samples, resolution)

    finalize(raw)
    return data
end

# Covert data from Int16 format
function convert_data!(raw::Array{Int16}, data::Array, samples::Integer, resolution::Vector{Float32})
    Threads.@threads for sample=1:samples
        @inbounds @views data[sample,:] .= Float32.(raw[:,sample]) .* resolution
    end
end

# Covert data from Float32 format
function convert_data!(raw::Array{Float32}, data::Array, samples::Integer, resolution::Vector{Float32})
    Threads.@threads for sample=1:samples
        @inbounds @views data[sample,:] .= raw[:,sample] .* resolution
    end
end