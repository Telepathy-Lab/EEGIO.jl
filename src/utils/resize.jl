# TODO: Add versions for EEG files
# TODO: Add inplace versions
# TODO: Fix the docstrings

"""
    crop(file::EEGData)

Since data in BDF files is stored in `record` chunks, cropping it requires preserving
an integer number of records that contain the specified beginning and end of the selection.
Therefore when supplying those points in seconds, they are converted into sample numbers
and appropriate subset of data containg both points is chosen.
"""
function crop(file::EEGData)
    error("No parameters given to crop the $(file.file) datafile.")
end

# Cropping based on time of the recording in seconds
function crop(bdf::BDF, timepoint::AbstractFloat)
    crop(bdf, timepoint, timepoint)
end

function crop(bdf::BDF, range::StepRangeLen{})
    crop(bdf, range[1], range[end])
end

function crop(bdf::BDF, from::AbstractFloat, to::AbstractFloat)
    sRate = bdf.header.nSampRec[1]
    start = Int(round(sRate*(from-1) + 1))
    finish = Int(round(sRate*to))
    @info (start, finish)
    crop(bdf, start, finish)
end

# Cropping based on sample count
function crop(bdf::BDF, sample::Integer)
    crop(bdf, sample, sample)
end

function crop(bdf::BDF, range::UnitRange{})
    crop(bdf, range[1], range[end])
end

function crop(bdf::BDF, from::Integer, to::Integer)
    dSize = size(bdf.data)[1]
    sRate = bdf.header.nSampRec[1]
    record = sRate * bdf.header.recordDuration
    if !(0 < from <= dSize)
        error("Sample $from is not in the data.")
    elseif !(0 < to <= dSize)
        error("Sample $to is not in the data.")
    else
        start = (from÷record)*record + 1
        # Subtracting 1 to compensate for `to` being a multiple of record
        finish = ((to-1)÷record)*record + record

        newHeader = deepcopy(bdf.header)
        newHeader.nDataRecords = Int64(length(start:finish)/record)

        newData = bdf.data[start:finish,:]
        return BDF(newHeader, newData, bdf.path, bdf.file)
    end
end

# Selecting a subset of channels from the original data.
function select(file::EEGData)
    error("No channels selected from the $(file.file) datafile.")
end

# Uses functions from load_bdf file.
function select(bdf::BDF, channels)
    newChannels = pick_channels(channels, bdf.header)
    newHeader = deepcopy(bdf.header)
    update_header!(newHeader, newChannels)
    newData = bdf.data[:, newChannels]
    return BDF(newHeader, newData, bdf.path, bdf.file)
end

function Base.split(file::EEGData)
    error("To split the data a timepoint or sample number is needed.")
end

function Base.split(bdf::BDF, timepoint::AbstractFloat)
    dataLength = bdf.header.recordDuration*bdf.header.nDataRecords
    return crop(bdf, 1., timepoint), crop(bdf, timepoint+1, Float64(dataLength))
end

function Base.split(bdf::BDF, timepoint::Integer)
    return crop(bdf, 1, timepoint), crop(bdf, timepoint+1, size(bdf.data)[1])
end