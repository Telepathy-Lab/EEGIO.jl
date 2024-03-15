mutable struct BDFHeader <: Header
    idCodeNonASCII::Int
    idCode::String
    subID::String
    recID::String
    startDate::String
    startTime::String
    nBytes::Int
    versionDataFormat::String
    nDataRecords::Int
    recordDuration::Int
    nChannels::Int
    chanLabels::Vector{String}
    transducer::Vector{String}
    physDim::Vector{String}
    physMin::Vector{Int}
    physMax::Vector{Int}
    digMin::Vector{Int}
    digMax::Vector{Int}
    prefilt::Vector{String}
    nSampRec::Vector{Int}
    reserved::Vector{String}
end

 mutable struct BDFStatus{T<:Integer}
    low::Vector{T}
    high::Vector{T}
    status::Vector{T}
end

mutable struct BDF <: EEGData
    header::BDFHeader
    data::Array
    status::BDFStatus
    path::String
    file::String
end

"""
    BDFHeader(samples::Integer, channels::Integer, sRate::Integer; kwargs...)

Convenience constructor for the BDFHeader struct.
The only three necessary arguments is the number of samples in the data, the number of channels,
and the sampling rate of signals. Other fields are optional, but providing them might improve
compatibility with other software.

##### Arguments
* `samples::Integer`: Number of samples in the data.
* `channels::Integer`: Number of channels in the data.
* `sRate::Integer`: Sampling rate of the data.

##### Keyword arguments
* `subID::String`: Subject ID.
* `recID::String`: Recording ID.
* `startDate::String`: Date of the recording.
* `startTime::String`: Time of the recording.
* `recordDuration::Integer`: Duration of each data record in seconds.
* `chanLabels::Vector{String}`: Channel labels.
* `transducer::Vector{String}`: Transducer type, eg. 'active electrode'.
* `physDim::Vector{String}`: Physical dimension of the data, eg. 'uV'.
* `physMin::Vector{Int}`: Minimum physical value of the data.
* `physMax::Vector{Int}`: Maximum physical value of the data.
* `digMin::Vector{Int}`: Minimum digital value of the data.
* `digMax::Vector{Int}`: Maximum digital value of the data.
* `prefilt::Vector{String}`: Prefiltering of the data, eg. 'HP:0.1Hz LP:75Hz'.
* `reserved::Vector{String}`: Reserved fields (usually empty).

##### Returns
* `BDFHeader`: A BDFHeader struct with the provided values.

You might notice that couple of fields mentioned in the BDF specification are not included 
in the constructor. These either have a fixed value or are calculated from provided values
to reduce the risk of mistakes. If you want to change these values, you can overwrite the
fields of the returned struct directly or use the default constructor and fill all the fields
manually.
However, this constructor provides additional validation checks that might help you avoid
entering wrong values or getting the data distorted during conversion to Int24 while writing 
to disk.

##### Examples
```julia
header = BDFHeader(1024, 17, 256)
```
```julia
header = BDFHeader(1024, 17, 256, subID="Subject 1", recID="Recording 1", 
                    startDate="01.01.2019", startTime="00:00:00")
```
"""
function BDFHeader(samples::Integer, channels::Integer, sRate::Integer; 
                    subID="", recID="", startDate="", startTime="", recordDuration=1,
                    chanLabels="", transducer="", physDim="",
                    physMin="", physMax="", digMin="", digMax="",
                    prefilt="", reserved="")

    # Mandatory values for BDF files
    idCodeNonASCII = 255
    idCode = "BIOSEMI"
    versionDataFormat = "24BIT"

    # Assumes the number of channels is correct
    nBytes = 256 * (channels + 1)
    
    recordSize = (sRate * recordDuration)
    nDataRecords = samples / recordSize

    # Make sure samples are multiple of decalred record size
    if nDataRecords != round(Int, nDataRecords)
        error("Number of samples ($samples) does not split evenly into declared record size \
        ($recordSize = sRate:$sRate * recordDuration:$recordDuration).")
    end

    nChannels = channels
    # Check if number of channels matches number of elements in channel-related fields.
    # If labels are not provided, fill with empty strings.
    # Length of strings is validated in write_bdf function
    chanLabels = check_fields(nChannels, "channel labels", chanLabels)
    transducer = check_fields(nChannels, "transducer fields", transducer)
    physDim = check_fields(nChannels, "physical dimensions fields", physDim)
    prefilt = check_fields(nChannels, "prefiltering fields", prefilt)
    reserved = check_fields(nChannels, "reserved fields", reserved)

    # Check if Status channel is present and at the end of the list
    if "Status" ∉ chanLabels
        @warn "Status not found in the channel list. For compatibility with other software,
                 it is recommended to add it to the data as the last channel."
    elseif "Status" != chanLabels[end]
        @warn "Status is not the last channel. For compatibility with other software,
                 it is recommended to have it at the end."
    end

    # Check if number of channels matches number of elements in physical and digital
    # dimensions fields. If yes, promote them to Int64.
    # If not provided, fill with default values.
    physMin = check_dims(nChannels, "physical minimum fields", physMin, -262144)
    physMax = check_dims(nChannels, "physical maximum fields", physMax, 262143)
    digMin = check_dims(nChannels, "digital minimum fields", digMin, -8388608)
    digMax = check_dims(nChannels, "digital maximum fields", digMax, 8388607)
    nSampRec = check_dims(nChannels, "digital maximum fields", digMax, recordSize)
    
    return BDFHeader(idCodeNonASCII, idCode, subID, recID, startDate, startTime, 
    nBytes, versionDataFormat, nDataRecords, recordDuration, nChannels, chanLabels, 
    transducer, physDim, physMin, physMax, digMin, digMax, prefilt, nSampRec, reserved)
end


function BDFStatus(length::T) where T <: Integer
    low = Vector{UInt8}(undef, length)
    high = Vector{UInt8}(undef, length)
    status = Vector{UInt8}(undef, length)

    return BDFStatus(low, high, status)
end

Base.isempty(status::BDFStatus) = isempty(status.low)

# Check if number of elements in channel-related string fields matches number of channels.
function check_fields(nChannels::Integer, name, field)
    if field == ""
        return fill("", nChannels)
    elseif length(field) != nChannels
        error("Number of channels ($nChannels) does not match number of $name \
        ($(length(field))).")
    else
        return field
    end
end

# Checks if number of elements in channel-related integer fields matches number of channels.
function check_dims(nChannels::Integer, name, field, value)
    if typeof(field) == Int
        return fill(field, nChannels)
    elseif field == ""
        return fill(value, nChannels)
    elseif length(field) != nChannels
        error("Number of channels ($nChannels) does not match number of $name \
        ($(length(field))).")
    else
        return Int.(field)
    end
end

"""
    BDF(data::Array, sRate::Integer; path="", file="", kwargs...)

Covenience constructor for BDF struct.
To get a valid BDF struct, you need to provide the data and its sampling rate. All other
keyword arguments are optional and will be passed to the BDFHeader constructor. Although
optional, the more information you provide, the less likely you will face problems when
importing the data into other software.

##### Arguments
- `data::Array`: 2D matrix of data. Each row represents a sample and each column a channel.
- `sRate::Integer`: Sampling rate of the data in Hz.

##### Keyword arguments
- `path::String`: Path to the folder where the file will be saved. If not provided, you will
have to provide the full path when calling the `write_bdf` function.
- `file::String`: Name of the file. If not provided, you will have to provide in the path.
- `subID::String`: Subject ID.
- `recID::String`: Recording ID.
- `startDate::String`: Date of the recording.
- `startTime::String`: Time of the recording.
- `recordDuration::Integer`: Duration of each data record in seconds.
- `chanLabels::Vector{String}`: Channel labels.
- `transducer::Vector{String}`: Transducer type, eg. 'active electrode'.
- `physDim::Vector{String}`: Physical dimension of the data, eg. 'uV'.
- `physMin::Vector{Int}`: Minimum physical value of the data.
- `physMax::Vector{Int}`: Maximum physical value of the data.
- `digMin::Vector{Int}`: Minimum digital value of the data.
- `digMax::Vector{Int}`: Maximum digital value of the data.
- `prefilt::Vector{String}`: Prefiltering of the data, eg. 'HP:0.1Hz LP:75Hz'.
- `reserved::Vector{String}`: Reserved fields (usually empty).

##### Returns
- `BDF`: BDF struct.

Additionally, this constructor provides validation checks that might help you avoid mistakes
or getting the data distorted during conversion to Int24 while writing to disk.

##### Examples
```julia
# Create a BDF struct with 10s of random data and 20 channels sampled at 256Hz.
BDF(rand(2560, 20), 256)
```
If you already have a BDFHeader, you can use the default constructor:
```julia
BDF(header, data, path="path/to/file/", file="file.bdf")
```
"""
function BDF(data::Array, sRate::Integer; path="", file="", kwargs...)
    
    # Check if data is 2D
    dataSize = size(data)
    if length(dataSize) != 2
        error("Data must be a 2D matrix.")
    end
    samples, channels = dataSize

    header = BDFHeader(samples, channels, sRate, kwargs...)

    # Check if data (given physical/digital dimensions) will not overflow Int24.
    # Calculate the extrema for each channel.    
    outSpan = check_span(header, data)
    if !isempty(outSpan)
        @warn "Data will overflow Int24. Consider changing physical/digital dimensions 
        (in channels $(join(outSpan, ", "))).)"
    end

    outBounds = check_bounds(header, data)
    if !isempty(outBounds)
        @warn "Some data values will be significantly clipped during conversion to Int24 
        (in channels $(join(outBounds, ", ")))."
    end

    status = BDFStatus(0)
    return BDF(header, data, status, path, file)
end

# Find channels which data spans beyond 24 bits
function check_span(header::BDFHeader, data)
    gains = (header.physMax-header.physMin)./(header.digMax-header.digMin)
    mins = abs.(minimum(data.data, dims=1))[:]
    maxs = abs.(maximum(data.data, dims=1))[:]
    dataSpan = abs.(maxs .- mins) ./ gains
    return findall(x -> x > 2^23, dataSpan)
end

# Make an inexpensive check if data in the first record will be clipped by much.
# Too be sure we would need to check all records, but this should be a good estimate.
function check_bounds(header::BDFHeader, data)
    gains = (header.physMax-header.physMin)./(header.digMax-header.digMin)
    dataSample = data[1:header.recordDuration*header.sRate,:]
    dataSample = abs.(dataSample[header.recordDuration*header.sRate,:]) ./ gains'

    clipped = abs.((dataSample .- round(Int32, dataSample)) ./ dataSample)
    # The threshold is set to 5%, which feels like a reasonable value for start.
    return findall.(x -> x > 0.05, clipped)
end

Base.show(io::IO, bdf::BDFHeader) = print(io, "BDF Header")
Base.show(io::IO, bdf::BDFStatus) = print(io, "BDF Status data")
Base.show(io::IO, ::MIME"text/plain", ::Type{BDF}) = print(io, "BDF")

function Base.show(io::IO, m::MIME"text/plain", bdf::BDF) 
    onlyHeader = isempty(bdf.data) ? "only header data, " : ""
    readStatus = isempty(bdf.status) ? "" : " + Status"
    print(io, 
    "BDF file ($(onlyHeader)$(bdf.header.nChannels) channels$readStatus, \
    duration: $(round(bdf.header.nDataRecords/60,digits=2)) min.)")
end
