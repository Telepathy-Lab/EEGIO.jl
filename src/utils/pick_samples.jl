"""
    EEGIO.pick_samples(records, header::BDFHeader)
    EEGIO.pick_samples(samples, nDataSamples::Ineger, header::EEGHeader)

Internal function used to properly pick the range of samples that should be read from every
channel. Since data is stored differently in each format, specialized variants were written
to read as much data as needed to satify the query without compromising efficiency.
Please refer to the description of `timeSelect` keyword argument of particular read function
for more detailed account of the picking behaviour.

Always returns a UnitRange.

## Examples

```julia
# Picking the first 10 records of the data (assuming `file` is an object of type BDF).
pick_samples(1:10, file.header)
```
```julia
# Picking the first 10 seconds of the data (assuming `file` is an object of type EEG).
pick_samples((1.,10.), size(file.data,1), file.header)
```
"""
function pick_samples(samples::Any, header)
    error("Selection of time interval \"$samples\" should be a number, a range, or a list of indices.")
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

# Integer interpreted as an index of a data record to be read.
function pick_samples(record::Integer, header::BDFHeader)
    if 0 < record < header.nDataRecords
        return record:record
    else
        error("Number of a record to read should be between 1 and $(header.nDataRecords). Got $record instead.")
    end
end

# Unitrange interpreted as an interval including records with such indexes.
function pick_samples(records::UnitRange, header::BDFHeader)
    if records[1] >= 1 && records[end] <= header.nDataRecords
        return records
    else
        error("Range $records does not fit in the available $(header.nDataRecords) records.")
    end
end

# Tuple of floats interpreted as seconds. Picking all records which parts are included
# in the given time interval. Therefore actual data might be slightly larger then the interval.
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
function pick_samples(records::Symbol, nDataSamples::Integer, header::EEGHeader)
    if records == :All
        return 1:nDataSamples
    else
        error("Unknown symbol :$records passed. Did You mean :All?")
    end
end

# Integer interpreted as a single sample.
function pick_samples(sample::Integer, nDataSamples::Integer, header::EEGHeader)
    if 0 < sample < nDataSamples
        return sample:sample
    else
        error("Number of a record to read should be between 1 and $nDataSamples. Got $sample instead.")
    end
end

# Unitrange interpreted as an interval of samples the should be read.
function pick_samples(samples::UnitRange, nDataSamples::Integer, header::EEGHeader)
    if samples[1] >= 1 && samples[end] <= nDataSamples
        return samples
    else
        error("Range $samples does not fit in the available $nDataSamples records.")
    end
end

# Tuple of floats interpreted as seconds. All samples fitting it will be read.
# This follows the Julia convention, where end of an interval is also included.
function pick_samples(times::Tuple{AbstractFloat, AbstractFloat}, nDataSamples::Integer, header::EEGHeader)
    sRate = 1_000_000 ÷ header.common["SamplingInterval"]
    signalTime = nDataSamples / sRate

    if 0 <= times[1] && times[2] <= signalTime
        return round(Int, (times[1]-1)*sRate+1):round(Int, times[2]*sRate)
    else
        error("Time range $times does not fit the available length of the data: $signalTime")
    end
end