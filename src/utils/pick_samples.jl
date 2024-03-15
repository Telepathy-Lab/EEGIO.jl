"""
    EEGIO.pick_samples(header::BDFHeader, records)
    EEGIO.pick_samples(header::BDFHeader, samples, nDataSamples::Ineger)

Internal function used to properly pick the range of samples that should be read from every
channel. Since data is stored differently in each format, specialized variants were written
to read as much data as needed to satify the query without compromising efficiency.
Please refer to the description of `timeSelect` keyword argument of particular read function
for more detailed account of the picking behaviour.

Always returns a UnitRange.

## Examples

```julia
# Picking the first 10 records of the data (assuming `file` is an object of type BDF).
pick_samples(file.header, 1:10)
```
```julia
# Picking the first 10 seconds of the data (assuming `file` is an object of type EEG).
pick_samples(file.header, (1.,10.), size(file.data,1))
```
"""
function pick_samples(header, samples::Any)
    error("Selection of time interval \"$samples\" should be a number, a range, or a list of indices.")
end
 
# BDF and EDF selection
# Picking the time interval to load, measured as number of records or seconds.

function pick_samples(header::BEDFHeader, records::Symbol)
    if records == :All
        return 1:header.nDataRecords
    else
        error("Unknown symbol :$records passed. Did You mean :All?")
    end
end

# Integer interpreted as an index of a data record to be read.
function pick_samples(header::BEDFHeader, record::Integer)
    if 0 < record < header.nDataRecords
        return record:record
    else
        error("Number of a record to read should be between 1 and $(header.nDataRecords). Got $record instead.")
    end
end

# Unitrange interpreted as an interval including records with such indexes.
function pick_samples(header::BEDFHeader, records::UnitRange)
    if records[1] >= 1 && records[end] <= header.nDataRecords
        return records
    else
        error("Range $records does not fit in the available $(header.nDataRecords) records.")
    end
end

# Tuple of floats interpreted as seconds. Picking all records which parts are included
# in the given time interval. Therefore actual data might be slightly larger then the interval.
function pick_samples(header::BEDFHeader, records::Tuple{AbstractFloat, AbstractFloat})
    dur =  header.recordDuration
    signalTime = header.nDataRecords * dur
    if 0 <= records[1] && records[2] <= signalTime
        return Int64(floor(records[1]/dur))+1:Int64(ceil(records[2]/dur))
    else
        error("Time range $records does not fit the available length of the data: $signalTime")
    end
end

# EEG selection
function pick_samples(header::EEGHeader, records::Symbol, nDataSamples::Integer)
    if records == :All
        return 1:nDataSamples
    else
        error("Unknown symbol :$records passed. Did You mean :All?")
    end
end

# Integer interpreted as a single sample.
function pick_samples(header::EEGHeader, sample::Integer, nDataSamples::Integer)
    if 0 < sample < nDataSamples
        return sample:sample
    else
        error("Number of a record to read should be between 1 and $nDataSamples. Got $sample instead.")
    end
end

# Unitrange interpreted as an interval of samples the should be read.
function pick_samples(header::EEGHeader, samples::UnitRange, nDataSamples::Integer)
    if samples[1] >= 1 && samples[end] <= nDataSamples
        return samples
    else
        error("Range $samples does not fit in the available $nDataSamples records.")
    end
end

# Tuple of floats interpreted as seconds. All samples fitting it will be read.
# This follows the Julia convention, where end of an interval is also included.
function pick_samples(header::EEGHeader, times::Tuple{AbstractFloat, AbstractFloat}, nDataSamples::Integer)
    sRate = 1_000_000 ÷ header.common["SamplingInterval"]
    signalTime = nDataSamples / sRate

    if 0 <= times[1] && times[2] <= signalTime
        return round(Int, (times[1]-1)*sRate+1):round(Int, times[2]*sRate)
    else
        error("Time range $times does not fit the available length of the data: $signalTime")
    end
end