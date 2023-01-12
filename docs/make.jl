push!(LOAD_PATH,"../src/")

using Documenter, EEGIO

makedocs(;
    pages=[
        "Home" => "index.md",
        "Formats" => Any[
            "BDF (BioSemi)" => "formats/bdf.md",
            "EEG (BrainVision)" => "formats/eeg.md",
        ],
        "Utilities" => "utils.md",
        "Reference" => "reference.md",
    ],
    sitename="EEGIO",
    authors="Telepathy team",
)

deploydocs(
    repo = "github.com/Telepathy-Software/EEGIO.jl.git",
    push_preview=true,
    devbranch="main",
)