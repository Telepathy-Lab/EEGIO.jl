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

function pick_samples(records::Tuple{AbstractFloat, AbstractFloat}, header::BDFHeader)
    dur =  header.recordDuration
    signalTime = header.nDataRecords * dur
    if 0 <= records[1] && records[2] <= signalTime
        return Int64(floor(records[1]/dur)):Int64(ceil(records[2]/dur))
    else
        error("Time range $records does not fit the available length of the data: $signalTime")
    end
end

function pick_samples(records::UnitRange{}, header::BDFHeader)
    if records[1] >= 1 && records[end] <= header.nDataRecords
        return records
    else
        error("Range $records does not fit in the available $(header.nDataRecords) records.")
    end
end

function pick_samples(records::Any, header)
    error("Selection of time interval \"$records\" should be a number, a range, or a list of indices.")
end