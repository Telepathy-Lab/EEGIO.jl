# TODO: Make sure channel/range selection also corrects the appropriate header fields

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

Current implementation follows closely the specification formulated by [BioSemi]
(https://www.biosemi.com/faq/file_format.htm) that extends EDF format from 16 to 24-bit.
Therefore it will read only data produced by BioSemi equipment and software compliant with
the specification.
BDF+ extension is not yet implemented.
"""
function read_bdf(f::String; kwargs...)
    # Open file
    open(f) do fid
        read_bdf(fid; kwargs...)
    end
end

# Internal function called by public API and FileIO
function read_bdf(fid::IO; onlyHeader=false, addOffset=true, numPrecision=Float64,
    chanSelect=:All, chanIgnore=:None, timeSelect=:All, readStatus=true)
    
    # Preserve the path and the name of file
    filepath = splitdir(split(strip(fid.name, ['<','>']), ' ', limit=2)[2])
    path = abspath(filepath[1])
    file = filepath[2]
    
    # Read the header
    header = read_bdf_header(fid)

    if onlyHeader
        return header
    else
        # Read the data
        data = read_bdf_data(fid, header, addOffset, numPrecision, chanSelect, chanIgnore, timeSelect, readStatus)
        return BDF(header, data, path, file)
    end
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
    nBytes =            decodeNumber(fid, 8)
    versionDataFormat = decodeString(fid, 44)
    nDataRecords =      decodeNumber(fid, 8)
    recordDuration =    decodeNumber(fid, 8)
    nChannels =         decodeNumber(fid, 4)

    # Read the data channel specific information
    chanLabels =    decodeChanStrings(fid, nChannels, 16)
    transducer =    decodeChanStrings(fid, nChannels, 80)
    physDim =       decodeChanStrings(fid, nChannels, 8)
    physMin =       decodeChanNumbers(fid, nChannels, 8)
    physMax =       decodeChanNumbers(fid, nChannels, 8)
    digMin =        decodeChanNumbers(fid, nChannels, 8)
    digMax =        decodeChanNumbers(fid, nChannels, 8)
    prefilt =       decodeChanStrings(fid, nChannels, 80)
    nSampRec =      decodeChanNumbers(fid, nChannels, 8)
    reserved =      decodeChanStrings(fid, nChannels, 32)

    return BDFHeader(idCodeNonASCII, idCode, subID, recID, startDate, startTime, nBytes, 
    versionDataFormat, nDataRecords, recordDuration, nChannels, chanLabels, transducer, 
    physDim, physMin, physMax, digMin, digMax, prefilt, nSampRec, reserved)
end

# Helper functions for decoding string and numerical header entries
decodeString(fid, size) = strip(ascii(String(read!(fid, Array{UInt8}(undef, size)))))
decodeNumber(fid, size) = parse(Int, ascii(String(read!(fid, Array{UInt8}(undef, size)))))

# Helper function to decode channel specific string entries
function decodeChanStrings(fid, nChannels, size)
    arr = Array{String}(undef, nChannels)
    buf = read(fid, nChannels*size)
    for i=1:nChannels
        @inbounds arr[i] = strip(ascii(String(buf[(size*(i-1)+1):(size*i)])))
    end
    return arr
end

# Helper function to decode channel specific numerical entries
function decodeChanNumbers(fid, nChannels, size)
    arr = Array{Int}(undef, nChannels)
    buf = read(fid, nChannels*size)
    for i=1:nChannels
        @inbounds arr[i] = parse(Int, ascii(String(buf[(size*(i-1)+1):(size*i)])))
    end
    return arr
end

# Read the EEG data points to a preallocated array.
function read_bdf_data(fid::IO, header::BDFHeader, addOffset, numPrecision, chanSelect, chanIgnore, timeSelect, readStatus)
    nChannels = header.nChannels
    srate = Int(header.nSampRec[1] / header.recordDuration)
    scaleFactor = numPrecision.(header.physMax-header.physMin)./(header.digMax-header.digMin)

    #=
    Addition of offset value to data points seems to be a legacy from reading EDF files that
    have physical or digital values not distributed symmetrically around zero. Biosemi system
    is symmetrical, so adding the offset has no real impact and can be skipped. See here:
    http://www.biosemi.nl/forum/viewtopic.php?f=4&t=1520&sid=ba7f775f06adbaa165230fdf1ad55c1c

    However, for compatibility with other EEG software, adding offset is the default.
    It can be switched off through setting the parameter offset=false.
    =#
    if addOffset
        offset = Float64.(header.physMin .- (header.digMin .* scaleFactor))
    else
        offset = Int.(header.physMin .* 0)
    end
    
    # Limiting the number of channels and records to a requested subset.
    records = pick_samples(timeSelect, header)
    chans = pick_channels(chanSelect, header.nChannels, header.chanLabels)
    chans = setdiff(chans, pick_channels(chanIgnore, header.nChannels, header.chanLabels))
    if readStatus chans = check_status(chans, header) end

    # Update the header to reflect the subset of read data.
    update_header!(header, chans)

    raw = Mmap.mmap(fid);

    data = Array{numPrecision}(undef, (srate*length(records),length(chans)));
    convert_data!(raw, data, srate, records, chans, nChannels, scaleFactor, offset)
    finalize(raw)
    GC.gc(false)
    return data
end

# Always include status channel unless explicitly stated otherwise
function check_status(chans, header)
    ind = findfirst(isequal("Status"), header.chanLabels)
    if isnothing(ind) 
        error("No Status channel in the file!")
    elseif ind ∉ chans
        return [chans..., ind]
    else
        return chans
    end
end

# Function to update the header to reflect the subset of data actually read.
function update_header!(header::BDFHeader, chans)
    header.nBytes = (length(chans)+1)*256
    header.nChannels = length(chans)
    header.chanLabels = header.chanLabels[chans]
    header.transducer = header.transducer[chans]
    header.physDim = header.physDim[chans]
    header.physMin = header.physMin[chans]
    header.physMax = header.physMax[chans]
    header.digMax = header.digMax[chans]
    header.digMin = header.digMin[chans]
    header.prefilt = header.prefilt[chans]
    header.reserved = header.reserved[chans]
    header.nSampRec = header.nSampRec[chans]
end

# Loop through all segments for each channel
function convert_data!(raw::Array{UInt8}, data, srate, records, chans, nChannels, scaleFactor, offset)
    Threads.@threads for recIdx in eachindex(records)
        for chanIdx in eachindex(chans)
            for dataPoint=1:srate
                @fastmath sample = (records[recIdx]-1)*nChannels*srate + (chans[chanIdx]-1)*srate + dataPoint-1
                @fastmath dp = dataPoint+(recIdx-1)*srate
                convert!(raw, data, dp, sample, chans[chanIdx], chanIdx, scaleFactor, offset)
            end
        end
    end
end

# Convert 24-bit integer numbers into floats.
# Default conversion from digital to analog output.
function convert!(raw::Array{UInt8}, data::Array{<:AbstractFloat}, dp, sample, chan, chanIdx, scaleFactor, offset)
    @inbounds @fastmath data[dp,chanIdx] = ((((Int32(raw[3*sample+1]) << 8) | 
                                            (Int32(raw[3*sample+2]) << 16) | 
                                            (Int32(raw[3*sample+3]) << 24)) >> 8) * scaleFactor[chan]) + offset[chan]
end

# Convert 24-bit integer numbers into 32/64 bit integers.
# Used when 'digital' option was chosen.
function convert!(raw::Array{UInt8}, data::Array{<:Integer}, dp, sample, chan, chanIdx, scaleFactor, offset)
    @inbounds @fastmath data[dp,chanIdx] = (((Int32(raw[3*sample+1]) << 8) | 
                                            (Int32(raw[3*sample+2]) << 16) | 
                                            (Int32(raw[3*sample+3]) << 24)) >> 8)
end