
"""
    read_bdf(f::String; kwargs...)

Read data from a BDF file.

Providing a string containing valid path to a .bdf file will result in reading the data
as a Float64 matrix with an added offset. Behavior of the function can be altered through
additional keyword arguments listed below. Please consult the online documentation for
a more thorough explanation of different options.

## Arguments:
- `f::String`
    - Path to the BDF file to be read.

## Keywords:
- `onlyHeader::Bool=false`
    - Indicates whether to read the header information with data points or just the header.
- `addOffset::Bool=true`
    - Whether to add constant offset to data points to compensate for asymmetric digitalization
      done by the amplifier. This setting differs between software. Defaults to `true`.
- `numPrecision::Type=Float64`
    - Specifies the numerical type of the data. Data points in BDF files are stored as signed
      24-bit integers, therefore can be read as types with higher bit count per number.
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
      BDF files are read one record at a time (just as they are written), so the user can
      indicate which records to read.
      Using integers will select records with those indexes in the data.
      Using a tuple of floats will be interpreted as start and stop values in seconds
      and all records that fit this time span will be read.
      Using Symbol :All will read every record in the file. This is also the default.
- `readStatus::Bool=true`
    - Specifies if the Status channel should be read. As this is a special channel,
      always placed at the end of the file and carrying trigger information along with some
      technical data about the hardware setup, this setting provides an option to ignore it.
      Please be aware, that its absence might generate errors in code that expects it (even
      if it is empty). Default is set to true. 
- `method::Symbol=:Direct`
    - Choose the IO method of reading data. Can be either :Direct (set as the default) for 
      reading the file in chunks or :Mmap for using memory mapping.
- `tasks::Int=1`
    - Specifies how many concurent tasks will be spawn to read chunks of data. Tasks will use
      as many threads as there are available to Julia, but users can specify a higher number.
      Default is set to 1 (equal to single threaded run).

Current implementation follows closely the specification formulated by [BioSemi]
(https://www.biosemi.com/faq/file_format.htm) that extends EDF format from 16 to 24-bit.
Therefore it will read only data produced by BioSemi equipment and software compliant with
the specification.
BDF+ extension is not yet implemented.
"""
function read_bdf(f::String; kwargs...)
    # Check if an existing path is given, then open the file
    if ispath(f)
        path, file = splitdir(f)
        open(f) do fid
            read_bdf(fid; path=path, file=file, kwargs...)
        end
    else
        error("$f is not a valid file path.")
    end
end

# Internal function called by public API
function read_bdf(fid::IO; path="", file="", onlyHeader=false, addOffset=true, numPrecision=Float64,
    chanSelect=:All, chanIgnore=:None, timeSelect=:All, readStatus=true, method=:Direct, tasks=1)
    
    # Read the header
    header = read_bdf_header(fid)

    if onlyHeader
        data = Array{numPrecision}(undef, (0, 0))
        status = BDFStatus(0)
    else
        # Read the data
        data, status = read_bdf_data(fid, header, addOffset, numPrecision, chanSelect, chanIgnore, timeSelect, readStatus, method, tasks)
    end
    return BDF(header, data, status, path, file)
end

"""
    read_bdf_header(::IO)

Read the header of a BDF file.
"""
function read_bdf_header(fid::IO)
    # Read the general recording data
    idCodeNonASCII =    Int(read(fid, UInt8))
    idCode =            decodeString(fid, 7)
    subID =             decodeString(fid, 80)
    recID =             decodeString(fid, 80)
    startDate =         decodeString(fid, 8)
    startTime =         decodeString(fid, 8)
    nBytes =            decodeNumber(fid, Int64, 8)
    versionDataFormat = decodeString(fid, 44)
    nDataRecords =      decodeNumber(fid, Int64, 8)
    recordDuration =    decodeNumber(fid, Int64, 8)
    nChannels =         decodeNumber(fid, Int64, 4)

    # Read the data channel specific information
    chanLabels =    decodeChanStrings(fid, nChannels, 16)
    transducer =    decodeChanStrings(fid, nChannels, 80)
    physDim =       decodeChanStrings(fid, nChannels, 8)
    physMin =       decodeChanNumbers(fid, Int64, nChannels, 8)
    physMax =       decodeChanNumbers(fid, Int64, nChannels, 8)
    digMin =        decodeChanNumbers(fid, Int64, nChannels, 8)
    digMax =        decodeChanNumbers(fid, Int64, nChannels, 8)
    prefilt =       decodeChanStrings(fid, nChannels, 80)
    nSampRec =      decodeChanNumbers(fid, Int64, nChannels, 8)
    reserved =      decodeChanStrings(fid, nChannels, 32)

    return BDFHeader(idCodeNonASCII, idCode, subID, recID, startDate, startTime, nBytes, 
    versionDataFormat, nDataRecords, recordDuration, nChannels, chanLabels, transducer, 
    physDim, physMin, physMax, digMin, digMax, prefilt, nSampRec, reserved)
end

# Read the EEG data points to a preallocated array.
function read_bdf_data(fid::IO, header::BDFHeader, addOffset, numPrecision, chanSelect, chanIgnore, timeSelect, readStatus, method, tasks)
    nChannels = header.nChannels
    srate = Int(header.nSampRec[1] / header.recordDuration)
    scaleFactors = numPrecision.(header.physMax-header.physMin)./(header.digMax-header.digMin)

    #=
    Addition of offset value to data points seems to be a legacy from reading EDF files that
    have physical or digital values not distributed symmetrically around zero. Biosemi system
    is symmetrical, so adding the offset has no real impact and can be skipped. See here:
    http://www.biosemi.nl/forum/viewtopic.php?f=4&t=1520&sid=ba7f775f06adbaa165230fdf1ad55c1c

    However, for compatibility with other EEG software, adding offset is the default.
    It can be switched off through setting the parameter offset=false.
    =#
    scaleFactors, offsets = resolve_offsets(header, addOffset, numPrecision)
    
    # Limiting the number of channels and records to a requested subset.
    records = pick_samples(header, timeSelect)
    chans = pick_channels(header, chanSelect)
    chans = setdiff(chans, pick_channels(header, chanIgnore))
    chans, statusIdx = check_status(header, chans)

    raw = read_method(fid, method, Vector{UInt8}, 3*header.nDataRecords*nChannels*srate)

    data = Array{numPrecision}(undef, (srate*length(records),length(chans)));
    if readStatus
        status = BDFStatus(srate*length(records))
    else
        status = BDFStatus(0)
    end

    convert_data!(raw, data, status, srate, records, chans, nChannels, statusIdx, scaleFactors, offsets, tasks)
    
    # Update the header to reflect the subset of data actually read.
    update_header!(header, records)
    update_header!(header, chans)

    return data, status
end

# Always include status channel unless explicitly stated otherwise
function check_status(header, chans)
    ind = findfirst(isequal("Status"), header.chanLabels)

    # Check if Status channel exists and is at the end of file
    if isnothing(ind) 
        error("No channel named Status in the file! If you want to ignore it, set readStatus=false.")
    elseif ind != length(header.chanLabels)
        @warn "Status is not the last channel as expected based on format specification. \
            Check if read data are correct."
    end

    # Remove Status from other channels and return them seperately
    if ind ∈ chans
        deleteat!(chans, ind)
        return chans, ind
    else
        return chans, ind
    end
end

# Read data from one record into a buffer and copy it to the output matrix
function convert_data!(raw::IO, data, status, srate, records, chans, nChannels, statusIdx, scaleFactors, offsets, tasks)

    posi = position(raw)
    readLock = ReentrantLock()

    @tasks for recIdx in 1:length(records)
        @set ntasks = tasks
        @local scratch = Array{UInt8}(undef, (3, srate, maximum([chans..., statusIdx])))
        convert_data!(raw, data, status, scratch, readLock, posi, srate, recIdx, records, chans, nChannels, statusIdx, scaleFactors, offsets)
    end

    return data
end

function convert_data!(raw::IO, data, status, scratch, readLock, posi, srate, recIdx, records, chans, nChannels, statusIdx, scaleFactors, offsets)
    
    rawOffset = 3 * (records[recIdx] - 1) * nChannels * srate + posi

    lock(readLock) do 
        seek(raw, rawOffset)
        read!(raw, scratch)
    end
    
    recordOffset = (recIdx-1) * srate

    parse_record!(scratch, data, status, recordOffset, chans, statusIdx, scaleFactors, offsets)

    return nothing
end

function parse_record!(raw, data, status, recordOffset, chans, statusIdx, scaleFactors, offsets)
    for (chanIdx, chan) in enumerate(chans)
        scaleFactor = scaleFactors[chan]
        offset = offsets[chan]
        idx = 0
        for triplet in eachcol(view(raw, :, :, chan))
            idx += 1
            parse_value!(triplet, data, recordOffset+idx, 0, chanIdx, scaleFactor, offset)
        end
    end

    # Parse Status values
    if !isempty(status)
        idx = 0
        for triplet in eachcol(view(raw, :, :, statusIdx))
            idx += 1
            parse_status!(triplet, status, recordOffset+idx, 0)
        end
    end

    return nothing
end

# Read data through mmap
function convert_data!(raw::Vector, data, srate, records, chans, nChannels, scaleFactors, offsets, tasks)
    @tasks for recIdx in 1:length(records)
        @set ntasks = tasks
        parse_record!(raw, data, srate, recIdx, records, chans, nChannels, scaleFactors, offsets)
    end
    finalize(raw)

    return nothing
end

function parse_record!(raw::Vector{UInt8}, data, srate, recIdx, records, chans, nChannels, scaleFactors, offsets)
    recordOffset = (records[recIdx] - 1) * nChannels * srate
    outputRecOffset = (recIdx - 1) * srate
    for chanIdx in eachindex(chans)
        scaleFactor = scaleFactors[chans[chanIdx]]
        offset = offsets[chans[chanIdx]]
        chanOffset = (chans[chanIdx] - 1) * srate
        for dataPoint in 1:srate
            sample = recordOffset + chanOffset + dataPoint - 1
            dp = dataPoint + outputRecOffset
            parse_value!(raw, data, dp, sample, chanIdx, scaleFactor, offset)
        end
    end

    return nothing
end

# Parsing the raw values into floats trough applying a scale factor and offest from the header
function parse_value!(raw, data::Array{<:AbstractFloat}, idx, sample, chanIdx, scaleFactor, offset)
    @inbounds data[idx, chanIdx] = (convert24to32(raw, sample) * scaleFactor) + offset
end

# Parsing the raw values into integers of chosen precision
function parse_value!(raw, data::Array{<:Integer}, idx, sample, chanIdx, scaleFactor, offset)
    @inbounds data[idx, chanIdx] = convert24to32(raw, sample)
end

# Converting the 24-bit (3-byte triplet) into 32-bit integer
function convert24to32(bytes, sample)
    return ((Int32(bytes[3*sample+1]) << 8) | 
            (Int32(bytes[3*sample+2]) << 16) | 
            (Int32(bytes[3*sample+3]) << 24)) >> 8
end

function parse_status!(raw, status, idx, sample)
    @inbounds status.low[idx] = raw[3*sample+1]
    @inbounds status.high[idx] = raw[3*sample+2]
    @inbounds status.status[idx] = raw[3*sample+3]
end
