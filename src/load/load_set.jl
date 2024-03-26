function read_set(f::String; kwargs...)
    # Check if an existing path is given, then open the file
    if ispath(f)
        path, file = splitdir(f)
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

    elseif typeof(rawData) <: AbstractArray
        data = read_set_data(rawData, header, numPrecision, chanSelect, chanIgnore, timeSelect, tasks)
    else
        error("EEG data in file is of unknown type: $(type(rawData)).")
    end

    return SET(header, data, path, file)
end

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

    rawData = raw["data"]

    return header, rawData
end

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

function normalize_chans(rawVector, outputType)
    return vec(map(x -> isempty(x) ? get_zero(outputType) : x, rawVector))
end

get_zero(T::Any) = nothing
get_zero(T::Type{<:Number}) = zero(T)
get_zero(T::Type{<:AbstractString}) = ""

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