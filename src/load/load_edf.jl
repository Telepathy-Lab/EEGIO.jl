
"""
    read_edf(f::String; kwargs...)

Read data from an EDF file.

Providing a string containing valid path to a .edf file will result in reading the data
as a Float64 matrix with an added offset. Behavior of the function can be altered through
additional keyword arguments listed below. Please consult the online documentation for
a more thorough explanation of different options.

## Arguments:
- `f::String`
    - Path to the EDF file to be read.

## Keywords:
- `onlyHeader::Bool=false`
    - Indicates whether to read the header information with data points or just the header.
- `addOffset::Bool=true`
    - Whether to add constant offset to data points to compensate for asymmetric digitalization
      done by the amplifier. This setting differs between software. Defaults to `true`.
- `numPrecision::Type=Float64`
    - Specifies the numerical type of the data. Data points in EDF files are stored as signed
      16-bit integers, therefore can be read as types with higher bit count per number.
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
      EDF files are read one record at a time (just as they are written), so the user can
      indicate which records to read.
      Using integers will select records with those indexes in the data.
      Using a tuple of floats will be interpreted as start and stop values in seconds
      and all records that fit this time span will be read.
      Using Symbol :All will read every record in the file. This is also the default.
- `method::Symbol=:Direct`
    - Choose the IO method of reading data. Can be either :Direct (set as the default) for 
      reading the file in chunks or :Mmap for using memory mapping.
- `tasks::Int=1`
    - Specifies how many concurent tasks will be spawn to read chunks of data. Tasks will use
      as many threads as there are available to Julia, but users can specify a higher number.
      Default is set to 1 (equal to single threaded run).

Current implementation follows closely the specification formulated in the original 
[scientific article](https://doi.org/10.1016/0013-4694(92)90009-7). Here, we used a summary 
from a [reference website](https://www.edfplus.info/specs/edf.html).
EDF+ extension is not yet implemented.
"""
function read_edf(f::String; kwargs...)
    # Check if an existing path is given, then open the file
    if ispath(f)
        path, file = splitdir(f)
        open(f) do fid
            read_edf(fid; path=path, file=file, kwargs...)
        end
    else
        error("$f is not a valid file path.")
    end
end

# Internal function called by public API
function read_edf(fid::IO; path="", file="", onlyHeader=false, addOffset=true, numPrecision=Float64, 
    chanSelect=:All, chanIgnore=:None, timeSelect=:All, method=:Direct, tasks=1)

    # Read the header
    header = read_edf_header(fid)

    if onlyHeader
        data = Vector{numPrecision}(undef, 0)
    else
        # Read the data
        data = read_edf_data(fid, header, addOffset, numPrecision, chanSelect, chanIgnore, timeSelect, method, tasks)
    end

    return EDF(header, data, path, file)
end

"""
    read_edf_header(::IO)

Read the header of a EDF file.
"""
function read_edf_header(fid::IO)
    # Read the general recording data
    version =           decodeString(fid, 8)
    patientID =         decodeString(fid, 80)
    recordingID =       decodeString(fid, 80)
    startDate =         decodeString(fid, 8)
    startTime =         decodeString(fid, 8)
    nBytes =            decodeNumber(fid, Int64, 8)
    reserved44 =        decodeString(fid, 44)
    nDataRecords =      decodeNumber(fid, Int64, 8)
    recordDuration =    decodeNumber(fid, Float64, 8)
    nChannels =         decodeNumber(fid, Int64, 4)

    # Read the data channel specific information
    chanLabels =    decodeChanStrings(fid, nChannels, 16)
    transducer =    decodeChanStrings(fid, nChannels, 80)
    physDim =       decodeChanStrings(fid, nChannels, 8)
    physMin =       decodeChanNumbers(fid, Float64, nChannels, 8)
    physMax =       decodeChanNumbers(fid, Float64, nChannels, 8)
    digMin =        decodeChanNumbers(fid, Float64, nChannels, 8)
    digMax =        decodeChanNumbers(fid, Float64, nChannels, 8)
    prefilt =       decodeChanStrings(fid, nChannels, 80)
    nSampRec =      decodeChanNumbers(fid, Int64, nChannels, 8)
    reserved32 =    decodeChanStrings(fid, nChannels, 32)

    return EDFHeader(version, patientID, recordingID, startDate, startTime, nBytes, 
    reserved44, nDataRecords, recordDuration, nChannels, chanLabels, transducer, 
    physDim, physMin, physMax, digMin, digMax, prefilt, nSampRec, reserved32)
end

# Main data read function that gets specialized based on user choices
function read_edf_data(fid::IO, header::EDFHeader, addOffset, numPrecision, chanSelect, chanIgnore, timeSelect, method, tasks)
    allSamples = header.nDataRecords .* header.nSampRec
    recSamples = sum(header.nSampRec)

    scaleFactors, offsets = resolve_offsets(header, addOffset, numPrecision)

    # Limiting the number of channels and records to a requested subset.
    records = pick_samples(header, timeSelect)
    chans = pick_channels(header, chanSelect)
    chans = setdiff(chans, pick_channels(header, chanIgnore))

    # Decide how to access the datafile
    raw = read_method(fid, method, Vector{Int16}, sum(allSamples))
    data = [Vector{numPrecision}(undef, len) for len in length(records) .* header.nSampRec[chans]]

    read_edf_data!(raw, data, header, recSamples, records, chans, scaleFactors, offsets, tasks)

    # Update the header to reflect the subset of data actually read.
    update_header!(header, records)
    update_header!(header, chans)

    return data
end

# Read data directly to a buffer in chunks
function read_edf_data!(raw::IO, data, header, recSamples, records, chans, scaleFactors, offsets, tasks)
    chanOffset = vcat([1], accumulate(+, header.nSampRec, init=1)[1:end-1])

    scratch = TaskLocalValue{Vector{Int16}}(() -> Vector{Int16}(undef, recSamples))
    dataStart = TaskLocalValue{Vector{Int}}(() -> Vector{Int}(undef, length(chans)))
    dataEnd = TaskLocalValue{Vector{Int}}(() -> Vector{Int}(undef, length(chans)))

    posi = position(raw)
    readLock = ReentrantLock()

    @tasks for recIdx in records
        @set scheduler = DynamicScheduler(; nchunks=tasks)
        parse_record!(raw, data, scratch[], dataStart[], dataEnd[], recIdx, header, readLock, posi, recSamples, chans, chanOffset, scaleFactors, offsets)
    end

    return nothing
end

# Read data from on record into a buffer and copy it to the output matrix
function parse_record!(fid, data, scratch, dataStart, dataEnd, recIdx, header, readLock, posi, recSamples, chans, chanOffset, scaleFactors, offsets)
    @views dataStart .= (recIdx-1) .* header.nSampRec[chans] .+ 1
    @views dataEnd .= recIdx .* header.nSampRec[chans]
    rawOffset = posi + 2 * (recIdx-1) * recSamples
    lock(readLock) do 
        seek(fid, rawOffset)
        read!(fid, scratch)
    end

    for col in eachindex(data)
        parse_channel!(scratch, data, col, chans, dataStart, dataEnd, 0, chanOffset, header.nSampRec, scaleFactors, offsets)
    end

    return nothing
end

# Read data through mmap
function read_edf_data!(raw::Vector, data, header, recSamples, records, chans, scaleFactors, offsets, tasks)
    chanOffset = vcat([1], accumulate(+, header.nSampRec, init=1)[1:end-1])

    dataStart = TaskLocalValue{Vector{Int}}(() -> Vector{Int}(undef, length(chans)))
    dataEnd = TaskLocalValue{Vector{Int}}(() -> Vector{Int}(undef, length(chans)))

    @tasks for ridx in records
        @set scheduler = DynamicScheduler(; nchunks=tasks)
        parse_record!(raw, data, header, records, ridx, recSamples, chans, chanOffset, dataStart[], dataEnd[], scaleFactors, offsets)
    end

    return nothing
end

# Find the indices of the record in the input vector and copy it to the output matrix
function parse_record!(raw::Vector{Int16}, data, header, records, ridx, recSamples, chans, chanOffset, dataStart, dataEnd, scaleFactors, offsets)
    rawOffset = (records[ridx] - 1) * recSamples
    @views dataStart .= (ridx - 1) .* header.nSampRec[chans] .+ 1
    @views dataEnd .= ridx .* header.nSampRec[chans]

    for col in eachindex(data)
        parse_channel!(raw, data, col, chans, dataStart, dataEnd, rawOffset, chanOffset, header.nSampRec, scaleFactors, offsets)
    end

    return nothing
end

# Copy data for a channel with promotion to a longer Integer, if necessary
@inline function parse_channel!(raw::Vector{Int16}, data::Vector{Vector{T}}, col, chans, dataStart, dataEnd, rawOffset, chanOffset, nSampRec, scaleFactors, offsets) where T <: Integer
    @views data[col][dataStart[col]:dataEnd[col]] .= raw[rawOffset+chanOffset[chans[col]]:rawOffset+chanOffset[chans[col]]+nSampRec[chans[col]]-1]
end

# Copy data for a channel with promotion to a floating point number with scaling and offset correction
@inline function parse_channel!(raw::Vector{Int16}, data::Vector{Vector{T}}, col, chans, dataStart, dataEnd, rawOffset, chanOffset, nSampRec, scaleFactors, offsets) where T <: AbstractFloat
    @views data[col][dataStart[col]:dataEnd[col]] .= raw[rawOffset+chanOffset[chans[col]]:rawOffset+chanOffset[chans[col]]+nSampRec[chans[col]]-1] .* scaleFactors[chans[col]] .+ offsets[chans[col]]
end
