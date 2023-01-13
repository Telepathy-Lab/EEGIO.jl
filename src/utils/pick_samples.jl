# Each format has dedicated functions since they store data and metadata in different ways.
function pick_samples(records::Any, header)
    error("Selection of time interval \"$records\" should be a number, a range, or a list of indices.")
end
 
# BDF selection
# Picking the time interval to load, measured as number of records or seconds.
function pick_samples(records::Symbol, header::BDFHeader)
    if records == :All
        return 1:header.nDataRecords
    else
        error("Unknown symbol :$records passed. Did You mean :All?")
    end
end

function pick_samples(records::Integer, header::BDFHeader)
    if 0 < records < header.nDataRecords
        return records
    else
        error("Number of a record to read should be between 1 and $(header.nDataRecords). Got $records instead.")
    end
end

function pick_samples(records::UnitRange, header::BDFHeader)
    if records[1] >= 1 && records[end] <= header.nDataRecords
        return records
    else
        error("Range $records does not fit in the available $(header.nDataRecords) records.")
    end
end

function pick_samples(records::Tuple{AbstractFloat, AbstractFloat}, header::BDFHeader)
    dur =  header.recordDuration
    signalTime = header.nDataRecords * dur
    if 0 <= records[1] && records[2] <= signalTime
        return Int64(floor(records[1]/dur)):Int64(ceil(records[2]/dur))
    else
        error("Time range $records does not fit the available length of the data: $signalTime")
    end
end

# EEG selection
function pick_samples(records::Symbol, nDataSamples::Int, header::EEGHeader)
    if records == :All
        return 1:nDataSamples
    else
        error("Unknown symbol :$records passed. Did You mean :All?")
    end
end

function pick_samples(sample::Integer, nDataSamples::Int, header::EEGHeader)
    if 0 < sample < nDataSamples
        return sample
    else
        error("Number of a record to read should be between 1 and $nDataSamples. Got $sample instead.")
    end
end

function pick_samples(samples::UnitRange, nDataSamples::Int, header::EEGHeader)
    if samples[1] >= 1 && samples[end] <= nDataSamples
        return samples
    else
        error("Range $samples does not fit in the available $nDataSamples records.")
    end
end

function pick_samples(times::Tuple{AbstractFloat, AbstractFloat}, nDataSamples::Int, header::EEGHeader)
    srate = 1_000_000 ÷ header.common["SamplingInterval"]
    signalTime = nDataSamples / srate

    if 0 <= times[1] && times[2] <= signalTime
        return Int((times[1]-1)*srate+1):Int(times[2]*srate)
    else
        error("Time range $times does not fit the available length of the data: $signalTime")
    end
end