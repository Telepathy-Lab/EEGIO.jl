# Convenince functions for resizing the data (limiting the timespan or channel number).
# Contains also function to adequately update metadata.
# These functions are also sed in the main read functions.

# Functions to update BDF header.
function update_header(header::BEDFHeader, change)
    newHeader = deepcopy(header)
    update_header!(newHeader, change)
    return newHeader
end

function update_header!(header::BEDFHeader, records::UnitRange)
    header.nDataRecords = length(records)
end

function update_header!(header::BEDFHeader, chans::Vector)
    header.nBytes = (length(chans)+1)*256
    header.nChannels = length(chans)

    for hfield in fieldnames(typeof(header))
        if typeof(getfield(header, hfield)) <: AbstractVector
            setfield!(header, hfield, getfield(header, hfield)[chans])
        end
    end
end

# Functions to update EEG header.
function update_header(header::EEGHeader, chans::Vector)
    newHeader = deepcopy(header)
    update_header!(newHeader, chans)
    return newHeader
end

function update_header!(header::EEGHeader, chans)
    header.common["NumberOfChannels"] = length(chans)

    # Update channel specification count
    for (key, val) in header.channels
        header.channels[key] = val[chans]
    end 

    # Update electrode coordinate count
    for (key, val) in header.coords
        header.coords[key] = val[chans]
    end
end

# Functions to update EEG markers.
function update_markers(markers::EEGMarkers, samples)
    newMarkers = deepcopy(markers)
    update_markers!(newMarkers, samples)
    return newMarkers
end

function update_markers!(markers::EEGMarkers, samples)
    pos = markers.position

    # Leave only markers that occur in the selected time window
    if !isempty(pos)
        mask = samples[1] .<= pos .<= samples[end]
        markers = EEGMarkers(
            markers.number[mask],
            markers.type[mask],
            markers.description[mask],
            markers.position[mask],
            markers.duration[mask],
            markers.chanNum[mask],
            markers.date,
        )
    end
end

# Functions to update SET header
function update_header!(header::SETHeader, chans::Vector)
    header.nbchan = length(chans)
    # Transfer channel data to urchanlocs if it is empty
    if isempty(header.urchanlocs)
        for prop in propertynames(header.chanlocs)
            header.urchanlocs[string(prop)] = getproperty(header.chanlocs, prop)
        end
    end

    # Leave only the data for those channels that are actually being read
    for prop in propertynames(header.chanlocs)
        if !isempty(getproperty(header.chanlocs, prop))
            setproperty!(header.chanlocs, prop, getproperty(header.chanlocs, prop)[chans])
        end
    end

    # Store channel IDs so they can be referred back to urchans (if they are not already there)
    if isempty(header.chanlocs.urchan) || all(isnothing.(header.chanlocs.urchan))
        header.chanlocs.urchan = chans
    end
end

function update_header!(header::SETHeader, samples::UnitRange)
    header.pnts = length(samples)

    if !isempty(header.event)
        # Transfer event data to urevent if it is empty
        if isempty(header.urevent)
            for prop in keys(header.event)
                header.urevent[prop] = header.event[prop]
            end
        end

        # Leave only the data for those events that are actually being read
        mask = first(samples) .<= header.event["latency"] .<= last(samples)
        for prop in keys(header.event)
            if !isempty(header.event[prop])
                header.event[prop] = header.event[prop][mask]
            end
        end
    end
end

"""
    crop(file::EEGData, timeSelect)

Allows for cropping the data to a specified time window. `timeSelect` can be either an Integer, 
a UnitRange, or a tuple of Floats. Depending on the format, the time window will be measured
in different units. Since this keyword argument works exactly the same as in read functions,
please refer to their documentation for more details on specific use cases.
Returns a new EEGData object with the cropped data.

## Examples
```julia
# Cropping the data to the first 10 seconds of the file.
data = crop(file, (1.,10.))
```
```julia
# Cropping the data to the first 10 samples/records of the file.
data = crop(file, 1:10)
```
"""
function crop(file::EEGData)
    error("No parameters given to crop the $(file.file) datafile.")
end

# Cropping based on time of the recording in seconds.
function crop(bdf::BDF, timeSelect)
    range = pick_samples(bdf.header, timeSelect)
    header = update_header(bdf.header, range)

    sRate = bdf.header.nSampRec[1]
    start = (range[1]-1) * sRate * bdf.header.recordDuration + 1
    finish = range[end] * sRate * bdf.header.recordDuration

    return BDF(header, bdf.data[start:finish, :], bdf.file, bdf.path)
end

function crop(eeg::EEG, timeSelect)
    range = pick_samples(eeg.header, timeSelect, size(eeg.data,1))
    markers = update_markers(eeg.markers, range)

    return EEG(eeg.header, markers, eeg.data[range, :], eeg.file, eeg.path)
end

"""
    crop!(file::EEGData, timeSelect)

Performs cropping in place. See [`crop`](@ref) for more details. 
"""
function crop!(bdf::BDF, timeSelect)
    range = pick_samples(bdf.header, timeSelect)
    update_header!(bdf.header, range)

    sRate = bdf.header.nSampRec[1]
    start = (range[1]-1) * sRate * bdf.header.recordDuration + 1
    finish = range[end] * sRate * bdf.header.recordDuration

    bdf.data = bdf.data[start:finish, :]
end

function crop!(eeg::EEG, timeSelect)
    range = pick_samples(eeg.header, timeSelect, size(eeg.data,1))
    update_markers!(eeg.markers, range)

    eeg.data = eeg.data[range, :]
end


"""
    select(file::EEGData, chanSelect)

Allows for selecting a subset of channels from the original data. `chanSelect` can be either
an Integer, a UnitRange, a Vector of Integers/Strings, or a regular expression. Behaves exactly
the same as in read functions.
Returns a new EEGData object with only the selected channels.

## Examples
```julia
# Selecting the first 10 channels from the file.
data = select(file, 1:10)
```
```julia
# Selecting channels 1, 3, 5, and 7 from the file.
data = select(file, [1,3,5,7])
```
```julia
# Selecting only frontal channels (labels containing the letter "F") from the file.
data = select(file, r"F")
```
"""
function select(file::EEGData)
    error("No channels selected from the $(file.file) datafile.")
end

# Selecting a subset of channels from the original data.
function select(bdf::BDF, channels)
    newChannels = pick_channels(bdf.header, channels)
    newHeader = update_header(bdf.header, newChannels)
    newData = bdf.data[:, newChannels]
    return BDF(newHeader, newData, bdf.path, bdf.file)
end

function select(eeg::EEG, channels)
    newChannels = pick_channels(eeg.header, channels)
    newHeader = update_header(eeg.header, newChannels)
    newData = eeg.data[:, newChannels]
    return EEG(newHeader, eeg.markers, newData, eeg.path, eeg.file)
end

"""
    select!(file::EEGData, chanSelect)

Performs channel selection in place. See [`select`](@ref) for more details.
"""
function select!(bdf::BDF, channels)
    newChannels = pick_channels(bdf.header, channels)
    update_header!(bdf.header, newChannels)
    bdf.data = bdf.data[:, newChannels]
end

function select!(eeg::EEG, channels)
    newChannels = pick_channels(bdf.header, channels)
    update_header!(eeg.header, newChannels)
    eeg.data = eeg.data[:, newChannels]
end


"""
    split(file::EEGData, timepoint)

Allows for splitting the data into two objects at a specified timepoint. `timepoint` can be
either a Float or an Integer. Depending on the format, the timepoint will be measured in
different units. To preserve the structure of the underlying format, e.g. BDF files will be
split based on the record duration.
Returns two new EEGData objects with the split data.

## Examples
```julia
# Splitting the data at the 10th second of the file.
data1, data2 = split(file, 10.)
```
```julia
# Splitting the data at the 100th sample/record of the file.
data1, data2 = split(file, 100)
```
"""
function Base.split(file::EEGData)
    error("To split the data a timepoint or sample number is needed.")
end

function Base.split(bdf::BDF, timepoint::AbstractFloat)
    dataLength = bdf.header.recordDuration*bdf.header.nDataRecords
    return crop(bdf, (1., timepoint)), crop(bdf, (timepoint+1, Float64(dataLength)))
end

function Base.split(bdf::BDF, timepoint::Integer)
    return crop(bdf, 1:timepoint), crop(bdf, timepoint+1:bdf.header.nDataRecords)
end

function Base.split(eeg::EEG, timepoint::AbstractFloat)
    sRate = 1_000_000 / eeg.header.common["SamplingInterval"]
    dataLength = size(eeg.data,1) / sRate
    return crop(eeg, (1., timepoint)), crop(eeg, (timepoint+1, Float64(dataLength)))
end

function Base.split(eeg::EEG, timepoint::Integer)
    return crop(eeg, 1:timepoint), crop(eeg, timepoint+1:size(eeg.data,1))
end