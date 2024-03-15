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
- `method::Symbol=:Direct`
    - Choose the IO method of reading data. Can be either :Direct (set as the default) for 
      reading the file in chunks or :Mmap for using memory mapping.
- `tasks::Int=1`
    - Specifies how many concurent tasks will be spawn to read chunks of data. Tasks will use
      as many threads as there are available to Julia, but users can specify a higher number.
      Default is set to 1 (equal to single threaded run).

Current implementation follows closely the specification formulated by [BrainVision]
(https://www.brainproducts.com/download/specification-of-brainvision-core-data-format-1-0/).
However the contents of the header and marker files can differ substantially, 
even if recorded with BrainVision hardware. If your files are not read properly, open an
issue on github and try to provide a sample dataset to reproduce the problem.
"""
function read_eeg(f::String; onlyHeader=false, onlyMarkers=false, numPrecision=Float64, 
    chanSelect=:All, chanIgnore=:None, timeSelect=:All, method=:Direct, tasks=1)

    path, file = splitdir(f)
    # Check if an existing path is given and find relevant files
    if !ispath(path)
        error("$path is not a valid path.")
    elseif !isfile(f)
        error("Could not find requested file at $f.")
    else
        headerFile, dataFile, markerFile = find_eeg_files(f, onlyHeader, onlyMarkers)
    end

    # Read the header
    header = read_eeg_header(headerFile)

    # Read the markers
    if onlyHeader
        # Create an empty EEGMarkers object
        markers = EEGMarkers(empty=true)
    else
        hvmrk = joinpath(splitdir(f)[1], header.common["MarkerFile"])
        if splitdir(markerFile)[2] == header.common["MarkerFile"]
            if isempty(header.common["MarkerFile"])
                markers = EEGMarkers()
            else
                markers = read_eeg_markers(markerFile)
            end
        elseif isempty(markerFile)
            if isfile(hvmrk)
                markers = read_eeg_markers(hvmrk)
            else
                error("Could not find the marker file from the header in the folder.")
            end
        elseif isempty(header.common["MarkerFile"])
            markers = EEGMarkers()
        else
            if isfile(hvmrk)
                error("Marker file with the same name exists in the folder, but the header points to another file.")
            else
                @warn "Marker file from the header does not exist, reading a marker file with the same name instead."
                markers = read_eeg_markers(markerFile)
            end
        end
    end

    # Read only header or header and markers if user asked for it.
    if onlyHeader | onlyMarkers
        data = Array{numPrecision}(undef, (0,0))
    else
        data = open(dataFile) do fid
            read_eeg_data(fid, header, markers, numPrecision, chanSelect, chanIgnore, timeSelect, method, tasks)
        end
    end

    return EEG(header, markers, data, path, splitext(file)[1])
end

# Try to locate all files from the triplet
function find_eeg_files(f::String, onlyHeader, onlyMarkers)
    path, file = splitdir(f)
    root, ext = splitext(file)

    if ext == ".eeg"
        headerFile = find_eeg_header(path, root)
        dataFile = f
        markerFile = onlyHeader ? "" : find_eeg_markers(path, root)
    elseif ext in [".vhdr", ".ahdr"]
        headerFile = f
        dataFile = (onlyHeader | onlyMarkers) ? "" : find_eeg_data(path, root)
        markerFile = onlyHeader ? "" : find_eeg_markers(path, root)
    elseif ext == ".vmrk"
        headerFile = find_eeg_header(path, root)
        dataFile = (onlyHeader | onlyMarkers) ? "" : find_eeg_data(path, root)
        markerFile = f
    else
        error("Unknown file type $f. Expected .vhdr, .eeg, or .vmrk file types.")
    end

    return headerFile, dataFile, markerFile
end

# Check if a header file with a certain name exists
function find_eeg_header(path, root)
    if isfile(joinpath(path, root * ".vhdr")) 
        headerFile = joinpath(path, root * ".vhdr")
    elseif isfile(joinpath(path, root * ".ahdr")) 
        headerFile = joinpath(path, root * ".ahdr")
    else
        error("Could not find the header file at $(joinpath(path, root * ".vhdr"))")
    end

    return headerFile
end

# Check if a data file with a certain name exists
function find_eeg_data(path, root)
    if isfile(joinpath(path, root * ".eeg")) 
        dataFile = joinpath(path, root * ".eeg")
    else
        error("Could not find the data file at $(joinpath(path, root * ".eeg"))")
    end

    return dataFile
end

# Check if a marker file with a certain name exists
function find_eeg_markers(path, root)
    if isfile(joinpath(path, root * ".vmrk")) 
        markerFile = joinpath(path, root * ".vmrk")
    else
        markerFile = ""
    end

    return markerFile
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


function read_eeg_data(fid::IO, header::EEGHeader, markers::EEGMarkers, numPrecision, chanSelect, chanIgnore, timeSelect, method, tasks)
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
    chans = pick_channels(header, chanSelect)
    chans = setdiff(chans, pick_channels(header, chanIgnore))
    nChannels = length(chans)

    samples = pick_samples(header, timeSelect, nDataSamples)
    nSamples = length(samples)

    # Update header and markers to match the subsets
    update_header!(header, chans)
    update_markers!(markers, samples)

    raw = read_method(fid, method, Matrix{header.binary}, (nDataChannels, nDataSamples))
    data = Array{numPrecision}(undef, (nSamples, nChannels))

    convert_data!(raw, data, header, nDataChannels, nDataSamples, samples, chans, resolution, bytes, tasks)

    finalize(raw)
    return data
end

# Mmap version
function convert_data!(raw::Array, data, header, nDataChannels, nDataSamples, samples, chans, resolution, bytes, tasks)

    @tasks for sidx in eachindex(samples)
        @set scheduler = DynamicScheduler(; nchunks=tasks)
        convert_chunk!(raw, data, samples[sidx], sidx, chans, resolution)
    end

    return nothing
end

# Direct version
function convert_data!(raw::IO, data, header, nDataChannels, nDataSamples, samples, chans, resolution, bytes, tasks)
    readLock = ReentrantLock()

    # Divide the input data into 2 MB chunks to reduce the number of read calls
    offset = nDataChannels * bytes
    maxChunk = 2_000_000 ÷ offset

    scratch = TaskLocalValue{Array{header.binary}}(() -> Array{header.binary}(undef, (nDataChannels, maxChunk)))
    
    filechunks = collect(partition(1:length(samples), maxChunk))

    @tasks for chunk in filechunks
        @set scheduler = DynamicScheduler(; nchunks=tasks)
        convert_chunk!(raw, chunk, scratch[], data, samples, chans, resolution, offset, readLock)
    end

    return nothing
end

function convert_chunk!(raw::IO, chunk, scratch, data, samples, chans, resolution, offset, readlock)
    samplePosition = (samples[chunk[1]] - 1) * offset
    lock(readlock) do 
        seek(raw, samplePosition)
        read!(raw, view(scratch, :, 1:length(chunk)))
    end

    for dataIdx in eachindex(chunk)
        convert_chunk!(scratch, data, samples[chunk[dataIdx]], dataIdx, chans, resolution)
    end

    return nothing
end

function convert_chunk!(scratch, data::Array{T}, scratchIdx, dataIdx, chans, resolution) where T <: AbstractFloat
    @inbounds @views data[scratchIdx,:] .= T.(scratch[chans, dataIdx]) .* resolution[chans]
end

function convert_chunk!(scratch, data::Array{T}, scratchIdx, dataIdx, chans, resolution) where T <: Integer
    @inbounds @views data[scratchIdx,:] .= round.(T, scratch[chans, dataIdx] .* resolution[chans])
end

function convert_chunk!(scratch::Array{Float32}, data::Array{Float32}, scratchIdx, dataIdx, chans, resolution)
    @inbounds @views data[scratchIdx,:] .= scratch[chans, dataIdx] .* resolution[chans]
end

function convert_chunk!(scratch::Array{Int16}, data::Array{Int16}, scratchIdx, dataIdx, chans, resolution)
    @inbounds @views data[scratchIdx,:] .= scratch[chans, dataIdx]
end