function write_bdf(f::String, bdf::BDF)
    open(f, "w", lock = false) do fid
        write_bdf(fid, bdf)
    end
end

function write_bdf(fid::IO, bdf::BDF; useOffset=true)
    # Write the header
    write_header(fid, bdf)

    # Write the data
    write_data(fid, bdf.header, bdf.data, useOffset)

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

function write_data(fid, header, data, useOffset)

    scaleFactor = Float32.(header.physMax-header.physMin)./(header.digMax-header.digMin)
    if useOffset
        offset = Float32.(header.physMin .- (header.digMin .* scaleFactor))
    else
        offset = Int32.(header.physMin .* 0)
    end
    records = header.nDataRecords
    channels = header.nChannels
    srate = header.nSampRec[1]
    duration = header.recordDuration
    
    # Testing different methods of writing to disk has shown that writing in chunks,
    # is more efficient than writing the whole array at once.
    # Here we determine the size of chunk that is a multiple of record size and closest
    # to 512k which is used as a default.
    def_chunk = 512_000
    record_size = channels*srate*duration*3

    chunk = def_chunk + record_size/2
    chunk = Int(chunk - chunk%record_size)
    if chunk == 0
        chunk = record_size
    end
    rec_num = Int(chunk/record_size)
    
    output = Vector{UInt8}(undef,chunk)

    for rec_start = 1:rec_num:records
        if (rec_start + rec_num - 1) <= records
            rec_end = rec_start + rec_num - 1
        else
            rec_end = records
        end
        
        pointer = 1
        for rec in rec_start:rec_end
            for chan in 1:channels
                for sample in 1:(srate * duration)
                    recode_value(data, output, pointer, rec, srate, sample, chan, scaleFactor, offset)
                    pointer += 3
                end
            end
        end
        @inbounds write(fid, @view output[1:(rec_end-rec_start+1)*record_size])
    end
    output = nothing
end

function recode_value(data::Matrix{Int32}, output, pointer, rec, srate, sample, chan, scaleFactor, offset)
    @inbounds output[pointer] = data[(rec-1)*srate+sample, chan] % UInt8
    @inbounds output[pointer+1] = (data[(rec-1)*srate+sample, chan] >> 8) % UInt8
    @inbounds output[pointer+2] = (data[(rec-1)*srate+sample, chan] >> 16) % UInt8
end

function recode_value(data::Matrix{Int64}, output, pointer, rec, srate, sample, chan, scaleFactor, offset)
    value = round(Int32, data[(rec-1)*srate+sample, chan])
    @inbounds output[pointer] = value % UInt8
    @inbounds output[pointer+1] = (value >> 8) % UInt8
    @inbounds output[pointer+2] = (value >> 16) % UInt8
end

function recode_value(data::Matrix{<:AbstractFloat}, output, pointer, rec, srate, sample, chan, scaleFactor, offset)
    value = round(Int32, (data[(rec-1)*srate+sample, chan]/scaleFactor[chan])-offset[chan])
    @inbounds output[pointer] = value % UInt8
    @inbounds output[pointer+1] = (value >> 8) % UInt8
    @inbounds output[pointer+2] = (value >> 16) % UInt8
end