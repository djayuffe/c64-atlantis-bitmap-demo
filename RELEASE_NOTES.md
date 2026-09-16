# Atlantis Bitmap Demo v1.0.0

Initial release of the C64 bitmap demo.

## Highlights

- 25 timed hires-bitmap effects in VIC bank 2.
- Four-phase 40×25 cell renderer with per-effect pattern transforms.
- Atlantis Gabber three-voice SID soundtrack.
- Space-key effect skip with music phrase alignment.

## Build and verification

```bash
make audit
make release
```

The release archive contains `atlantis-bitmap-demo.prg` and these notes. Start
the program in VICE with `./run.sh`.
