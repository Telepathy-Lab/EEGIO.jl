"""
    EEGIO.pick_channels(channels, nChannels::Integer, chanLabels::Vector{String})

Internal function used to properly select requested subset of channels from the data.
It allows users to narrow down the number of read channels through numerical indexes,
or name labels picked directly with a list or matched with regex expression.

Always returns a vector of indices corresponding to the picked channels.

## Examples

```julia
# Assume we have an object `raw` of type BDF with 10 channels.

# Picking the first channel of the data.
pick_channels(1, raw.header.nChannels, raw.header.chanLabels)
```
```julia
# Picking the first 5 channels of the data.
pick_channels(1:5, raw.header.nChannels, raw.header.chanLabels)
```
```julia
# Picking channels Fp1, Fp2, F7, F3, and Fz.
pick_channels(["Fp1", "Fp2", "F7", "F3", "Fz"], raw.header.nChannels, raw.header.chanLabels)
```
```julia
# Picking all channels that contain the letter "F".
pick_channels(r"F", raw.header.nChannels, raw.header.chanLabels)
```

"""
function pick_channels(channels::Any, nChannels::Integer, chanLabels::Vector{String})
    error("Selection of channels \"$channels\" should be an integer, a range,
    a vector of channel names, or a regex expression.")
end

# Picking the channel for which an indice was passed.
function pick_channels(channel::Integer, nChannels::Integer, chanLabels::Vector{String})
    if channel in 1:nChannels
        return channel
    else
        error("No channel number $channel available. File contains only $nChannels channels.")
    end
end

# Picking all the channels which indices are included in the range.
function pick_channels(channels::UnitRange, nChannels::Integer, chanLabels::Vector{String})
    if channels[1] >= 1 && channels[end] <= nChannels
        return channels
    else
        error("Range $channels does not fit in the available $nChannels channels.")
    end
end

# Picking all channels that match the provided string or regex expression.
function pick_channels(channels::Union{String, Regex}, nChannels::Integer, chanLabels::Vector{String})
    picks = chanLabels[occursin.(channels, chanLabels)]
    if isempty(picks)
        error("No requested channel found in the data.")
    end
    return indexin(picks, chanLabels)
end

# Picking all channels from the provided vector that exist in the data.
# Warning is thrown if vector contains names that are absent in the data.
function pick_channels(channels::Vector{String}, nChannels::Integer, chanLabels::Vector{String})
    absent = (channels[channels .∉ [chanLabels]])
    present = (channels[channels .∈ [chanLabels]])
    picks = indexin(present, chanLabels)
    if isempty(present)
        error("No channel from the list found in the file.")
    elseif !isempty(absent)
        @warn "Selected channels $absent not found in file. 
        Read only channels $present."
    end
    return picks
end

# Picking all or none of the channels. Using symbols as shortcuts and useful defaults.
function pick_channels(channels::Symbol, nChannels::Integer, chanLabels::Vector{String})
    if channels == :All
        return 1:nChannels
    elseif channels == :None
        return Int64[]
    else
        error("Unrecogniezed symbol $channels. Did you mean :All?")
    end
end
