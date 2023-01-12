# Picking the channels to load trough indices, ranges, or labels from the header.
function pick_channels(channel::Integer, nChannels::Integer, chanLabels::Vector{String})
    if channel in 1:nChannels
        return channel
    else
        error("No channel number $channel available. File contains only $nChannels channels.")
    end
end

function pick_channels(channels::UnitRange{}, nChannels::Integer, chanLabels::Vector{String})
    if channels[1] >= 1 && channels[end] <= nChannels
        return channels
    else
        error("Range $channels does not fit in the available $nChannels channels.")
    end
end

function pick_channels(channels::Union{String, Regex}, nChannels::Integer, chanLabels::Vector{String})
    picks = chanLabels[occursin.(channels, chanLabels)]
    if isempty(picks)
        error("No requested channel found in the data.")
    end
    return indexin(picks, chanLabels)
end

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

function pick_channels(channels::Symbol, nChannels::Integer, chanLabels::Vector{String})
    if channels == :All
        return 1:nChannels
    elseif channels == :None
        return Int64[]
    else
        error("Unrecogniezed symbol $channels. Did you mean :All?")
    end
end

function pick_channels(channels::Any, nChannels::Integer, chanLabels::Vector{String})
    error("Selection of channels \"$channels\" should be an integer, a range, or a list of channels.")
end