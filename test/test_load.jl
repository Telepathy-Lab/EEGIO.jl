@testitem "Load BDF: Header parsing" begin
    string = IOBuffer(UInt8[0x42, 0x49, 0x4f, 0x53, 0x45, 0x4d, 0x49])
    @test EEGIO.decodeString(string, 7) == "BIOSEMI"

    number = IOBuffer(UInt8[0x33, 0x33, 0x37, 0x31])
    @test EEGIO.decodeNumber(number, 4) == 3371

    chanLabels = IOBuffer(UInt8[0x41, 0x31, 0x41, 0x32, 0x41, 0x33])
    @test EEGIO.decodeChanStrings(chanLabels, 3, 2) == ["A1", "A2", "A3"]

    chanNum = IOBuffer(UInt8[0x20, 0x31, 0x30, 0x31, 0x20, 0x31, 0x35, 0x31, 0x20, 0x32, 0x30, 0x31])
    @test EEGIO.decodeChanNumbers(chanNum, 3, 4) == [101, 151, 201]
end

@testitem "Load BDF: Data selection" begin
    testFile = joinpath(@__DIR__, "files", "Newtest17-256.bdf")
    header = read_bdf(testFile, onlyHeader=true)
    @test typeof(header) == BDFHeader

    @test EEGIO.pick_records(:All, header) == 1:60
    @test EEGIO.pick_records(30, header) == 30
    @test EEGIO.pick_records((2.5,15.9), header) == 2:16
    @test EEGIO.pick_records(4:29, header) == 4:29
    @test_throws "Selection of time interval \"one\"" EEGIO.pick_records("one", header)
    
    @test EEGIO.pick_channels(14, header) == 14
    @test EEGIO.pick_channels(2:10, header) == 2:10
    @test EEGIO.pick_channels(r"A1.", header) == [10, 11, 12, 13, 14, 15, 16]
    @test EEGIO.pick_channels(["A1", "A7", "A13"], header) == [1, 7, 13]
    @test EEGIO.pick_channels(:All, header) == 1:17
    @test EEGIO.pick_channels(:None, header) == Int64[]
    @test_throws "Selection of channels \"Any[]\"" EEGIO.pick_channels([], header)

    @test EEGIO.check_status(1:4, header) == [1, 2, 3, 4, 17]
    
    EEGIO.update_header!(header, 1:10)
    @test header.nBytes == 256*11
    @test header.nChannels == 10

    @test EEGIO.changeToInt(Float64) == Int64
    @test EEGIO.changeToInt(Float32) == Int32
end

@testitem "Load BDF: Data exctraction" begin
    raw = UInt8[1,0,0]
    dataF = [0.]
    dp = 1; sample = 0; chan = 1; chanIdx = 1
    scaleFactor = [1]; offset = [0]
    EEGIO.convert!(raw, dataF, dp, sample, chan, chanIdx, scaleFactor, offset)
    @test dataF[1,1] == 1.
    @test typeof(dataF[1,1]) == Float64

    raw = UInt8[7,0,0]
    dataI = [0]
    EEGIO.convert!(raw, dataI, dp, sample, chan, chanIdx, scaleFactor, offset)
    @test dataI[1,1] == 7
    @test typeof(dataI[1,1]) == Int64

    raw = UInt8[1, 0, 0, 3, 0, 0, 3, 0, 0, 7, 0, 0, 2, 0, 0, 0, 0, 0, 2, 0, 0, 2, 0, 0]
    data = Float64[0 0; 0 0; 0 0; 0 0]
    srate = 4; records = 1; chans = [1, 2]; nChannels = 2
    scaleFactor = [1, 1]; offset = [0, 0]
    EEGIO.convert_data!(raw, data, srate, records, chans, nChannels, scaleFactor, offset)
    @test data == [1 2; 3 0; 3 2; 7 2]
end

# Testing only the basic usage for now.
# Adding tests for combinations of optional parameters would be nice.
@testitem "Load BDF: Read data" begin
    testFile = joinpath(@__DIR__, "files", "Newtest17-256.bdf")
    open(testFile) do fid
        header = EEGIO.read_bdf_header(fid)
        data = EEGIO.read_bdf_data(fid, header, true, Float64, :All, :None, :All, true, false)

        @test header.idCode == "BIOSEMI"
        @test header.nBytes == 4608
        @test length(header.chanLabels) == 17
        
        @test size(data) == (15360, 17)
    end

    data = read_bdf(testFile)
    @test data.header.idCode == "BIOSEMI"
    @test data.header.nBytes == 4608
    @test length(data.header.chanLabels) == 17
    
    @test size(data.data) == (15360, 17)

    @test data.file == "Newtest17-256.bdf"
end