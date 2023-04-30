"""
    EEGIO.pick_channels(header::Header, channels)

Internal function used to properly select requested subset of channels from the data.
It allows users to narrow down the number of read channels through numerical indexes,
or name labels picked directly with a list or matched with regex expression.

Always returns a vector of indices corresponding to the picked channels.

## Examples

```julia
# Assume we have an object `raw` of type BDF with 10 channels.

# Picking the first channel of the data.
pick_channels(raw.header, 1)
```
```julia
# Picking the first 5 channels of the data.
pick_channels(raw.header, 1:5)
```
```julia
# Picking channels Fp1, Fp2, F7, F3, and Fz.
pick_channels(raw.header, ["Fp1", "Fp2", "F7", "F3", "Fz"])
```
```julia
# Picking all channels that contain the letter "F".
pick_channels(raw.header, r"F")
```

"""
function pick_channels(header::Header, channels::Any)
    error("Selection of channels \"$channels\" should be an integer, a range,
    a vector of channel names, or a regex expression.")
end

# Picking the channel for which an indice was passed.
function pick_channels(header::Header, channel::Integer)
    nChannels, chanLabels = channel_info(header)
    if channel in 1:nChannels
        return channel
    else
        error("No channel number $channel available. File contains only $nChannels channels.")
    end
end

# Picking all the channels which indices are included in the range.
function pick_channels(header::Header, channels::UnitRange)
    nChannels, chanLabels = channel_info(header)
    if channels[1] >= 1 && channels[end] <= nChannels
        return channels
    else
        error("Range $channels does not fit in the available $nChannels channels.")
    end
end

# Picking all channels that match the provided string or regex expression.
function pick_channels(header::Header, channels::Union{String, Regex})
    nChannels, chanLabels = channel_info(header)
    picks = chanLabels[occursin.(channels, chanLabels)]
    if isempty(picks)
        error("No requested channel found in the data.")
    end
    return indexin(picks, chanLabels)
end

# Picking all channels from the provided vector that exist in the data.
# Warning is thrown if vector contains names that are absent in the data.
function pick_channels(header::Header, channels::Vector{String})
    nChannels, chanLabels = channel_info(header)
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
function pick_channels(header::Header, channels::Symbol)
    nChannels, chanLabels = channel_info(header)
    if channels == :All
        return 1:nChannels
    elseif channels == :None
        return Int64[]
    else
        error("Unrecogniezed symbol $channels. Did you mean :All?")
    end
end

channel_info(header::BDFHeader) = header.nChannels, header.chanLabels
channel_info(header::EEGHeader) = header.common["NumberOfChannels"], header.channels["name"]