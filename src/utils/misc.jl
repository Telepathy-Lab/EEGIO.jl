# Decide which file access method to use
function read_method(fid::IO, method, type, shape)
    if method == :Direct
        return fid
    elseif method == :Mmap
        return Mmap.mmap(fid, type, shape)
    else
        error("Selected read method '$method' is not recognized. Only valid options are :Direct and :Mmap.")
    end
end

# Helper functions for decoding string and numerical header entries
decodeString(fid, size) = strip(ascii(String(read!(fid, Array{UInt8}(undef, size)))))
decodeNumber(fid, numType, size) = parse(numType, ascii(String(read!(fid, Array{UInt8}(undef, size)))))

# Helper function to decode channel specific string entries
function decodeChanStrings(fid, nChannels, size)
    arr = Array{String}(undef, nChannels)
    buf = read(fid, nChannels*size)
    for i=eachindex(arr)
        arr[i] = strip(ascii(String(buf[(size*(i-1)+1):(size*i)])))
    end
    return arr
end

# Helper function to decode channel specific numerical entries
function decodeChanNumbers(fid, numType, nChannels, size)
    arr = Array{numType}(undef, nChannels)
    buf = read(fid, nChannels*size)
    for i=eachindex(arr)
        arr[i] = parse(numType, ascii(String(buf[(size*(i-1)+1):(size*i)])))
    end
    return arr
end

# Calculate scaling and offsets for EDF/BDF data while checking if including them makes sense.
function resolve_offsets(header, addOffset, numPrecision)
    if addOffset & (numPrecision <: Integer)
        @warn "Reading data as integers is not compatible with scaling and offset correction,
         so it will be omitted. To get corrected data, use floating point output, e.g. NumPrecision=Float64.
         To hide this warning include addOffest=false in the read call. $(time_ns())"

        addOffset = false
    end

    if addOffset
        scaleFactors = numPrecision.(header.physMax-header.physMin)./(header.digMax-header.digMin)
        offsets = get_offsets(header, numPrecision, scaleFactors)
    else
        scaleFactors = ones(numPrecision, header.nChannels)
        offsets = numPrecision.(header.physMin .* 0)
    end

    return scaleFactors, offsets
end

function get_offsets(header, numPrecision::Type{ <: AbstractFloat}, scaleFactors)
    return numPrecision.(header.physMin .- (header.digMin .* scaleFactors))
end

function get_offsets(header, numPrecision::Type{ <: Integer}, scaleFactors)
    return round.(numPrecision, header.physMin .- (header.digMin .* scaleFactors))
end