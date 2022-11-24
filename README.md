# EEGIO

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://Telepathy-Software.github.io/EEGIO.jl/stable/)

[![CI](https://github.com/Telepathy-Software/EEGIO.jl/workflows/CI/badge.svg)](https://github.com/Telepathy-Software/EEGIO.jl/actions?query=workflow%3ACI)
[![Codecov](https://codecov.io/gh/Telepathy-Software/EEGIO.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/Telepathy-Software/EEGIO.jl)

Julia library for reading and writing EEG data.  
Designed to be compatible with [`FileIO`](https://github.com/JuliaIO/FileIO.jl) interface, but can be used separately.

EEGIO serves as an IO backend for [`Telepathy.jl`](https://github.com/Telepathy-Software/Telepathy.jl).

Current status: Work-In-Progress  
The main goal is to support reading and writing of all file formats included in the [BIDS specification](https://bids-specification.readthedocs.io/en/stable/04-modality-specific-files/03-electroencephalography.html). Secondly, we will focus on providing import options for other vendor raw files and interoperability with other EEG software packages.

## Version 1.0 roadmap:
- [x] BDF read and write
- [ ] EDF read and write
- [x] EEG read and write
- [ ] EEGLab read and write
- [ ] BDF+ and EDF+ extension