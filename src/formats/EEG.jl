"""
    EEGHeader(common::Dict, binary::Type, channels::Dict, coords::Dict, comments::Vector{String})

Struct for storing EEG header information.
Follows closely the structure of .vhdr files, reading all the data recognizable from the
section names and keywords. Each section is stored as a dictionary, please refer to the
official BrainVision documentation or the constructor function for more details on the
necessary and optional information required.
"""
mutable struct EEGHeader <: Header
    common::Dict
    binary::Type
    channels::Dict
    coords::Dict
    comments::Vector{String}
end

"""
    EEGMarkers(number::Vector{Int}, type::Vector{String}, description::Vector{String}, 
        position::Vector{Int}, duration::Vector{Int}, chanNum::Vector{Int}, date::String)

Struct for storing EEG marker information. Follows closely the structure of .vmrk files,
reading all the data recognizable from the section names and keywords. Each section is
stored as a dictionary, please refer to the official BrainVision documentation or the
constructor function for more details on the necessary and optional information required.
"""
mutable struct EEGMarkers
    number::Vector{Int}
    type::Vector{String}
    description::Vector{String}
    position::Vector{Int}
    duration::Vector{Int}
    chanNum::Vector{Int}
    date::String
end

"""
    EEG(header::EEGHeader, markers::EEGMarkers, data::Matrix, path::String, file::String)

Struct for storing data from EEG files. Includes a header (with information from .vhdr file),
markers (with information from .vmrk file), and the data matrix (from .eeg file).
You can use it to manually construct a vaild EEG file that can be saved using the `write_eeg`.
See constructor function for a more convenient way of creating an EEG struct with only the
necessary information. Constructor also provides rudimentary validation of provided data
before writing to file.
"""
mutable struct EEG <: EEGData
    header::EEGHeader
    markers::EEGMarkers
    data::Matrix
    path::String
    file::String
end

"""
    EEGHeader(sInterval::Integer, nChannels::Integer, binaryFormat::Type; kwargs...)

Convencience constructor for EEGHeader struct. Allows for easy creation of a valid EEGHeader
struct with only the necessary information. All the optional arguments are stored as
dictionaries, so you can use them to add additional information to the header. Please note
that the more information you add, the more likely it is that the header will be compatible
with other software.

##### Arguments
* `sInterval::Integer`: Sampling interval in microseconds 
    (e.g. sampling rate of 100Hz is equal to sampling interval of 10_000).
* `nChannels::Integer`: Number of channels in the data.
* `binaryFormat::Type`: Type of the signal data (either Int16 or Float32).

##### Keyword arguments
* `filename::String`: Name of the data file (without extension).
* `chanNames::Vector{String}`: Channel names.
* `chanRefs::Vector{String}`: Indicates the reference for each channel, empty defaults are 
    interpreted as average reference.
* `chanRes::Vector{Float64}`: Resolution (gain) of each channel, defaults to 1.
* `chanUnits::Vector{String}`: Units for each channel, defaults to "µV".
* `coordRadius::Vector{Float64}`: Radius of each channel in spherical coordinates.
* `coordTheta::Vector{Float64}`: Theta angle of each channel in spherical coordinates.
* `coordPhi::Vector{Float64}`: Phi angle of each channel in spherical coordinates.
* `comments::Vector{String}`: Additional comments. Each element of the vector will be
    written as a separate comment line.

##### Returns
* `EEGHeader`: EEGHeader struct with all the provided information.

##### Examples
```julia
header = EEGHeader(10_000, 3, Int16; filename="test", chanNames=["C1", "C2", "C3"])
```
"""
function EEGHeader(sInterval::Integer, nChannels::Integer, binaryFormat::Type; 
    filename="", chanNames="", chanRefs="", chanRes="", chanUnits="", 
    coordRadius="", coordTheta="", coordPhi="", comments="")
    
    common = Dict(
        "Codepage" => "UTF-8",
        "DataFile" => "$filename.eeg",
        "MarkerFile" => "$filename.vmrk",
        "DataFormat" => "BINARY",
        "DataOrientation" => "MULTIPLEXED",
        "DataType" => "TIMEDOMAIN",
        "NumberOfChannels" => nChannels,
        "SamplingInterval" => sInterval,
    )

    if binaryFormat <: Integer
        binary = Int16
    elseif binaryFormat <: AbstractFloat
        binary = Float32
    else
        error("Binary format must be either an Integer or an AbstractFloat")
    end

    channels = Dict(
        "name" => channel_data(nChannels, chanNames, "names", map(x->"Ch$x",1:nChannels)),
        "number" => collect(1:nChannels),
        "reference" => channel_data(nChannels, chanRefs, "references", ""),
        "resolution" => channel_data(nChannels, chanRes, "resolutions", 1),
        "unit" => channel_data(nChannels, chanUnits, "units", "µV"),
    )

    coords = Dict(
        "number" => collect(1:nChannels),
        "radius" => channel_data(nChannels, coordRadius, "radii", ""),
        "theta" => channel_data(nChannels, coordTheta, "theta", ""),
        "phi" => channel_data(nChannels, coordPhi, "phi", ""),
    )

    if comments == ""
        comments = String[]
    end

    return EEGHeader(common, binary, channels, coords, comments)
end

# Check if number of elements in channel-related vectors matches number of channels.
function channel_data(nChannels::Integer, values, property, default)
    if values==""
        if length(default) == nChannels
            return default
        else
            return fill(default, nChannels)
        end
    elseif length(values) == nChannels
        return values
    else
        error("The number of $property elements must be equal to the number of channels.
        Expected $nChannels elements, got $(length(values)).")
    end
end

"""
    EEGMarkers(; kwargs...)

Convencience constructor for EEGMarkers struct. A call with no arguments will create default
marker object with only element named "New Segment". Providing optional arguments requires
all of them to be the same length. From the usability perspective, only the `position` needs
to be provided (and `type` if you want to record more than one type of event).

##### Keyword arguments
* `type::Vector{String}`: Type of each marker (e.g. "Stimulus" or "Response").
* `description::Vector{String}`: Description of each marker (e.g. IDs of stimuli).
* `position::Vector{String}`: Position of each marker in samples, defaults to 1.
* `duration::Vector{String}`: Duration of each marker in samples, defaults to 0.
* `chanNum::Vector{String}`: Channel number to which marker is applicable, defaults to 0 (all).
* `date::String`: Date of the recording (placed only at the first marker).

##### Returns
* `EEGMarkers`: EEGMarkers struct with all the provided information.

##### Examples
```julia
markers = EEGMarkers(type=["New Segment", "Stimulus"], description=["", "S  1"],
    position=[1, 1000], duration=[1, 0], chanNum=[1, 1])
```
"""
function EEGMarkers(; type="", description="", position="", duration="", chanNum="", date="")
    # Create a default EEGMarkers struct with obligatory `New Segment` marker.
    markers = EEGMarkers([1], ["New Segment"], [""], [1], [1], [0], date)

    # Add additional markers if provided.
    if length(type) > 0
        push!(markers["number"], collect(2:length(type)+1))
        push!(markers["type"], marker_data(length(type), type, "types", "Event"))
        push!(markers["description"], marker_data(length(type), description, "descriptions", ""))
        push!(markers["position"], marker_data(length(type), position, "positions", 1))
        push!(markers["duration"], marker_data(length(type), duration, "durations", 0))
        push!(markers["chanNum"], marker_data(length(type), chanNum, "channel number", 0))
    end
    return markers
end

function marker_data(nMarkers::Integer, values, property, default)
    if values==""
        return fill(default, nMarkers)
    elseif length(values)==1
        return fill(values, nMarkers)
    elseif length(values) == nMarkers
        return values
    else
        error("The number of $property elements must be equal to the number of markers.
        Expected $nMarkers elements, got $(length(values)).")
    end
end

"""
    EEG(data::Array, sInterval::Integer; path="", filename="", kwargs...)

Convencience constructor for EEG struct. For minimal example, only the 2D data array
and sampling interval are required. The data array must be a matrix of Integers or Floats.
All other arguments are optional and can be provided as keyword arguments that will be passed
down to header and marker objects constructors. Please refer to their documentation for more
information. If You have more than just the data array, it might be more convenient to create
the header and marker objects manually and pass them to the proper constructor directly.

##### Arguments
* `data::Array`: 2D data array, must be a matrix of Integers or Floats.
* `sInterval::Integer`: Sampling interval in microseconds.
        (e.g. sampling rate of 100Hz is equal to sampling interval of 10_000).

##### Keyword arguments
* `path::String`: Path to the file to be created.
* `filename::String`: Name of the file to be created.
* `kwargs...`: Keyword arguments passed down to header and marker objects constructors.

##### Returns
* `EEG`: EEG struct with all the provided information.

##### Examples
```julia
# Create a minimal EEG struct with 10s of 1000Hz sampled signal from 20 electrodes.
eeg = EEG(rand(10_000, 20), 1000)
```

```julia
# Create an EEG struct with 70s of 2000Hz sampled signal from 5 named electrodes.
eeg = EEG(rand(140_000, 5), 2000, chanNames=["Fp1", "Fp2", "F3", "F4", "Cz"])
```
"""
function EEG(data::Array, sInterval::Integer; path="", filename="", kwargs...)
    # Check if data is 2D
    dataSize = size(data)
    if length(dataSize) != 2
        error("Data must be a 2D matrix.")
    end

    # Check if data is a matrix of Integers or Floats
    if typeof(data[1,1]) <: Integer
        binaryFormat = Int16
        if maximum(data) > 32767 || minimum(data) < -32768
            error("Data must be convertable to a matrix of Int16: between -32768 and 32767.")
        end
    elseif typeof(data[1,1]) <: AbstractFloat
        binaryFormat = Float32
    else
        error("Data must be a matrix of Integers or Floats.")
    end

    # Create EEGHeader
    header = EEGHeader(sInterval, dataSize[2], binaryFormat, kwargs...)
    if filename == ""
        header.common["DataFile"] = filename
        header.common["MarkerFile"] = filename
    end

    # Create EEGMarkers
    markers = EEGMarkers(kwargs...)

    # Create EEG
    return EEG(header, markers, data, path, filename)
end

Base.show(io::IO, eeg::EEGHeader) = print(io, "EEG Header")
Base.show(io::IO, eeg::EEGMarkers) = print(io, "EEG Markers")

Base.show(io::IO, eeg::EEG) = print(io,
    """
    EEG File ($(eeg.file))
        Channels:       $(eeg.header.common["NumberOfChannels"]) $(eeg.header.channels["name"][1:5])...
        Sampling rate:  $(1_000_000/eeg.header.common["SamplingInterval"]) Hz
        Length:         $(size(eeg.data, 1)/(1_000_000/eeg.header.common["SamplingInterval"])) seconds
        Markers:        $(length(eeg.markers.description)) \
        $(length(eeg.markers.description)>5 ? eeg.markers.description[1:5] : eeg.markers.description[:])...
        Size in MB:     $(round(sizeof(eeg.data)/1_000_000, digits=2))
    """
)

Base.show(io::IO, ::Type{EEG}) = print(io, "EEG")