# TODO: add checks if data fits the physical/digital dimensions to be written into Int24

function write_bdf(f::String, bdf::BDF; overwrite=false, kwargs...)
    if isfile(f)
        if overwrite
            rm(f)
        else
            error("File $f already exists. Use `overwrite=true` to overwrite the file.")
        end
    end
    open(f, "w+", lock = false) do fid
        write_bdf(fid, bdf; kwargs...)
    end
end

function write_bdf(fid::IO, bdf::BDF; useOffset=true, method="mmap", chunk=512_000)
    # Write the header
    write_bdf_header(fid, bdf)

    # Write the data
    write_bdf_data(fid, bdf.header, bdf.data, useOffset, method, chunk)
end

function write_bdf_header(fid, bdf::BDF)

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

# Write the general data information
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

# Write the chennel specific information
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


# Write data into a file.
function write_bdf_data(fid, header, data, useOffset, method, chunk)
    scaleFactor = Float32.(header.physMax-header.physMin)./(header.digMax-header.digMin)

    # Insert the offset for compatibility with other software
    if useOffset
        offset = Float32.(header.physMin .- (header.digMin .* scaleFactor))
    else
        offset = Int32.(header.physMin .* 0)
    end

    records = header.nDataRecords
    channels = header.nChannels
    srate = header.nSampRec[1]
    duration = header.recordDuration

    if method == "mmap"
        write_mmap(fid, data, records, channels, srate, duration, scaleFactor, offset)
    else method == "sequential"
        write_seq(fid, data, records, channels, srate, duration, scaleFactor, offset, chunk)
    end
end

function write_mmap(fid, data, records, channels, srate, duration, scaleFactor, offset)
    samples = srate * duration
    recordSize = channels*srate*duration*3
    
    output = Mmap.mmap(fid, Vector{UInt8}, (records*recordSize))
    Threads.@threads for rec in 1:records
        for chan in 1:channels
            for sample in 1:samples
                @inbounds @fastmath pointer = (sample + samples*(chan-1) + samples*channels*(rec-1))*3-2
                recode_value(data, output, pointer, rec, srate, sample, chan, scaleFactor, offset)
            end
        end
    end
    # Necessary to properly close the mmaped file.
    finalize(output)
    GC.gc(false)
end

function write_seq(fid, data, records, channels, srate, duration, scaleFactor, offset, chunk)
    recordSize = channels*srate*duration*3

    # Testing different methods of writing to disk has shown that writing in chunks,
    # is more efficient than writing the whole array at once.
    # Here we determine the size of chunk that is a multiple of record size and closest
    # to 512k which is used as a default.
    chunk = chunk + recordSize/2
    chunk = Int(chunk - chunk%recordSize)
    if chunk == 0
        chunk = recordSize
    end
    recNum = Int(chunk/recordSize)
    
    output = Vector{UInt8}(undef,chunk)

    for recStart = 1:recNum:records
        if (recStart + recNum - 1) <= records
            recEnd = recStart + recNum - 1
        else
            recEnd = records
        end
        
        pointer = 1
        for rec in recStart:recEnd
            for chan in 1:channels
                for sample in 1:(srate * duration)
                    recode_value(data, output, pointer, rec, srate, sample, chan, scaleFactor, offset)
                    pointer += 3
                end
            end
        end
        @inbounds write(fid, view(output, 1:(recEnd-recStart+1)*recordSize))
    end
end

function recode_value(data::Matrix{Int32}, output::Vector{UInt8}, pointer, rec, srate, sample, chan, scaleFactor, offset)
    @inbounds output[pointer] = data[(rec-1)*srate+sample, chan] % UInt8
    @inbounds output[pointer+1] = (data[(rec-1)*srate+sample, chan] >> 8) % UInt8
    @inbounds output[pointer+2] = (data[(rec-1)*srate+sample, chan] >> 16) % UInt8
end

function recode_value(data::Matrix{Int64}, output::Vector{UInt8}, pointer, rec, srate, sample, chan, scaleFactor, offset)
    @inbounds value = round(Int32, data[(rec-1)*srate+sample, chan])
    @inbounds output[pointer] = value % UInt8
    @inbounds output[pointer+1] = (value >> 8) % UInt8
    @inbounds output[pointer+2] = (value >> 16) % UInt8
end

function recode_value(data::Matrix{<:AbstractFloat}, output::Vector{UInt8}, pointer, rec, srate, sample, chan, scaleFactor::Vector{Float32}, offset::Vector{Float32})
    @inbounds @fastmath value = round(Int32, ((data[(rec-1)*srate+sample, chan]-offset[chan])/scaleFactor[chan]))
    @inbounds output[pointer] = value % UInt8
    @inbounds output[pointer+1] = (value >> 8) % UInt8
    @inbounds output[pointer+2] = (value >> 16) % UInt8
end