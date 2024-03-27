"""
    read_set(f::String; kwargs...)

Reads EEG data from a SET file.

Providing a string containing valid path to a .set or .fdt file will result in reading 
the data as a Float64 matrix (provided all files share their name). Behavior of the function 
can be altered through additional keyword arguments listed below. Please consult the online 
documentation for a more thorough explanation of different options.

## Arguments:
- `f::String`
    - Path to the SET file (either .set or .fdt) to be read.

## Keywords:
- `onlyHeader::Bool=false`
    - Indicates whether to read only the metadata information from the .set file.
- `numPrecision::Type=Float64`
    - Specifies the numerical type of the data. Data points in SET and FDT files are stored 
      as 32-bit floats, therefore can be read as types with higher bit count per number.
      However, currently data stored within .set files is always read as Float64 (limitations
      of MAT.jl library that this package depends on) therefore ignoring this setting. For
      data stored in separate .fdt files, possible tested options are: `Float32`, `Float64`, 
      `Int32`, `Int64`. Since there is no clear benefit (except amount of memory used) to 
      using smaller number, the default is set to `Float64`.
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
      reading the file in chunks or :Mmap for using memory mapping. This setting is ignored
      for .set files, as they are always read in directly by MAT.jl.
- `tasks::Int=1`
    - Specifies how many concurent tasks will be spawn to read chunks of data. Tasks will use
      as many threads as there are available to Julia, but users can specify a higher number.
      Default is set to 1 (equal to single threaded run).

SET files are just MATLAB data structures saved in a file with a .set extension. They have
a specific structure imposed by the EEGLab software, but individual users might alter it
manually to contain additional fields or data types. There were also changes in the format
over the years, so there is always a possibility that some data were not extracted.
MAT.jl library reads in the data as a single dictionary, which is then parsed by this function.
To allow users to inspect all of the original metadata, it is being stored in the header field
`raw`. Please check it if you suspect some data are missing.
"""
function read_set(f::String; kwargs...)
    # Check if an existing path is given, then open the file
    if isfile(f)
        path, file = splitdir(f)

        # Check if it is a .fdt file and search for .set if yes
        root, ext = splitext(file)
        if ext == ".fdt"
            f = joinpath(path, root * ".set")
            if !isfile(f)
                error("$f file was expected, but does not exist.")
            end
        elseif ext != ".set"
            error("Expected a SET or FDT file, got $file.")
        end

        matopen(f) do fid
            read_set(fid; path=path, file=file, kwargs...)
        end
    else
        error("$f is not a valid file path.")
    end
end

# Internal function called by public API
function read_set(fid; path="", file="", onlyHeader=false, addOffset=true, numPrecision=Float64, 
    chanSelect=:All, chanIgnore=:None, timeSelect=:All, method=:Direct, tasks=1)

    # Check if the data is nested
    raw = find_set_data(fid)

    # Read the header
    header, rawData = read_set_header(raw)

    # If the data is stored in a separate file, read it
    if typeof(rawData) == String
        if onlyHeader || isempty(rawData)
            data = Array{Float64}(undef, (0,0))
        else
            if isfile(joinpath(path, rawData))
                rawDataPath = joinpath(path, rawData)

            else
                root, ext = splitext(file)
                rawDataPath = joinpath(path, root * ".fdt")
                if !isfile(rawDataPath)
                    error("Could not find the data file associated with the SET file. Please check 
                    if they are in the same folder.")
                end
                @warn "SET file was pointing to non-existing file, but an FDT file with the same name
                was found in the folder - reading it instead."
            end
            data = read_set_data(rawDataPath, header, numPrecision, chanSelect, chanIgnore, timeSelect, method, tasks)
        end

    # If the data is already in the file, read it
    elseif typeof(rawData) <: AbstractArray
        data = read_set_data(rawData, header, numPrecision, chanSelect, chanIgnore, timeSelect, tasks)
        # Remove the raw signal data from the header
        header.raw["data"] = ""
    else
        error("EEG data in file is of unknown type: $(type(rawData)).")
    end

    return SET(header, data, path, file)
end

# Find the EEG dataset in the file
function find_set_data(fid)
    vars = keys(fid)
    if "EEG" in vars
        return read(fid, "EEG")
    # Check for presence of one of obligatory fields
    elseif "setname" in vars
        return read(fid)
    else
        error("Could not find EEGLab data in the file. Only these fields are present: $vars.")
    end
end

"""
    read_set_header(raw::Dict)

Reads the metadata from the raw dictionary provided by MAT.jl and creates a SETHeader object.
"""
function read_set_header(raw::Dict)
    rawKeys = keys(raw)

    header = SETHeader()
    
    hNames = fieldnames(SETHeader)
    hTypes = fieldtypes(SETHeader)

    for i in eachindex(hNames)
        name = String(hNames[i])
        if (name in rawKeys) && !isempty(raw[name])
            if name == "chanlocs"
                channels = parse_set_channels(raw[name])
                setproperty!(header, hNames[i], channels)
            elseif typeof(raw[name]) <: AbstractMatrix && (1 in size(raw[name]))
                setproperty!(header, hNames[i], vec(raw[name]))
            else
                setproperty!(header, hNames[i], raw[name])
            end
        end
    end

    # Store the original metadata in the header
    setproperty!(header, :raw, raw)

    rawData = raw["data"]

    return header, rawData
end

# Parse channel information into a SETChannels object
function parse_set_channels(rawchans)
    rawKeys = keys(rawchans)

    channels = SETChannels()

    cNames = fieldnames(SETChannels)

    for i in eachindex(cNames)
        name = String(cNames[i])
        if (name in rawKeys) && !isempty(rawchans[name])
            if typeof(rawchans[name]) <: AbstractMatrix && (1 in size(rawchans[name]))
                setproperty!(channels, cNames[i], normalize_chans(rawchans[name], eltype(getfield(channels, cNames[i]))))
            else
                setproperty!(channels, cNames[i], rawchans[name])
            end
        end
    end

    return channels
end

# Convert channel data into vectors
function normalize_chans(rawVector, outputType)
    return vec(map(x -> isempty(x) ? get_zero(outputType) : x, rawVector))
end

get_zero(T::Any) = nothing
get_zero(T::Type{<:Number}) = zero(T)
get_zero(T::Type{<:AbstractString}) = ""

# Read data that is stored in the .set file
function read_set_data(rawData::Array, header::SETHeader, numPrecision, chanSelect, chanIgnore, timeSelect, tasks)
    dims = size(rawData)
    flip = header.nbchan == dims[1] ? true : false

    # Check if the number of samples matches the metadata
    header.pnts in dims ? nothing : warn("Data has different number of samples than declared in the metadata.")
    
    # Select a subset of channels/samples if user specified a narrower scope.
    chans = pick_channels(header, chanSelect)
    chans = setdiff(chans, pick_channels(header, chanIgnore))
    nChannels = length(chans)

    samples = pick_samples(header, timeSelect)
    nSamples = length(samples)

    # Flip the dimentions or just return the array, if it is not necessary
    dims = flip ? reverse(dims) : dims

    # Return the raw matrix if new dimensions are the same
    !flip && dims == (nSamples, nChannels) && return rawData

    data = Array{numPrecision}(undef, (nSamples, nChannels))

    flip ? flip_copy!(rawData, data, chans, samples, tasks) : noflip_copy!(rawData, data, chans, samples, tasks)

    update_header!(header, chans)
    update_header!(header, samples)

    return data
end

function flip_copy!(rawData, data, chans, samples, tasks)
    @tasks for sIdx in samples
        @set ntasks=tasks
        @views data[sIdx,:] .= rawData[chans, sIdx]
    end
end

function noflip_copy!(rawData, data, chans, samples, tasks)
    @tasks for sIdx in samples
        @set ntasks=tasks
        @views data[sIdx,:] .= rawData[sIdx, chans]
    end
end

function read_set_data(rawData::String, args...)
    if isfile(rawData)
        open(rawData) do fid
            read_set_data(fid, args...)
        end
    else
        error("$rawData is not a valid file path.")
    end
end

# Read data that is stored in a separate .fdt file
function read_set_data(rawData::IO, header::SETHeader, numPrecision, chanSelect, chanIgnore, timeSelect, method, tasks)
    rawChans = header.nbchan
    rawSamples = header.pnts
    rawSize = rawChans * rawSamples

    # Assume files contain Float32 numbers.
    dataType = Float32
    dataSize = sizeof(dataType)
    # Check if the size of data in the file matches parameters from the header
    seekend(rawData)
    if !(position(rawData) ÷ dataSize == rawSize)
        error("Data from file $(header.datfile) does not match the amount declared in the SET file.")
    end
    seekstart(rawData)
    
    # Select a subset of channels/samples if user specified a narrower scope.
    chans = pick_channels(header, chanSelect)
    chans = setdiff(chans, pick_channels(header, chanIgnore))
    nChannels = length(chans)

    samples = pick_samples(header, timeSelect)
    nSamples = length(samples)

    raw = read_method(rawData, method, Vector{dataType}, rawSize)
    data = Array{numPrecision}(undef, nSamples, nChannels)

    resolution = ones(numPrecision, rawChans)
    # We will use convert functions for EEG files as both filetypes use Float32 and similar 
    # data alignment.
    convert_data!(raw, data, dataType, rawChans, rawSamples, samples, chans, resolution, dataSize, 1)

    update_header!(header, chans)
    update_header!(header, samples)

    return data
end