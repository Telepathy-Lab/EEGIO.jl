push!(LOAD_PATH,"../src/")

using Documenter, EEGIO

makedocs(;
    pages=[
        "Home" => "index.md",
        "BDF" => "bdf.md",
        "EEG" => "eeg.md",
    ],
    sitename="EEGIO",
    authors="Telepathy team",
)

deploydocs(
    repo = "github.com/Telepathy-Software/EEGIO.jl.git",
    push_preview=true,
    devbranch="main",
)