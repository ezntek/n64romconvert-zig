# n64romconvert-zig

N64 ROM format converter, consisting of a library and 2 CLI tools (`n64romconvert` and `n64romtype`) to help you convert between Z64, N64 and V64 ROMs, and to check formats.

## Background

The Super Mario 64 PC port takes specifically z64 ROMs and only z64 ROMs for asset extraction. However, some ROMs are labeled as z64, but in reality, are either n64 or v64, causing asset extraction to fail. This tool prevents this. This was developed out of necessity for `smbuilder`, but proves useful also for emulators that may not support all formats.

I do not condone piracy, nor am I liable if the Nintendo Police knocks on your door. This is a rewrite of the original Rust version.
