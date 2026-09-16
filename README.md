# Atlantis Bitmap Demo

Pure bitmap-only C64 demo pipeline. The active flow is FX00–FX24, all in VIC bank 2 hires bitmap mode, with the Atlantis Gabber soundtrack.

## Build

```bash
./build.sh
./run.sh
```

`src/atlantis_bitmap_demo.s` is the only source file.

## Verify and clean

```bash
make audit
make clean
```

`make audit` assembles with strict segment checks and verifies deterministic
output. `make clean` removes only generated files in `build/`.

## Contract

- CPU/PLA `$01=$36`
- VIC bank 2
- screen `$8400`
- bitmap `$A000`
- `D018=$18`, `D011=$3B`, `D016=$08`
- placement: `row*320 + col*8 + byteRow`

## Seal finale

FX24 is the seal finale: center lock/cross plus ring/rune fold, bitmap-only, no text/charset path, music unchanged.
