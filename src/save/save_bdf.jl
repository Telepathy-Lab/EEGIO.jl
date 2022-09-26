function write_bdf(f::String, bdf::BDF)
    open(f, "w", lock = false) do fid
        write_bdf(fid, bdf)
    end
end

function write_bdf(fid, bdf::BDF)
    # Write the header
    write_header(fid, bdf)

    # Write the data
    write_data(fid, bdf.header, bdf.data)

    close(fid)
end

function write_header(fid, bdf::BDF)

    header = bdf.header

    write(fid, 0xff)
    write_record(fid, header.idCode, 7, default="BIOSEMI")
    write_record(fid, header.subID, 80)
    write_record(fid, header.recID, 80)
    write_record(fid, header.startDate, 8)
    write_record(fid, header.startTime, 8)
    write_record(fid, header.nBytes, 8)
    write_record(fid, header.versionDataFormat, 44, default="24BIT")
    write_record(fid, header.nDataRecords, 8, default="-1")
    write_record(fid, header.recordDuration, 8, default="1")
    write_record(fid, header.nChannels, 4)
    chans = header.nChannels
    write_channel_records(fid, chans, header.chanLabels, 16)
    write_channel_records(fid, chans, header.transducer, 80)
    write_channel_records(fid, chans, header.physDim, 8)
    write_channel_records(fid, chans, header.physMin, 8)
    write_channel_records(fid, chans, header.physMax, 8)
    write_channel_records(fid, chans, header.digMin, 8)
    write_channel_records(fid, chans, header.digMax, 8)
    write_channel_records(fid, chans, header.prefilt, 80)
    write_channel_records(fid, chans, header.nSampRec, 8)
    write_channel_records(fid, chans, header.reserved, 32)
end

function write_record(fid, field, fieldLength; default="")
    # Prepare the entry.
    if field == ""
        record = rpad(string(default), fieldLength)
    else
        if length(field)>fieldLength
            @warn "Header field \"$field\"
                    is longer than required $fieldLength bytes and will be truncated."
        end
        record = rpad(string(field),fieldLength)
    end

    # Write bytes to file
    write(fid, codeunits(record))
end

function write_channel_records(fid, nChannels, field, fieldLength; default="")
    for chan in 1:nChannels
        #Prepare the entry for each channel.
        if field == ""
            record = rpad(string(default), fieldLength)
        else
            if length(field[chan])>fieldLength
                @warn "Header field \"$field\" entry on position $chan
                        is longer than required $fieldLength bytes and will be truncated."
            end
            record = rpad(string(field[chan]), fieldLength)
        end

        # Write bytes to file
        write(fid, codeunits(record))
    end
end

function write_data(fid, header, data)

    scaleFactor = Float32.(header.physMax-header.physMin)./(header.digMax-header.digMin)
    records = header.nDataRecords
    channels = header.nChannels
    srate = header.nSampRec[1]
    duration = header.recordDuration
    
    output = Vector{UInt8}(undef,records*channels*srate*duration*3)
    pointer = 1
    for rec in 1:records
        for chan in 1:channels
            for sample in 1:(srate * duration)
                recode_value(data, output, pointer, rec, srate, sample, chan, scaleFactor)
                pointer += 3
            end
        end
    end
    # Testing different methods of writing to disk has shown that writing in 512k chunks,
    # is more efficient than writing the whole array at once.
    ptr = 1
    chunk = 512000
    while length(output) > ptr+ chunk
        @inbounds write(fid, @view output[ptr:ptr+chunk])
        ptr += chunk
    end
    write(fid, @view output[ptr:end])
    output = nothing
end

function recode_value(data::Matrix{Int32}, output, pointer, rec, srate, sample, chan, scaleFactor)
    @inbounds output[pointer] = data[(rec-1)*srate+sample, chan] % UInt8
    @inbounds output[pointer+1] = (data[(rec-1)*srate+sample, chan] >> 8) % UInt8
    @inbounds output[pointer+2] = (data[(rec-1)*srate+sample, chan] >> 16) % UInt8
end

function recode_value(data::Matrix{Int64}, output, pointer, rec, srate, sample, chan, scaleFactor)
    value = round(Int32, data[(rec-1)*srate+sample, chan])
    @inbounds output[pointer] = value % UInt8
    @inbounds output[pointer+1] = (value >> 8) % UInt8
    @inbounds output[pointer+2] = (value >> 16) % UInt8
end

function recode_value(data::Matrix{<:AbstractFloat}, output, pointer, rec, srate, sample, chan, scaleFactor)
    value = round(Int32, map(/,data[(rec-1)*srate+sample, chan],scaleFactor[chan]))
    @inbounds output[pointer] = value % UInt8
    @inbounds output[pointer+1] = (value >> 8) % UInt8
    @inbounds output[pointer+2] = (value >> 16) % UInt8
end