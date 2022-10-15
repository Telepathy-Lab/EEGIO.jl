# TODO: Make sure channel/range selection also corrects the appropriate header fields

# Public function to use without FileIO 
function read_bdf(f::String; onlyHeader=false, addOffset=true, numPrecision=Float64,
    chanSelect=:All, chanIgnore=:None, timeSelect=:All, readStatus=true, digital=false)
    # Open file
    open(f) do fid
        read_bdf(fid, onlyHeader=onlyHeader, addOffset=addOffset, numPrecision=numPrecision,
        chanSelect=chanSelect, chanIgnore=chanIgnore, timeSelect=timeSelect, readStatus=readStatus, digital=digital)
    end
end

# Internal function called by public API and FileIO
function read_bdf(fid::IO; onlyHeader=false, addOffset=true, numPrecision=Float64,
    chanSelect=:All, chanIgnore=:None, timeSelect=:All, readStatus=true, digital=false)
    filepath = splitdir(split(strip(fid.name, ['<','>']), ' ')[2])
    path = abspath(filepath[1])
    file = filepath[2]
    # Read the header
    header = read_bdf_header(fid)

    if onlyHeader
        return header
    else
        data = read_bdf_data(fid, header, addOffset, numPrecision, chanSelect, chanIgnore, timeSelect, readStatus, digital)
        return BDF(header, data, path, file)
    end
end

function read_bdf_header(fid::IO)
    idCodeNonASCII =    Int32(read(fid, UInt8))
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

# Helper functions for decoding string and numerical entries
decodeString(fid, size) = ascii(String(read!(fid, Array{UInt8}(undef, size))))
decodeNumber(fid, size) = parse(Int32, ascii(String(read!(fid, Array{UInt8}(undef, size)))))

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
    arr = Array{Float32}(undef, nChannels)
    buf = read(fid, nChannels*size)
    for i=1:nChannels
        @inbounds arr[i] = parse(Int, ascii(String(buf[(size*(i-1)+1):(size*i)])))
    end
    return arr
end

# Read the EEG data points to a preallocated array.
function read_bdf_data(fid::IO, header::BDFHeader, addOffset, numPrecision, chanSelect, chanIgnore, timeSelect, readStatus, digital)
    nChannels = header.nChannels
    srate = Int32(header.nSampRec[1] / header.recordDuration)
    scaleFactor = numPrecision.(header.physMax-header.physMin)./(header.digMax-header.digMin)

    #=
    Addition of offset value to data points seems to be a legacy from reading EDF files that
    have physical or digital values not distributed symetrically around zero. Biosemi system
    is symetrical, so adding the offset has no real impact and can be skipped. See here:
    http://www.biosemi.nl/forum/viewtopic.php?f=4&t=1520&sid=ba7f775f06adbaa165230fdf1ad55c1c

    However, for compatibility with other EEG software, adding offset is the default.
    It can be switched off through setting the parameter offset=false.
    =#
    if addOffset
        offset = Float32.(header.physMin .- (header.digMin .* scaleFactor))
    else
        offset = Int32.(header.physMin .* 0)
    end
    
    # Limiting the number of channels and records to a requested subset.
    records = pick_records(timeSelect, header)
    chans = pick_channels(chanSelect, header)
    chans = setdiff(chans, pick_channels(chanIgnore, header))
    if readStatus chans = check_status(chans, header) end

    update_header!(header, chans)

    raw = Mmap.mmap(fid);
    if digital
        numPrecision = changeToInt(numPrecision)
    end
    data = Array{numPrecision}(undef, (srate*length(records),length(chans)));
    convert_data!(raw, data, srate, records, chans, nChannels, scaleFactor, offset)
    finalize(raw)
    GC.gc(false)
    return data
end

# Picking the time interval to load, measured as number of records or seconds.
function pick_records(records::Symbol, header)
    if records == :All
        return 1:header.nDataRecords
    else
        error("Unknown symbol :$records passed. Did You mean :All?")
    end
end

function pick_records(records::Integer, header)
    if 0 < records < header.nDataRecords
        return records
    else
        error("Number of a record to read should be between 1 and $(header.nDataRecords). Got $records instead.")
    end
end

function pick_records(records::Tuple{AbstractFloat, AbstractFloat}, header)
    dur =  header.recordDuration
    signalTime = header.nDataRecords * dur
    if 0 <= records[1] && records[2] <= signalTime
        return Int64(floor(records[1]/dur)+1):Int64(ceil(records[2]/dur))
    else
        error("Time range $records does not fit the available length of the data: $signalTime")
    end
end

function pick_records(records::UnitRange{}, header)
    if records[1] >= 1 && records[end] <= header.nDataRecords
        return records
    else
        error("Range $records does not fit in the available $(header.nDataRecords) records.")
    end
end

function pick_records(records::Any, header)
    error("Selection of time interval \"$records\" should be a number, a range, or a list of indices.")
end

# Picking the channels to load trough indices, ranges, or labels from the header.
function pick_channels(channels::Integer, header)
    if channels in 1:header.nChannels
        return channels
    else
        error("No channel number $channel available. File contains only $(header.nChannels) channels.")
    end
end

function pick_channels(channels::UnitRange{}, header)
    if channels[1] >= 1 && channels[end] <= header.nChannels
        return channels
    else
        error("Range $channels does not fit in the available $(header.nChannels) channels.")
    end
end

function pick_channels(channels::Union{String, Regex}, header)
    picks = header.chanLabels[occursin.(channels, header.chanLabels)]
    if isempty(picks)
        error("No requested channel found in the data.")
    end
    return indexin(picks, header.chanLabels)
end

function pick_channels(channels::Vector{String}, header)
    absent = (channels[channels .∉ [header.chanLabels]])
    present = (channels[channels .∈ [header.chanLabels]])
    picks = indexin(present, header.chanLabels)
    if isempty(present)
        error("No channel from the list found in the file.")
    elseif !isempty(absent)
        @warn "Selected channels $absent not found in file. 
        Read only channels $present."
    end
    return picks
end

function pick_channels(channels::Symbol, header)
    if channels == :All
        return 1:header.nChannels
    elseif channels == :None
        return Int64[]
    else
        error("Unrecogniezed symbol $channels. Did you mean :All?")
    end
end

function pick_channels(channels::Any, header)
    error("Selection of channels \"$channels\" should be an integer, a range, or a list of channels.")
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

function update_header!(header::BDFHeader, chans)
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

function changeToInt(::Type{Float64})
    return Int64
end

function changeToInt(::Type{Float32})
    return Int32
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