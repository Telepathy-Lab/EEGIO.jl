@testitem "BDF Format" begin
    idCodeNonASCII = Int32(255)
    idCode = "TestID"
    subID = "TestSub"
    recID = "TestRec"
    startDate = "01.01.2000"
    startTime = "19:19:19"
    nBytes = 768
    versionDataFormat = "24BIT"
    nDataRecords = 60
    recordDuration = 1
    nChannels = 2
    chanLabels = ["A1", "A2"]
    transducer = ["Active Electrode, pin type", "Active Electrode, pin type"]
    physDim = ["uV", "uV"]
    physMin = Int32[-262144, -262144]
    physMax = Int32[262144, 262144]
    digMin = Int32[-8388608, -8388608]
    digMax = Int32[8388607, 8388607]
    prefilt = ["HP: DC; LP: 113 Hz", "HP: DC; LP: 113 Hz"]
    nSampRec = Int32[256, 256]
    reserved = ["Reserved", "Reserved"]

    header = BDFHeader(idCodeNonASCII, idCode, subID, recID, startDate, startTime, 
    nBytes, versionDataFormat, nDataRecords, recordDuration, nChannels, chanLabels, 
    transducer, physDim, physMin, physMax, digMin, digMax, prefilt, nSampRec, reserved)

    data = rand(Float32, (256*60, 2))
    path = "C:/Path/To/File"
    file = "Filename.ext"

    bdfFile = BDF(header, data, path, file)

    @test typeof(header) == BDFHeader
    @test typeof(bdfFile) == BDF
    @test BDF <: EEGData
end

@testitem "EEG Format" begin
    common = Dict{Any, Any}(
        "Codepage" => "UTF-8",
        "MarkerFile" => "markers.vmrk",
        "DataFormat" => "BINARY",
        "DataOrientation" => "MULTIPLEXED",
        "NumberOfChannels" => 66,
        "DataFile" => "data.eeg",
        "SamplingInterval" => 4000
        )
    binary = Float32
    channels = Dict{String, Vector}(
        "name" => ["Fp1", "Fp2", "F3", "F4", "C3"],
        "number" => Int32[1, 2, 3, 4, 5],
        "resolution" => Float32[0.1, 0.1, 0.1, 0.1, 0.1],
        "reference" => ["", "", "", "", ""],
        "unit" => ["µV", "µV", "µV", "µV", "µV"]
        )
    coords = Dict{Any, Any}()
    comments = ["420"]
        
    number = Int32[1, 2, 3, 4, 5]
    type = ["New Segment", "Stimulus", "Stimulus", "Stimulus", "Stimulus"]
    description = ["", "S253", "S254", "S254", "S253"]
    position = Int32[1, 36475, 51474, 66474, 81473]
    duration = Int32[1, 1, 1, 1, 1]
    chanNum = Int32[0, 0, 0, 0, 0]

    data = rand(Float32, (2000, 5))
    path = "C:/Path/To/File"
    file = "Filename.ext"
    date = "01.01.2000"

    header = EEGHeader(common, binary, channels, coords, comments)
    markers = EEGMarkers(number, type, description, position, duration, chanNum, date)
    eegData = EEG(header, markers, data, path, file)

    @test typeof(header) == EEGHeader
    @test typeof(markers) == EEGMarkers
    @test typeof(eegData) == EEG
    @test EEG <: EEGData
end
