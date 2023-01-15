# EEGIO Package

The [*EEGIO*](https://github.com/Telepathy-Software/EEGIO.jl) package allows for loading and saving EEG data from most popular formats. It is configured to extend the FileIO interface for better discoverability and ease-of-use.

Main focus of the package is to provide access to all of the data stored in files. Therefore each format has its own type that is meant to provide easy way to see and extract data for further use. For implementation details, please see the dedicated pages.

Right now, EEGIO supports following formats:
- [BDF](@ref) (load and save)
- [EEG](@ref) (load and save)

If you are interested in processing and analyzing EEG data in Julia, and would like a more general interface for working with data, check out [Telepathy](https://github.com/Telepathy-Software/Telepathy.jl) for which EEGIO serves as an IO backend. It should have reasonable default settings for start, while still allowing you to do all of the customisations included in EEGIO.

### Roadmap
For the 1.0 release, we would like to support loading and saving of all the formats included in [EEG-BIDS specification](https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/03-electroencephalography.html). This includes support for:
- EDF files
- EDF+ and BDF+ extensions
- EEGLab files (.set and .fdt)

If you would like to see other formats (or even better, help to implement them), please open an issue for it.\
\
\

### Other packages
Currently, Julia ecosystem lacks a package serving as a singular entry point for EEG data (a role which EEGIO aspires to fill). There are however packages that implement reading and writing functions for some formats.

BDF/EDF: [EDF.jl](https://github.com/beacon-biosignals/EDF.jl), [EDFplus.jl](https://github.com/wherrera10/EDFPlus.jl), [BDF.jl](https://github.com/sam81/BDF.jl), [BioSemiBDF](https://github.com/igmmgi/BioSemiBDF)\
BrainVision: [brainvisionloader.jl](https://github.com/agricolab/brainvisionloader.jl)

Additionally, there are more general packages that include IO functionality:\
[Neuroimaging.jl](https://github.com/rob-luke/Neuroimaging.jl) and [NeuroAnalyzer.jl](https://codeberg.org/AdamWysokinski/NeuroAnalyzer.jl)

Similarly, there are many well established libraries in other languages that support reading and writing these files (along with tools for analysis). Most popular ones include [EEGLab](https://sccn.ucsd.edu/eeglab/index.php), [FieldTrip](https://www.fieldtriptoolbox.org/), and [Brainstorm](https://neuroimage.usc.edu/brainstorm/Introduction) for Matlab; [MNE-Python](https://mne.tools/stable/index.html) for Python. You should be able to easily find more browsing Github or Google results.