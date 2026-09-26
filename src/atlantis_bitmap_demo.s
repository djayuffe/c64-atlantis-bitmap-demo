; ================================================================
; Copyright (C) 2026 Ulf Bertilsson
; SPDX-License-Identifier: GPL-3.0-or-later
; ATLANTIS BITMAP DEMO
; - Twenty-five bitmap-only effects (FX00..FX24)
; - Atlantis Gabber soundtrack
; - VIC bank 2 hires bitmap contract
; Runtime: $4000+, screen $8400, bitmap $A000, CPU port $01=$36.
; Build: ./build.sh
; Run:   ./run.sh
; ================================================================

!cpu 6502

; BASIC: 10 SYS 16384
* = $0801
        !byte $0c,$08,$0a,$00,$9e,$31,$36,$33,$38,$34,$00,$00,$00

; ---------------- Hardware constants ----------------
SCREEN      = $0400
COLOR       = $d800
BORDER      = $d020
BGCOL       = $d021
CTRL1       = $d011
CTRL2       = $d016
MEMPTR      = $d018
RASTER      = $d012
VICIRQEN    = $d01a
VICIRQFLAG  = $d019
CIA1_ICR    = $dc0d
CIA2_ICR    = $dd0d
CIA2_PRA    = $dd00
CPU_DDR     = $00
CPU_PORT    = $01
CPU_PORT_DDR_SAFE = $2f          ; 6510 port direction: keep memory-control lines outputs
CPU_PORT_BITMAP   = $36          ; LORAM=0, HIRAM=1, CHAREN=1: RAM at $A000, I/O+KERNAL visible

ColLo       = $f7
ColHi       = $f8
TmpA        = $f9
SrcLo       = $fb
SrcHi       = $fc
DstLo       = $fd
DstHi       = $fe

; Palette tables below encode these screen-code values.
G_SPACE     = $20
G_DOT       = $61
G_BLOCK     = $62
G_HLINE     = $63
G_VLINE     = $64
G_SLASH     = $65
G_BSLASH    = $66
G_PLUS      = $67
G_SHADE1    = $68
G_SHADE2    = $69
G_DIAMOND   = $6b

NUM_PARTS   = 25
BITMAP_SCREEN = $8400
BITMAP_BASE   = $a000

; ================================================================
; CORRECT PLA/VIC/BITMAP CONTRACT
; ================================================================
; Renderer:       bitmap-only, one canonical VIC mode for all active parts.
; PLA/CPU port:   $36, not $37. BASIC ROM is off so CPU writes/reads RAM at $A000.
;                 KERNAL and I/O remain visible, so SID/VIC writes and KERNAL IRQ return are safe.
; VIC bank:       bank 2 ($8000-$bfff), CIA2 DD00 bits = %01.
; Screen matrix:  $8400.
; Bitmap RAM:     $a000.
; D018:           $18 (bank-relative screen $0400 / bitmap $2000).
; Music:          Atlantis Gabber driver with a bitmap-only seal finale.
; Removed:        active text/charset renderer and live text/bitmap strobe.
; Safety:         ForceVICBitmapBank2 hard-restores PLA+VIC+bitmap every frame.
; ================================================================

; ================================================================
; Runtime code/data safely outside VIC charset RAM
; ================================================================
* = $4000

Start:
        sei
        ldx #$ff
        txs
        lda #CPU_PORT_DDR_SAFE
        sta CPU_DDR
        lda #CPU_PORT_BITMAP
        sta CPU_PORT
        lda #$7f
        sta CIA1_ICR
        sta CIA2_ICR
        lda CIA1_ICR
        lda CIA2_ICR
        lda #0
        sta VICIRQEN
        lda VICIRQFLAG
        sta VICIRQFLAG
        jsr ForceVICBitmapBank2
        jsr ClearBitmapBank2          ; full $A000 bitmap clear once at boot
        jsr SetupBitmapBank2Colors    ; $8400 bitmap screen + color RAM
        jsr SID_Init
        jsr IRQ_Init
        lda #0
        sta Part
        jsr LoadPart
        cli
MainLoop:
        lda FrameReady
        beq MainLoop
        lda #0
        sta FrameReady
        jsr CheckSkipKey
        jsr EnsureRuntimeState
        jsr ForceVICBitmapBank2
        jsr MusicTick
        jsr VisualBeatPulse            ; tiny cracktro border/screen pulse
        jsr UpdateSequencer
        jmp MainLoop

ForceVICBitmapBank2:
        ; unconditional strict PLA + VIC + bitmap restore.
        ; $36 is intentional: RAM at $A000 is CPU-visible, I/O is visible, KERNAL stays visible.
        ; Correct physical mode: PLA $36, VIC bank2, screen $8400, bitmap $a000, D018=$18.
        ; No cache fast-path: stale cache was the source of wrong char/bank symptoms.
ForceVICBitmapBank2_Hard:
        lda #CPU_PORT_DDR_SAFE
        sta CPU_DDR
        lda #CPU_PORT_BITMAP
        sta CPU_PORT
        lda $dd02
        ora #%00000011
        sta $dd02
        lda CIA2_PRA
        and #%11111100
        ora #%00000001              ; VIC bank 2: $8000-$bfff
        sta CIA2_PRA
        lda #$3b                    ; bitmap mode on, 25 rows
        sta CTRL1
        lda #$08                    ; hires, 40 col, multicolor off
        sta CTRL2
        lda #$18                    ; bank-relative screen $0400, bitmap $2000
        sta MEMPTR
        lda #0
        sta BGCOL
        sta $d015                   ; bitmap parts never use sprites
        sta $d017
        sta $d01d
        sta $d01c
        rts
ResetEffectLocalState:
        ; Wipe per-effect scratch state before starting a new part.
        lda #0
        sta LocalTick
        sta EffectIndex
        sta WGCol
        sta StarIndex
        sta GatePhase
        sta ClearRow
        sta BitmapByte
        sta PlotX
        sta PlotY
        sta Phase
        sta PlotChar
        sta PlotColor
        sta LineColor
        sta LineChar
        rts

; no character-ROM bootstrap remains. Active release is bitmap-only.

IRQ_Init:
        lda #$7f
        sta CIA1_ICR
        sta CIA2_ICR
        lda CIA1_ICR
        lda CIA2_ICR
        lda #<IRQ_Main
        sta $0314
        lda #>IRQ_Main
        sta $0315
        lda #$30
        sta RASTER
        lda CTRL1
        and #$7f
        sta CTRL1
        lda #$01
        sta VICIRQEN
        sta VICIRQFLAG
        rts

IRQ_Main:
        pha
        txa
        pha
        tya
        pha
        lda #$01
        sta VICIRQFLAG
        ; IRQ must not fight effect-owned VIC mode mid-frame.
        ; Mode/bank is restored in main loop and in each effect preflight/update.
        inc Frame
        lda #1
        sta FrameReady
        pla
        tay
        pla
        tax
        pla
        jmp $ea31

SID_Init:
        ldx #$18
        lda #0
SID_Clear:
        sta $d400,x
        dex
        bpl SID_Clear
        ; ATLANTIS GABBER: V1 brutal bass/kick hybrid.
        lda #$03                    ; fast attack/decay, hard pulse thump
        sta $d405
        lda #$f4                    ; high sustain, short release
        sta $d406
        ; V2 Atlantis saw/pulse lead, short rave pluck.
        lda #$12
        sta $d40c
        lda #$86
        sta $d40d
        ; V3 gabber click / ghost-kick / clap transient.
        lda #$00
        sta $d413
        lda #$08
        sta $d414
        lda #$00
        sta $d415
        lda #$20
        sta $d416
        lda #$f3                    ; high resonance, route V1+V2 through filter
        sta $d417
        lda #$1f                    ; low-pass + volume 15
        sta $d418
        rts

EnsureRuntimeState:
        ; Restore PLA state and recover if the active part index is invalid.
        lda #CPU_PORT_DDR_SAFE
        sta CPU_DDR
        lda #CPU_PORT_BITMAP
        sta CPU_PORT
        lda Part
        cmp #NUM_PARTS
        bcc EnsureRuntimeState_PartOk
        lda #0
        sta Part
        jsr LoadPart
EnsureRuntimeState_PartOk:
        rts

VisualBeatPulse:
        ; Subtle cracktro sync: black most of the time, flash on kick/clap steps.
        ldx MusicStep
        lda DrumPat,x
        beq VisualBeatPulse_Black
        cmp #1
        beq VisualBeatPulse_Kick
        cmp #2
        beq VisualBeatPulse_Ghost
        cmp #3
        beq VisualBeatPulse_Clap
        lda #$0b                    ; hat / cyan-blue
        bne VisualBeatPulse_Set
VisualBeatPulse_Ghost:
        lda #$0e                    ; ghost kick / light blue
        bne VisualBeatPulse_Set
VisualBeatPulse_Kick:
        lda #$06                    ; kick / blue
        bne VisualBeatPulse_Set
VisualBeatPulse_Clap:
        lda #$0f                    ; clap / light grey
VisualBeatPulse_Set:
        sta BORDER
        rts
VisualBeatPulse_Black:
        lda #0
        sta BORDER
        rts

MusicFrameFX:
        ; frame-level SID movement between 4-frame tracker retriggers.
        ; Keeps the Atlantis Gabber theme, but adds real punch: PWM shimmer,
        ; lead vibrato/glide color, filter low-byte movement and drum pitch drop.
        lda Frame
        clc
        adc MusicStep
        and #$3f
        tax
        lda LeadPwLo,x
        sta $d409
        lda LeadPwHi,x
        sta $d40a
        lda FilterCutHi,x
        sta $d416
        lda Frame
        asl
        eor MusicStep
        sta $d415

        ; Tiny lead vibrato, only if the current row has a lead note.
        ldx MusicStep
        lda LeadLo,x
        cmp #$ff
        beq MusicFrameFX_Drum
        clc
        adc Frame
        and #$03
        clc
        adc LeadLo,x
        sta $d407
        lda LeadHi,x
        adc #0
        sta $d408

MusicFrameFX_Drum:
        lda DrumKind
        beq MusicFrameFX_Done
        cmp #1
        beq MusicFrameFX_KickDrop
        cmp #2
        beq MusicFrameFX_GhostDrop
        cmp #3
        beq MusicFrameFX_ClapHold
        jmp MusicFrameFX_HatHold
MusicFrameFX_KickDrop:
        lda MusicSub
        and #$03
        tax
        lda KickDropLo,x
        sta $d40e
        lda KickDropHi,x
        sta $d40f
        lda KickDropCtl,x
        sta $d412
        rts
MusicFrameFX_GhostDrop:
        lda MusicSub
        and #$03
        tax
        lda GhostDropLo,x
        sta $d40e
        lda GhostDropHi,x
        sta $d40f
        lda GhostDropCtl,x
        sta $d412
        rts
MusicFrameFX_ClapHold:
        lda #$81
        sta $d412
        rts
MusicFrameFX_HatHold:
        lda #$81
        sta $d412
MusicFrameFX_Done:
        rts

CheckSkipKey:
        ; SPACE skips both the visual effect and the matching cracktro phrase.
        ; Debounced so holding space does not blast through every part.
        jsr $ffe4                    ; KERNAL GETIN, A=0 if no key
        cmp #$20
        bne CheckSkipKey_Release
        lda SkipLatch
        bne CheckSkipKey_Done
        lda #1
        sta SkipLatch
        jsr SkipNextPartAndMusic
        rts
CheckSkipKey_Release:
        lda #0
        sta SkipLatch
CheckSkipKey_Done:
        rts

UpdateSequencer:
        jsr DispatchUpdate
        ; robust 16-bit timer countdown with no wrap-underflow dependency.
        lda TimerLo
        ora TimerHi
        bne UpdateSequencer_Count
        jsr NextPart
        rts
UpdateSequencer_Count:
        lda TimerLo
        bne UpdateSequencer_DecLo
        dec TimerHi
        lda #$ff
        sta TimerLo
        rts
UpdateSequencer_DecLo:
        dec TimerLo
        rts

NextPart:
        inc Part
        lda Part
        cmp #NUM_PARTS
        bcc NextPart_Load
        lda #0
        sta Part
NextPart_Load:
        jsr LoadPart
        rts

SkipNextPartAndMusic:
        ; Explicit user skip: advance effect and jump music to matching section.
        inc Part
        lda Part
        cmp #NUM_PARTS
        bcc SkipNextPart_HavePart
        lda #0
        sta Part
SkipNextPart_HavePart:
        jsr StopSIDGates
        jsr LoadPart                  ; LoadPart already resets matching music phrase.
        rts

ResetMusicForPart:
        ldx Part
        lda MusicStart,x
        sta MusicStep
        lda #3                       ; next MusicTick immediately executes Music_Do
        sta MusicSub
        rts

StopSIDGates:
        ; complete SID gate/control cleanup before effect/music switches.
        lda #$40
        sta $d404
        sta $d40b
        lda #$80
        sta $d412
        lda #0
        sta $d418
        lda #$1f
        sta $d418
        rts

LoadPart:
        ; Canonical bitmap-only part entry.
        jsr StopSIDGates
        jsr ResetEffectLocalState
        jsr ForceVICBitmapBank2
        jsr ClearBitmapBank2
        jsr SetupBitmapBank2Colors
        ldx Part
        lda DurLo,x
        sta TimerLo
        lda DurHi,x
        sta TimerHi
        jsr ResetMusicForPart
        lda InitLo,x
        sta PartInitVector+1
        lda InitHi,x
        sta PartInitVector+2
PartInitVector:
        jsr $ffff
        rts

DispatchUpdate:
        ldx Part
        lda UpdLo,x
        sta PartUpdateVector+1
        lda UpdHi,x
        sta PartUpdateVector+2
PartUpdateVector:
        jsr $ffff
        rts

; sequencer tables moved to data area after effect labels.


PartInit:
        ; LoadPart owns all part initialization.
        rts

BitmapFrameCommon:
        ; Keep the frame path minimal; drawing is phased in DrawBitmapCellField.
        inc LocalTick
        ; The main loop owns the PLA/VIC restore. Colours update with each cell.
        rts

; 0: Bitmap ColWarp Grid - diagonal XOR warp plasma
FX00_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapWarpGridBank2
        rts

; 1: Bitmap Gate Runner - scrolling tunnel gates
FX01_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapGateRunnerBank2
        rts

; 2: Bitmap Quantum Starfield - star/noise scatter
FX02_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapStarfieldBank2
        rts

; 3: Bitmap Quantum Plasma - full plasma
FX03_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapPlasmaBank2
        rts

; 4: Bitmap Neon Lightning - sharp alternating strike field
FX04_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapLightningBank2
        rts

; 5: Bitmap Hyper Warp - fast radial/ring hybrid
FX05_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapHyperWarpBank2
        rts

; 6: Bitmap Fire/Ice Moire - inverted dual-phase plasma
FX06_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapFireIceBank2
        rts

; 7: Bitmap Raster Temple Bars - horizontal temple bars
FX07_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapRasterTempleBank2
        rts

; 8: Bitmap Ocean Depth - sonar rings
FX08_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapRingsBank2
        rts

; 9: Bitmap Mirror Rune Tunnel - mirrored glyph-like slashes
FX09_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapMirrorRuneBank2
        rts

; 10: Bitmap Sine City Scanner - skyline bars + scanner
FX10_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapSineCityBank2
        rts

; 11: Bitmap Atlantis Core - alternating plasma/rings
FX11_Update:
        jsr BitmapFrameCommon
        lda LocalTick
        and #$10
        beq B11_Plasma
        jsr DrawBitmapRingsBank2
        rts
B11_Plasma:
        jsr DrawBitmapPlasmaBank2
        rts

; 12: Bitmap Final Hyperswitch - bitmap-only, no text strobe
FX12_Update:
        jsr BitmapFrameCommon
        lda LocalTick
        and #$08
        beq B12_Rings
        jsr DrawBitmapLightningBank2
        rts
B12_Rings:
        jsr DrawBitmapHyperWarpBank2
        rts

; 13: Bitmap Deep Sea Vortex - rotating Atlantis vortex/pressure field
FX13_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapVortexBank2
        rts

; 14: Bitmap Temple Circuit - angular circuit/rune scan
FX14_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapCircuitBank2
        rts

; 15: Bitmap Final Bloom - dense finale flash/ring/warp mix
FX15_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapFinalBloomBank2
        rts

; 16: Bitmap Trident Sweep - Atlantis trident beams / cross cuts
FX16_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapTridentSweepBank2
        rts

; 17: Bitmap Abyss Grid - pressure-grid checker with depth shimmer
FX17_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapAbyssGridBank2
        rts

; 18: Bitmap Pressure Runes - expanding rune pressure plates
FX18_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapPressureRunesBank2
        rts

; 19: Bitmap Mega Bloom Finale - final dense all-pattern bloom
FX19_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapMegaBloomBank2
        rts

; 20: Bitmap Deep Lattice - expanding diagonal lattice pressure field
FX20_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapDeepLatticeBank2
        rts

; 21: Bitmap Kraken Pulse - tentacle/pulse fold around center
FX21_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapKrakenPulseBank2
        rts

; 22: Bitmap Tide Wall - heavy horizontal water-wall shutters
FX22_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapTideWallBank2
        rts

; 23: Bitmap Sunken Finale - final dense Atlantis/ring/lightning mix
FX23_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapSunkenFinaleBank2
        rts

; 24: release Seal - release-candidate lock/signature effect
FX24_Update:
        jsr BitmapFrameCommon
        jsr DrawBitmapSealBank2
        rts

; ================================================================
; ULTRA HYPEROPTIMIZED BITMAP PIPELINE
; - four-phase row+column renderer cuts bitmap writes further
; - per-cell pattern dispatch moved to self-patched direct JSR
; - full 1KB color sweep removed from hot frame path
; ================================================================

; ================================================================
; SCREEN-CORRECT BITMAP PLACEMENT PIPELINE
; C64 hires bitmap is NOT a flat 320x200 linear framebuffer for effects.
; Visible placement is 40x25 cells, each cell is 8 consecutive bytes:
;   BITMAP_BASE + row*320 + col*8 + byteRow
; Color/screen matrix is:
;   BITMAP_SCREEN + row*40 + col
; All FX00..FX23 draw through this cell-addressed path so effects are
; placed in the correct visible screen cells on real VIC-II hardware.
; ================================================================

ClearBitmapBank2:
        lda #0
        ldx #0
ClearBitmapBank2_Loop:
        sta BITMAP_BASE+$0000,x
        sta BITMAP_BASE+$0100,x
        sta BITMAP_BASE+$0200,x
        sta BITMAP_BASE+$0300,x
        sta BITMAP_BASE+$0400,x
        sta BITMAP_BASE+$0500,x
        sta BITMAP_BASE+$0600,x
        sta BITMAP_BASE+$0700,x
        sta BITMAP_BASE+$0800,x
        sta BITMAP_BASE+$0900,x
        sta BITMAP_BASE+$0a00,x
        sta BITMAP_BASE+$0b00,x
        sta BITMAP_BASE+$0c00,x
        sta BITMAP_BASE+$0d00,x
        sta BITMAP_BASE+$0e00,x
        sta BITMAP_BASE+$0f00,x
        sta BITMAP_BASE+$1000,x
        sta BITMAP_BASE+$1100,x
        sta BITMAP_BASE+$1200,x
        sta BITMAP_BASE+$1300,x
        sta BITMAP_BASE+$1400,x
        sta BITMAP_BASE+$1500,x
        sta BITMAP_BASE+$1600,x
        sta BITMAP_BASE+$1700,x
        sta BITMAP_BASE+$1800,x
        sta BITMAP_BASE+$1900,x
        sta BITMAP_BASE+$1a00,x
        sta BITMAP_BASE+$1b00,x
        sta BITMAP_BASE+$1c00,x
        sta BITMAP_BASE+$1d00,x
        sta BITMAP_BASE+$1e00,x
        sta BITMAP_BASE+$1f00,x
        inx
        bne ClearBitmapBank2_Loop
        rts

SetupBitmapBank2Colors:
        ; Hires bitmap screen matrix. High nibble = set pixels, low nibble = bg.
        ; Keep black background and bright foregrounds in the correct 40x25 matrix.
        lda #$10
        ldx #0
SetupBitmapScreen_Loop:
        sta BITMAP_SCREEN+$000,x
        sta BITMAP_SCREEN+$100,x
        sta BITMAP_SCREEN+$200,x
        sta BITMAP_SCREEN+$300,x
        lda #0
        sta COLOR+$000,x
        sta COLOR+$100,x
        sta COLOR+$200,x
        sta COLOR+$300,x
        lda #$10
        inx
        bne SetupBitmapScreen_Loop
        rts

; ---- FX wrappers: set visual identity and patch direct pattern JSR ----
DrawBitmapWarpGridBank2:
        lda #0
        sta EffectIndex
        lda #<Pattern_Warp
        sta PatternCall+1
        lda #>Pattern_Warp
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapGateRunnerBank2:
        lda #1
        sta EffectIndex
        lda #<Pattern_Gate
        sta PatternCall+1
        lda #>Pattern_Gate
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapStarfieldBank2:
        lda #2
        sta EffectIndex
        lda #<Pattern_Stars
        sta PatternCall+1
        lda #>Pattern_Stars
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapPlasmaBank2:
        lda #3
        sta EffectIndex
        lda #<Pattern_Plasma
        sta PatternCall+1
        lda #>Pattern_Plasma
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapLightningBank2:
        lda #4
        sta EffectIndex
        lda #<Pattern_Lightning
        sta PatternCall+1
        lda #>Pattern_Lightning
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapHyperWarpBank2:
        lda #5
        sta EffectIndex
        lda #<Pattern_Hyper
        sta PatternCall+1
        lda #>Pattern_Hyper
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapFireIceBank2:
        lda #6
        sta EffectIndex
        lda #<Pattern_FireIce
        sta PatternCall+1
        lda #>Pattern_FireIce
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapRasterTempleBank2:
        lda #7
        sta EffectIndex
        lda #<Pattern_Temple
        sta PatternCall+1
        lda #>Pattern_Temple
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapRingsBank2:
        lda #8
        sta EffectIndex
        lda #<Pattern_Rings
        sta PatternCall+1
        lda #>Pattern_Rings
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapMirrorRuneBank2:
        lda #9
        sta EffectIndex
        lda #<Pattern_Mirror
        sta PatternCall+1
        lda #>Pattern_Mirror
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapSineCityBank2:
        lda #10
        sta EffectIndex
        lda #<Pattern_City
        sta PatternCall+1
        lda #>Pattern_City
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapVortexBank2:
        lda #13
        sta EffectIndex
        lda #<Pattern_Vortex
        sta PatternCall+1
        lda #>Pattern_Vortex
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapCircuitBank2:
        lda #14
        sta EffectIndex
        lda #<Pattern_Circuit
        sta PatternCall+1
        lda #>Pattern_Circuit
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapFinalBloomBank2:
        lda #15
        sta EffectIndex
        lda #<Pattern_FinalBloom
        sta PatternCall+1
        lda #>Pattern_FinalBloom
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapTridentSweepBank2:
        lda #16
        sta EffectIndex
        lda #<Pattern_TridentSweep
        sta PatternCall+1
        lda #>Pattern_TridentSweep
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapAbyssGridBank2:
        lda #17
        sta EffectIndex
        lda #<Pattern_AbyssGrid
        sta PatternCall+1
        lda #>Pattern_AbyssGrid
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapPressureRunesBank2:
        lda #18
        sta EffectIndex
        lda #<Pattern_PressureRunes
        sta PatternCall+1
        lda #>Pattern_PressureRunes
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapMegaBloomBank2:
        lda #19
        sta EffectIndex
        lda #<Pattern_MegaBloom
        sta PatternCall+1
        lda #>Pattern_MegaBloom
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapDeepLatticeBank2:
        lda #20
        sta EffectIndex
        lda #<Pattern_DeepLattice
        sta PatternCall+1
        lda #>Pattern_DeepLattice
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapKrakenPulseBank2:
        lda #21
        sta EffectIndex
        lda #<Pattern_KrakenPulse
        sta PatternCall+1
        lda #>Pattern_KrakenPulse
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapTideWallBank2:
        lda #22
        sta EffectIndex
        lda #<Pattern_TideWall
        sta PatternCall+1
        lda #>Pattern_TideWall
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapSunkenFinaleBank2:
        lda #23
        sta EffectIndex
        lda #<Pattern_SunkenFinale
        sta PatternCall+1
        lda #>Pattern_SunkenFinale
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapSealBank2:
        lda #24
        sta EffectIndex
        lda #<Pattern_Seal
        sta PatternCall+1
        lda #>Pattern_Seal
        sta PatternCall+2
        jmp DrawBitmapCellField
DrawBitmapCellField:
        ; optimized 4-phase checkerboard cell renderer.
        ; - inlines CalcBitmapCellPtr
        ; - inlines CalcBitmapCellBase
        ; - keeps self-patched PatternCall direct JSR
        ; - unrolls the 8 bitmap byte writes
        ; - writes cell color in the same hot loop
        ; Phase map:
        ;   0 even rows / even columns
        ;   1 even rows / odd  columns
        ;   2 odd  rows / even columns
        ;   3 odd  rows / odd  columns
        lda LocalTick
        and #$03
        sta Phase
        lsr                         ; bit1 -> row parity
        sta PlotY
DrawCell_RowLoop:
        ldx PlotY
        lda BmpRowLo,x
        sta DstLo
        lda BmpRowHi,x
        sta DstHi
        lda BmpScrRowLo,x
        sta ColLo
        lda BmpScrRowHi,x
        sta ColHi
        lda Phase
        and #$01                    ; bit0 -> column parity
        sta PlotX
DrawCell_ColLoop:
        ; Fast cell address: Src = rowBase + col*8.
        ldx PlotX
        lda BmpColLo,x
        clc
        adc DstLo
        sta SrcLo
        lda BmpColHi,x
        adc DstHi
        sta SrcHi

        ; Common pattern seed from visible 40x25 cell coordinates.
        lda PlotX
        asl
        asl
        eor PlotY
        eor LocalTick
        clc
        adc EffectIndex
        adc EffectIndex
        tay
        lda BitmapPattern,y
        sta BitmapByte

PatternCall:
        jsr Pattern_Warp            ; self-modified by FXxx wrappers

        ; Unrolled WriteBitmapCell8: one 8x8 hires cell at Src.
        ldy #0
        lda BitmapByte
        sta (SrcLo),y
        iny
        eor #$18
        sta (SrcLo),y
        iny
        lda BitmapByte
        sta (SrcLo),y
        iny
        eor #$24
        sta (SrcLo),y
        iny
        lda BitmapByte
        sta (SrcLo),y
        iny
        eor #$42
        sta (SrcLo),y
        iny
        lda BitmapByte
        sta (SrcLo),y
        iny
        eor #$81
        sta (SrcLo),y

        ; Fast bitmap screen/color matrix write for same cell.
        lda PlotX
        clc
        adc PlotY
        adc LocalTick
        adc EffectIndex
        and #$0f
        tax
        lda BitmapColorNibbles,x
        ldy PlotX
        sta (ColLo),y

        ; Step column by 2. Use branch-over-JMP so ACME can never fail range.
        lda PlotX
        clc
        adc #2
        sta PlotX
        cmp #40
        bcs DrawCell_ColDone
        jmp DrawCell_ColLoop
DrawCell_ColDone:
        ; Step row by 2. Use branch-over-JMP for range safety.
        lda PlotY
        clc
        adc #2
        sta PlotY
        cmp #25
        bcs DrawCell_RowDone
        jmp DrawCell_RowLoop
DrawCell_RowDone:
        rts

;

Pattern_Warp:
        ; stronger warp: combine base byte with row/column phase.
        lda PlotX
        asl
        eor PlotY
        clc
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        eor BitmapByte
        sta BitmapByte
        rts

Pattern_Gate:
        lda PlotX
        eor LocalTick
        and #$07
        bne Pattern_Gate_Side
        lda #$ff
        sta BitmapByte
        rts
Pattern_Gate_Side:
        lda PlotY
        eor LocalTick
        and #$03
        bne Pattern_Gate_Dim
        lda #$18
        sta BitmapByte
        rts
Pattern_Gate_Dim:
        lda BitmapByte
        and #$3c
        sta BitmapByte
        rts

Pattern_Stars:
        lda PlotX
        asl
        eor PlotY
        eor LocalTick
        and #$1f
        beq Pattern_StarBright
        lda BitmapByte
        and #$81
        sta BitmapByte
        rts
Pattern_StarBright:
        lda #$ff
        sta BitmapByte
        rts

Pattern_Plasma:
        ; richer XOR plasma with independent x/y phase.
        lda PlotX
        asl
        asl
        clc
        adc LocalTick
        tay
        lda BitmapPattern,y
        sta TmpA
        lda PlotY
        asl
        eor LocalTick
        tay
        lda BitmapRingPattern,y
        eor TmpA
        ora #$18
        sta BitmapByte
        rts

Pattern_Lightning:
        ; two crossing lightning paths instead of one sparse test.
        lda PlotX
        sec
        sbc PlotY
        clc
        adc LocalTick
        and #$07
        beq Pattern_Lightning_Bright
        lda PlotX
        clc
        adc PlotY
        adc LocalTick
        and #$0f
        beq Pattern_Lightning_Bright
        lda BitmapByte
        and #$24
        sta BitmapByte
        rts
Pattern_Lightning_Bright:
        lda #$ff
        sta BitmapByte
        rts

Pattern_Hyper:
        lda PlotX
        eor #20
        eor PlotY
        eor #12
        clc
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        sta BitmapByte
        rts

Pattern_FireIce:
        ; split-screen fire/ice with moving seam.
        lda LocalTick
        and #$03
        clc
        adc #11
        sta TmpA
        lda PlotY
        cmp TmpA
        bcc Pattern_Fire
Pattern_Ice:
        lda BitmapByte
        eor #$0f
        ora #$18
        sta BitmapByte
        rts
Pattern_Fire:
        lda BitmapByte
        eor #$f0
        ora #$24
        sta BitmapByte
        rts

Pattern_Temple:
        ; temple bars plus vertical pillar flashes.
        lda PlotX
        and #$07
        beq Pattern_Temple_Pillar
        lda PlotY
        clc
        adc LocalTick
        and #$07
        tax
        lda TempleCellBars,x
        sta BitmapByte
        rts
Pattern_Temple_Pillar:
        lda #$ff
        sta BitmapByte
        rts

Pattern_Rings:
        ; centered sonar rings with stronger symmetric fold.
        lda PlotX
        sec
        sbc #20
        sta TmpA
        lda PlotY
        sec
        sbc #12
        eor TmpA
        asl
        clc
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        ora #$18
        sta BitmapByte
        rts

Pattern_Mirror:
        ; mirrored rune tunnel; fold right half back toward center.
        lda PlotX
        cmp #20
        bcc Pattern_Mirror_Left
        eor #$3f
Pattern_Mirror_Left:
        asl
        eor PlotY
        eor LocalTick
        tay
        lda MirrorRuneBitmap,y
        sta BitmapByte
        rts

Pattern_City:
        ; sine skyline with moving scanner in the sky.
        lda PlotY
        cmp #18
        bcc Pattern_City_Sky
        lda PlotX
        clc
        adc LocalTick
        and #$0f
        tax
        lda SineCityBitmapBars,x
        sta BitmapByte
        rts
Pattern_City_Sky:
        lda PlotX
        eor LocalTick
        and #$0f
        beq Pattern_City_Scanner
        lda PlotY
        eor LocalTick
        and #$1f
        beq Pattern_City_Scanner
        lda #0
        sta BitmapByte
        rts
Pattern_City_Scanner:
        lda #$18
        sta BitmapByte
        rts

Pattern_Vortex:
        ; pressure/vortex fold around screen center.
        lda PlotX
        sec
        sbc #20
        eor PlotY
        clc
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        eor BitmapByte
        sta TmpA
        lda PlotY
        sec
        sbc #12
        asl
        eor TmpA
        ora #$24
        sta BitmapByte
        rts

Pattern_Circuit:
        ; angular temple/circuit scan lines.
        lda PlotX
        and #$03
        beq Pattern_Circuit_Bright
        lda PlotY
        eor LocalTick
        and #$07
        beq Pattern_Circuit_Bright
        lda PlotX
        clc
        adc PlotY
        adc LocalTick
        tay
        lda BitmapPattern,y
        and #$66
        ora #$18
        sta BitmapByte
        rts
Pattern_Circuit_Bright:
        lda #$ff
        sta BitmapByte
        rts

Pattern_FinalBloom:
        ; dense final mix, avoids text-mode strobe while still feeling like a finale.
        lda PlotX
        asl
        eor PlotY
        eor LocalTick
        tay
        lda BitmapPattern,y
        sta TmpA
        lda PlotX
        clc
        adc PlotY
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        eor TmpA
        ora #$81
        sta BitmapByte
        rts

Pattern_TridentSweep:
        ; Atlantis trident beams: center spear plus two moving diagonals.
        lda PlotX
        cmp #20
        beq Pattern_Trident_Bright
        lda PlotX
        clc
        adc LocalTick
        and #$0f
        cmp PlotY
        beq Pattern_Trident_Bright
        lda PlotX
        eor PlotY
        clc
        adc LocalTick
        tay
        lda BitmapPattern,y
        and #$7e
        ora #$18
        sta BitmapByte
        rts
Pattern_Trident_Bright:
        lda #$ff
        sta BitmapByte
        rts

Pattern_AbyssGrid:
        ; pressure grid shimmer, cheap but strong cell contrast.
        lda PlotX
        eor PlotY
        eor LocalTick
        and #$03
        beq Pattern_Abyss_Bright
        lda PlotX
        asl
        clc
        adc PlotY
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        and #$3c
        sta BitmapByte
        rts
Pattern_Abyss_Bright:
        lda #$db
        sta BitmapByte
        rts

Pattern_PressureRunes:
        ; expanding rune plates around the center.
        lda PlotX
        sec
        sbc #20
        eor PlotY
        sec
        sbc #12
        clc
        adc LocalTick
        tay
        lda MirrorRuneBitmap,y
        eor BitmapByte
        ora #$24
        sta BitmapByte
        rts

Pattern_MegaBloom:
        ; finale bloom: mixes ring, bitmap and rune sources.
        lda PlotX
        asl
        eor PlotY
        clc
        adc LocalTick
        tay
        lda BitmapPattern,y
        sta TmpA
        lda PlotX
        clc
        adc PlotY
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        eor TmpA
        sta TmpA
        lda PlotX
        eor PlotY
        tay
        lda MirrorRuneBitmap,y
        eor TmpA
        ora #$81
        sta BitmapByte
        rts


Pattern_DeepLattice:
        ; diagonal lattice, fast branch-local cells only.
        lda PlotX
        asl
        eor PlotY
        clc
        adc LocalTick
        and #$07
        beq Pattern_DeepLattice_Bright
        lda PlotX
        clc
        adc PlotY
        eor LocalTick
        tay
        lda BitmapPattern,y
        and #$5a
        ora #$18
        sta BitmapByte
        rts
Pattern_DeepLattice_Bright:
        lda #$ff
        sta BitmapByte
        rts

Pattern_KrakenPulse:
        ; tentacle pulse around center using folded x/y phase.
        lda PlotX
        sec
        sbc #20
        sta TmpA
        lda PlotY
        sec
        sbc #12
        asl
        eor TmpA
        clc
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        sta TmpA
        lda PlotX
        eor LocalTick
        tay
        lda MirrorRuneBitmap,y
        eor TmpA
        ora #$24
        sta BitmapByte
        rts

Pattern_TideWall:
        ; water-wall shutters with moving horizontal pressure bands.
        lda PlotY
        asl
        clc
        adc LocalTick
        and #$0f
        tax
        lda TideWallBars,x
        sta TmpA
        lda PlotX
        eor LocalTick
        and #$03
        bne Pattern_TideWall_NoCut
        lda TmpA
        eor #$ff
        sta TmpA
Pattern_TideWall_NoCut:
        lda TmpA
        sta BitmapByte
        rts

Pattern_SunkenFinale:
        ; final all-source mix, no mode strobe and no music change.
        lda PlotX
        asl
        eor PlotY
        clc
        adc LocalTick
        tay
        lda BitmapPattern,y
        sta TmpA
        lda PlotX
        clc
        adc PlotY
        adc LocalTick
        tay
        lda BitmapRingPattern,y
        eor TmpA
        sta TmpA
        lda PlotX
        eor PlotY
        eor LocalTick
        tay
        lda MirrorRuneBitmap,y
        eor TmpA
        ora #$c3
        sta BitmapByte
        rts

Pattern_Seal:
        ; release: release-candidate seal.  Branch-local center cross +
        ; ring/rune fold; no text/charset path and no music changes.
        lda PlotX
        cmp #19
        beq Pattern_Seal_Bright
        cmp #20
        beq Pattern_Seal_Bright
        lda PlotY
        cmp #11
        beq Pattern_Seal_Bright
        cmp #12
        beq Pattern_Seal_Bright
        lda PlotX
        asl
        eor PlotY
        eor LocalTick
        tay
        lda BitmapRingPattern,y
        sta TmpA
        lda PlotX
        eor #$18
        clc
        adc PlotY
        adc LocalTick
        tay
        lda MirrorRuneBitmap,y
        eor TmpA
        ora #$24
        sta BitmapByte
        rts
Pattern_Seal_Bright:
        lda LocalTick
        and #$08
        beq Pattern_Seal_BrightAlt
        lda #$ff
        sta BitmapByte
        rts
Pattern_Seal_BrightAlt:
        lda #$bd
        sta BitmapByte
        rts

;

TempleCellBars:
        !byte $00,$18,$3c,$7e,$ff,$7e,$3c,$18
TideWallBars:
        !byte $00,$00,$18,$18,$3c,$3c,$7e,$7e,$ff,$ff,$7e,$7e,$3c,$3c,$18,$18

BmpColLo:
        !byte <(0*8),<(1*8),<(2*8),<(3*8),<(4*8),<(5*8),<(6*8),<(7*8),<(8*8),<(9*8)
        !byte <(10*8),<(11*8),<(12*8),<(13*8),<(14*8),<(15*8),<(16*8),<(17*8),<(18*8),<(19*8)
        !byte <(20*8),<(21*8),<(22*8),<(23*8),<(24*8),<(25*8),<(26*8),<(27*8),<(28*8),<(29*8)
        !byte <(30*8),<(31*8),<(32*8),<(33*8),<(34*8),<(35*8),<(36*8),<(37*8),<(38*8),<(39*8)
BmpColHi:
        !byte >(0*8),>(1*8),>(2*8),>(3*8),>(4*8),>(5*8),>(6*8),>(7*8),>(8*8),>(9*8)
        !byte >(10*8),>(11*8),>(12*8),>(13*8),>(14*8),>(15*8),>(16*8),>(17*8),>(18*8),>(19*8)
        !byte >(20*8),>(21*8),>(22*8),>(23*8),>(24*8),>(25*8),>(26*8),>(27*8),>(28*8),>(29*8)
        !byte >(30*8),>(31*8),>(32*8),>(33*8),>(34*8),>(35*8),>(36*8),>(37*8),>(38*8),>(39*8)

BmpRowLo:
        !byte <(BITMAP_BASE+0*320),<(BITMAP_BASE+1*320),<(BITMAP_BASE+2*320),<(BITMAP_BASE+3*320),<(BITMAP_BASE+4*320)
        !byte <(BITMAP_BASE+5*320),<(BITMAP_BASE+6*320),<(BITMAP_BASE+7*320),<(BITMAP_BASE+8*320),<(BITMAP_BASE+9*320)
        !byte <(BITMAP_BASE+10*320),<(BITMAP_BASE+11*320),<(BITMAP_BASE+12*320),<(BITMAP_BASE+13*320),<(BITMAP_BASE+14*320)
        !byte <(BITMAP_BASE+15*320),<(BITMAP_BASE+16*320),<(BITMAP_BASE+17*320),<(BITMAP_BASE+18*320),<(BITMAP_BASE+19*320)
        !byte <(BITMAP_BASE+20*320),<(BITMAP_BASE+21*320),<(BITMAP_BASE+22*320),<(BITMAP_BASE+23*320),<(BITMAP_BASE+24*320)
BmpRowHi:
        !byte >(BITMAP_BASE+0*320),>(BITMAP_BASE+1*320),>(BITMAP_BASE+2*320),>(BITMAP_BASE+3*320),>(BITMAP_BASE+4*320)
        !byte >(BITMAP_BASE+5*320),>(BITMAP_BASE+6*320),>(BITMAP_BASE+7*320),>(BITMAP_BASE+8*320),>(BITMAP_BASE+9*320)
        !byte >(BITMAP_BASE+10*320),>(BITMAP_BASE+11*320),>(BITMAP_BASE+12*320),>(BITMAP_BASE+13*320),>(BITMAP_BASE+14*320)
        !byte >(BITMAP_BASE+15*320),>(BITMAP_BASE+16*320),>(BITMAP_BASE+17*320),>(BITMAP_BASE+18*320),>(BITMAP_BASE+19*320)
        !byte >(BITMAP_BASE+20*320),>(BITMAP_BASE+21*320),>(BITMAP_BASE+22*320),>(BITMAP_BASE+23*320),>(BITMAP_BASE+24*320)

BmpScrRowLo:
        !byte <(BITMAP_SCREEN+0*40),<(BITMAP_SCREEN+1*40),<(BITMAP_SCREEN+2*40),<(BITMAP_SCREEN+3*40),<(BITMAP_SCREEN+4*40)
        !byte <(BITMAP_SCREEN+5*40),<(BITMAP_SCREEN+6*40),<(BITMAP_SCREEN+7*40),<(BITMAP_SCREEN+8*40),<(BITMAP_SCREEN+9*40)
        !byte <(BITMAP_SCREEN+10*40),<(BITMAP_SCREEN+11*40),<(BITMAP_SCREEN+12*40),<(BITMAP_SCREEN+13*40),<(BITMAP_SCREEN+14*40)
        !byte <(BITMAP_SCREEN+15*40),<(BITMAP_SCREEN+16*40),<(BITMAP_SCREEN+17*40),<(BITMAP_SCREEN+18*40),<(BITMAP_SCREEN+19*40)
        !byte <(BITMAP_SCREEN+20*40),<(BITMAP_SCREEN+21*40),<(BITMAP_SCREEN+22*40),<(BITMAP_SCREEN+23*40),<(BITMAP_SCREEN+24*40)
BmpScrRowHi:
        !byte >(BITMAP_SCREEN+0*40),>(BITMAP_SCREEN+1*40),>(BITMAP_SCREEN+2*40),>(BITMAP_SCREEN+3*40),>(BITMAP_SCREEN+4*40)
        !byte >(BITMAP_SCREEN+5*40),>(BITMAP_SCREEN+6*40),>(BITMAP_SCREEN+7*40),>(BITMAP_SCREEN+8*40),>(BITMAP_SCREEN+9*40)
        !byte >(BITMAP_SCREEN+10*40),>(BITMAP_SCREEN+11*40),>(BITMAP_SCREEN+12*40),>(BITMAP_SCREEN+13*40),>(BITMAP_SCREEN+14*40)
        !byte >(BITMAP_SCREEN+15*40),>(BITMAP_SCREEN+16*40),>(BITMAP_SCREEN+17*40),>(BITMAP_SCREEN+18*40),>(BITMAP_SCREEN+19*40)
        !byte >(BITMAP_SCREEN+20*40),>(BITMAP_SCREEN+21*40),>(BITMAP_SCREEN+22*40),>(BITMAP_SCREEN+23*40),>(BITMAP_SCREEN+24*40)

; ================================================================
; Hyperoptimized true cracktro SID tick
; ================================================================
MusicTick:
        ; ATLANTIS GABBER: 50 Hz driver.
        ; 4 frames/row on PAL ~= 187.5 BPM 16th-note tracker grid.
        jsr MusicFrameFX
        inc MusicSub
        lda MusicSub
        and #$03                    ; 12.5 rows/sec ~= 187.5 BPM
        beq Music_Do
        rts
Music_Do:
        ldx MusicStep

        ; Voice 1: gated pulse/triangle bass.  Explicit gate-off before retrigger.
        lda #$40
        sta $d404
        lda BassLo,x
        cmp #$ff
        beq Music_NoBass
        sta $d400
        lda BassHi,x
        sta $d401
        lda #$08
        sta $d402
        lda #$08
        sta $d403
        lda DrumPat,x
        cmp #1
        beq Music_BassHard
        cmp #2
        beq Music_BassHard
        lda #$41                    ; gate + pulse bass
        bne Music_BassCtlGo
Music_BassHard:
        lda #$51                    ; gate + triangle+pulse for gabber thump rows
Music_BassCtlGo:
        sta $d404
Music_NoBass:

        ; Voice 2: cracktro arp/stab voice, pulse/saw alternation from LeadCtl.
        lda #$40
        sta $d40b
        lda LeadLo,x
        cmp #$ff
        beq Music_NoLead
        sta $d407
        lda LeadHi,x
        sta $d408
        lda LeadPwLo,x
        sta $d409
        lda LeadPwHi,x
        sta $d40a
        lda LeadCtl,x
        sta $d40b
Music_NoLead:

        ; Voice 3: K/k/clap/hat. Always gate-off first; zero pattern stays silent.
        lda #$80
        sta $d412
        lda #0
        sta DrumKind
        lda DrumPat,x
        bne MusicDispatch_NotSilent
        jmp Music_NoDrum
MusicDispatch_NotSilent:
        cmp #1
        bne MusicDispatch_NotKick
        jmp Music_Kick
MusicDispatch_NotKick:
        cmp #2
        bne MusicDispatch_NotGhost
        jmp Music_Ghost
MusicDispatch_NotGhost:
        cmp #3
        bne MusicDispatch_Hat
        jmp Music_Clap
MusicDispatch_Hat:
Music_Hat:
        lda #4
        sta DrumKind
        lda #$ff
        sta $d40e
        lda #$1f
        sta $d40f
        lda #$04
        sta $d413
        lda #$18
        sta $d414
        lda #$81                    ; short high noise hat
        jmp Music_DrumGo
Music_Clap:
        lda #3
        sta DrumKind
        lda #$18
        sta $d40e
        lda #$24
        sta $d40f
        lda #$08
        sta $d413
        lda #$a8
        sta $d414
        lda #$81                    ; noise gate clap
        jmp Music_DrumGo
Music_Kick:
        lda #1
        sta DrumKind
        lda #$14                    ; F# punch start
        sta $d40e
        lda #$03
        sta $d40f
        lda #$00
        sta $d413
        lda #$08
        sta $d414
        lda #$81                    ; noise click gate for distorted gabber attack
        jmp Music_DrumGo
Music_Ghost:
        lda #2
        sta DrumKind
        lda #$8a                    ; ghost/pitch-drop tail
        sta $d40e
        lda #$01
        sta $d40f
        lda #$00
        sta $d413
        lda #$08
        sta $d414
        lda #$11                    ; triangle tail
Music_DrumGo:
        sta $d412
Music_NoDrum:
        lda FilterCutHi,x
        sta $d416
        lda FilterRes,x
        sta $d417
        inx
        txa
        and #$3f
        sta MusicStep
        rts

; release active effect table: 25-part bitmap-only renderer pipeline.
; 0 FX00 WarpGrid, 1 FX01 GateRunner, 2 FX02 Starfield, 3 FX03 Plasma,
; 4 FX04 Lightning, 5 FX05 HyperWarp, 6 FX06 FireIce, 7 FX07 TempleBars,
; 8 FX08 SonarRings, 9 FX09 MirrorRune, 10 FX10 SineCity, 11 FX11 AtlantisCore,
; 12 FX12 FinalSwitch, 13 FX13 DeepSeaVortex, 14 FX14 TempleCircuit, 15 FX15 FinalBloom,
; 16 FX16 TridentSweep, 17 FX17 AbyssGrid, 18 FX18 PressureRunes, 19 FX19 MegaBloom, 20 FX20 DeepLattice, 21 FX21 KrakenPulse, 22 FX22 TideWall, 23 FX23 SunkenFinale, 24 FX24 Seal.
InitLo: !fill NUM_PARTS,<PartInit
InitHi: !fill NUM_PARTS,>PartInit
UpdLo:  !byte <FX00_Update,<FX01_Update,<FX02_Update,<FX03_Update,<FX04_Update,<FX05_Update,<FX06_Update,<FX07_Update,<FX08_Update,<FX09_Update,<FX10_Update,<FX11_Update,<FX12_Update,<FX13_Update,<FX14_Update,<FX15_Update,<FX16_Update,<FX17_Update,<FX18_Update,<FX19_Update,<FX20_Update,<FX21_Update,<FX22_Update,<FX23_Update,<FX24_Update
UpdHi:  !byte >FX00_Update,>FX01_Update,>FX02_Update,>FX03_Update,>FX04_Update,>FX05_Update,>FX06_Update,>FX07_Update,>FX08_Update,>FX09_Update,>FX10_Update,>FX11_Update,>FX12_Update,>FX13_Update,>FX14_Update,>FX15_Update,>FX16_Update,>FX17_Update,>FX18_Update,>FX19_Update,>FX20_Update,>FX21_Update,>FX22_Update,>FX23_Update,>FX24_Update
DurLo:  !byte <500,<500,<460,<540,<500,<480,<480,<500,<500,<500,<500,<400,<400,<500,<500,<560,<500,<500,<520,<620,<520,<520,<540,<700,<760
DurHi:  !byte >500,>500,>460,>540,>500,>480,>480,>500,>500,>500,>500,>400,>400,>500,>500,>560,>500,>500,>520,>620,>520,>520,>540,>700,>760
; music starts aligned to 25 bitmap parts.  Atlantis music tables unchanged.
MusicStart: !byte $30,$00,$10,$20,$30,$28,$38,$08,$18,$28,$38,$00,$20,$10,$30,$00,$18,$28,$38,$00,$10,$20,$30,$00,$30

; bitmap-only effect pattern helpers.
RasterBitmapBars:
        !byte $00,$00,$18,$18,$3c,$3c,$7e,$7e,$ff,$ff,$7e,$7e,$3c,$3c,$18,$18
        !byte $00,$24,$24,$66,$66,$e7,$e7,$ff,$ff,$e7,$e7,$66,$66,$24,$24,$00
MirrorRuneBitmap:
        !byte $81,$42,$24,$18,$18,$24,$42,$81,$c3,$66,$3c,$18,$18,$3c,$66,$c3
        !byte $99,$5a,$3c,$24,$24,$3c,$5a,$99,$ff,$81,$bd,$a5,$a5,$bd,$81,$ff
        !byte $18,$3c,$7e,$db,$db,$7e,$3c,$18,$42,$66,$7e,$5a,$5a,$7e,$66,$42
        !byte $24,$66,$e7,$ff,$ff,$e7,$66,$24,$00,$18,$3c,$7e,$7e,$3c,$18,$00
SineCityBitmapBars:
        !byte $80,$c0,$e0,$f0,$f8,$fc,$fe,$ff,$ff,$7f,$3f,$1f,$0f,$07,$03,$01

; ================================================================
; State variables
; ================================================================
Part        !byte 0
TimerLo     !byte 0
TimerHi     !byte 0
Frame       !byte 0
FrameReady  !byte 0
LocalTick   !byte 0
MusicStep   !byte 0
MusicSub    !byte 0
DrumKind    !byte 0        ; current V3 transient type for frame pitch/drop
SkipLatch   !byte 0
PlotX       !byte 0
PlotY       !byte 0
PlotChar    !byte 0
PlotColor   !byte 0
LineX1      !byte 0
LineX2      !byte 0
LineY       !byte 0
LineY1      !byte 0
LineY2      !byte 0
LineChar    !byte 0
LineColor   !byte 0
RectL       !byte 0
RectR       !byte 0
RectT       !byte 0
RectB       !byte 0
ClearRow    !byte 0
GatePhase   !byte 0
EffectIndex !byte 0
WGCol       !byte 0
StarIndex   !byte 0
Count       !byte 0
BitmapByte  !byte 0        ; Bitmap pattern scratch byte.
Phase       !byte 0        ; Four-phase row/column selector.
StarX       !fill 32,0
StarY       !fill 32,0
StarSpeed   !fill 32,1
StarColor   !fill 32,1

; ================================================================
; Data tables from/adapted from uploaded source material
; ================================================================
BM_Title: !scr "bitmap bank2 hires bitmap plasma"
BM_TitleLen = *-BM_Title
BS_Title: !scr "bitmap live bitmap bank switch"
BS_TitleLen = *-BS_Title
PL_Title: !scr "quantum plasma / deepseek palette"
PL_TitleLen = *-PL_Title
NE_Title: !scr "neon lightning / moire source"
NE_TitleLen = *-NE_Title
HF_Title: !scr "hyper warp field / quantum source"
HF_TitleLen = *-HF_Title
FI_Title: !scr "fire ice moire / palette source"
FI_TitleLen = *-FI_Title
RT_Title: !scr "raster temple bars"
RT_TitleLen = *-RT_Title
OD_Title: !scr "ocean depth sonar rings"
OD_TitleLen = *-OD_Title
MR_Title: !scr "mirror rune tunnel"
MR_TitleLen = *-MR_Title
SC_Title: !scr "sine city scanner"
SC_TitleLen = *-SC_Title
RowLo:
        !byte <(SCREEN+0*40),<(SCREEN+1*40),<(SCREEN+2*40),<(SCREEN+3*40),<(SCREEN+4*40)
        !byte <(SCREEN+5*40),<(SCREEN+6*40),<(SCREEN+7*40),<(SCREEN+8*40),<(SCREEN+9*40)
        !byte <(SCREEN+10*40),<(SCREEN+11*40),<(SCREEN+12*40),<(SCREEN+13*40),<(SCREEN+14*40)
        !byte <(SCREEN+15*40),<(SCREEN+16*40),<(SCREEN+17*40),<(SCREEN+18*40),<(SCREEN+19*40)
        !byte <(SCREEN+20*40),<(SCREEN+21*40),<(SCREEN+22*40),<(SCREEN+23*40),<(SCREEN+24*40)
RowHi:
        !byte >(SCREEN+0*40),>(SCREEN+1*40),>(SCREEN+2*40),>(SCREEN+3*40),>(SCREEN+4*40)
        !byte >(SCREEN+5*40),>(SCREEN+6*40),>(SCREEN+7*40),>(SCREEN+8*40),>(SCREEN+9*40)
        !byte >(SCREEN+10*40),>(SCREEN+11*40),>(SCREEN+12*40),>(SCREEN+13*40),>(SCREEN+14*40)
        !byte >(SCREEN+15*40),>(SCREEN+16*40),>(SCREEN+17*40),>(SCREEN+18*40),>(SCREEN+19*40)
        !byte >(SCREEN+20*40),>(SCREEN+21*40),>(SCREEN+22*40),>(SCREEN+23*40),>(SCREEN+24*40)
CRowLo:
        !byte <(COLOR+0*40),<(COLOR+1*40),<(COLOR+2*40),<(COLOR+3*40),<(COLOR+4*40)
        !byte <(COLOR+5*40),<(COLOR+6*40),<(COLOR+7*40),<(COLOR+8*40),<(COLOR+9*40)
        !byte <(COLOR+10*40),<(COLOR+11*40),<(COLOR+12*40),<(COLOR+13*40),<(COLOR+14*40)
        !byte <(COLOR+15*40),<(COLOR+16*40),<(COLOR+17*40),<(COLOR+18*40),<(COLOR+19*40)
        !byte <(COLOR+20*40),<(COLOR+21*40),<(COLOR+22*40),<(COLOR+23*40),<(COLOR+24*40)
CRowHi:
        !byte >(COLOR+0*40),>(COLOR+1*40),>(COLOR+2*40),>(COLOR+3*40),>(COLOR+4*40)
        !byte >(COLOR+5*40),>(COLOR+6*40),>(COLOR+7*40),>(COLOR+8*40),>(COLOR+9*40)
        !byte >(COLOR+10*40),>(COLOR+11*40),>(COLOR+12*40),>(COLOR+13*40),>(COLOR+14*40)
        !byte >(COLOR+15*40),>(COLOR+16*40),>(COLOR+17*40),>(COLOR+18*40),>(COLOR+19*40)
        !byte >(COLOR+20*40),>(COLOR+21*40),>(COLOR+22*40),>(COLOR+23*40),>(COLOR+24*40)

ScaleTable:
        !byte 8,8,7,7,6,6,5,5,4,4,3,3,2,2,1,1,1,1,1,1,1,1,1,1,1
RowBase1:
        !byte 0,1,3,6,10,15,21,28,36,45,55,66,78,91,105,120,136,153,171,190,210,231,253,20,48
WidthTable:
        !byte 2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,12,13,14,15,16,17,18
VolumetricPalette:
        !byte $00,$00,$00,$00,$06,$06,$06,$06,$0e,$0e,$0e,$0e,$03,$03,$03,$03
        !byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
ColWarp1:
        !byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        !byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
ColWarp2:
        !byte 0,0,0,0,0,0,0,0,0,0,1,1,2,2,2,3,3,3,3,3
        !byte 0,253,253,252,252,252,253,253,255,0,0,0,0,0,0,0,0,0,0,0
ColWarp3:
        !byte 0,0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,6,6,6
        !byte 0,250,250,250,250,250,250,251,251,252,253,254,254,255,255,0,0,0,0,0
ColWarp4:
        !byte 0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,13,13,13,13,13
        !byte 0,243,243,243,243,243,243,244,245,246,247,248,249,250,251,252,253,254,255,0
WarpTableLo: !byte <ColWarp1,<ColWarp2,<ColWarp3,<ColWarp4
WarpTableHi: !byte >ColWarp1,>ColWarp2,>ColWarp3,>ColWarp4

CorridorW: !byte 2,4,6,9,12,15,18
CorridorH: !byte 1,2,3,5,7,9,10
CorridorColor: !byte $0b,$0c,$0f,$01,$0f,$0c,$0b
TunnelRowColor:
        !byte $00,$00,$0b,$0b,$0c,$0c,$0f,$0f,$01,$01,$0f,$0f,$0c,$0c,$0b,$0b,$06,$06,$0e,$0e,$03,$03,$01,$01,$00
BR_X1: !byte 4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
BR_Y1: !byte 20,19,18,17,16,15,14,13,12,11,10,9,8,7,6,5
BR_X2: !byte 20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35
BR_Y2: !byte 5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20

LogoColors: !byte $00,$06,$0b,$0c,$0f,$01,$0f,$0c,$0b,$06,$03,$0e,$03,$06,$0b,$00
NeonColors16: !byte $00,$05,$0d,$03,$0b,$0c,$0f,$01,$0f,$0c,$0b,$03,$0d,$05,$06,$00
QuantumColors16:
        !byte $00,$0b,$0c,$0f,$01,$0f,$0c,$0b,$03,$0d,$07,$05,$07,$0d,$03,$00
LightningX: !byte 14,17,13,18,15,20,16,21,17,19,14,22,16,20,12,18,15,21,13,19,16,22,14,18,15
StarXInit: !byte 2,8,14,20,26,32,38,5,11,17,23,29,35,3,9,15,21,27,33,39,6,12,18,24,30,36,4,10,16,22,28,34
StarYInit: !byte 4,6,8,10,12,14,16,18,20,22,5,7,9,11,13,15,17,19,21,23,3,5,7,9,11,13,15,17,19,21,23,6
StarSpeedInit: !byte 1,2,1,3,1,2,1,3,1,2,1,3,1,2,1,3,1,2,1,3,1,2,1,3,1,2,1,3,1,2,1,3
StarColorInit: !byte 1,1,7,7,1,1,7,7,1,1,7,7,1,1,7,7,1,1,7,7,1,1,7,7,1,1,7,7,1,1,7,7

FireIceColors16:
        !byte $00,$09,$02,$08,$0a,$07,$0f,$01,$0f,$07,$0a,$08,$02,$09,$0b,$00
FireIceChars16:
        !byte G_SPACE,G_DOT,G_SHADE1,G_SHADE1,G_SHADE2,G_SHADE2,G_PLUS,G_DIAMOND
        !byte G_BLOCK,G_DIAMOND,G_PLUS,G_SHADE2,G_SHADE1,G_DOT,G_SPACE,G_DOT

RT_CharTable:
        !byte G_HLINE,G_SHADE1,G_SHADE2,G_BLOCK
SineCityHeight16:
        !byte 2,4,6,8,10,12,14,11,9,7,5,3,6,10,13,7

; ATLANTIS GABBER / SUNKEN TEMPLE HARDCORE music tables
; 64 rows, F# minor/Phrygian color: F# G A B C# D E.
; Voice 1 bass/kick hybrid, Voice 2 Atlantis lead, Voice 3 K/k/clap/hat transient.
; Rebuilt for harder gabber punch while keeping the same theme/chords/hook.
BassLo:
        !byte $14,$ff,$27,$ff,$14,$ff,$42,$14,$14,$ff,$27,$ff,$14,$ff,$42,$14
        !byte $71,$ff,$e2,$ff,$71,$ff,$be,$71,$a9,$ff,$51,$ff,$a9,$ff,$1b,$a9
        !byte $be,$ff,$7b,$ff,$be,$ff,$42,$be,$14,$ff,$27,$ff,$14,$ff,$42,$14
        !byte $71,$ff,$e2,$ff,$71,$ff,$be,$71,$14,$ff,$27,$ff,$14,$ff,$42,$14
BassHi:
        !byte $03,$00,$06,$00,$03,$00,$03,$03,$03,$00,$06,$00,$03,$00,$03,$03
        !byte $02,$00,$04,$00,$02,$00,$02,$02,$03,$00,$07,$00,$03,$00,$04,$03
        !byte $02,$00,$05,$00,$02,$00,$03,$02,$03,$00,$06,$00,$03,$00,$03,$03
        !byte $02,$00,$04,$00,$02,$00,$02,$02,$03,$00,$06,$00,$03,$00,$03,$03
LeadLo:
        !byte $9c,$ff,$e0,$ff,$da,$11,$e0,$45,$9c,$ff,$45,$ff,$e0,$da,$39,$da
        !byte $11,$ff,$e0,$ff,$45,$13,$9c,$13,$da,$ff,$11,$ff,$e0,$da,$45,$13
        !byte $9c,$ff,$e0,$ff,$da,$11,$e0,$da,$45,$ff,$13,$ff,$9c,$13,$45,$e0
        !byte $da,$ff,$11,$ff,$e0,$da,$45,$13,$9c,$ff,$9c,$ff,$39,$da,$e0,$9c
LeadHi:
        !byte $18,$00,$24,$00,$2b,$27,$24,$1d,$18,$00,$1d,$00,$24,$2b,$31,$2b
        !byte $27,$00,$24,$00,$1d,$1a,$18,$1a,$2b,$00,$27,$00,$24,$20,$1d,$1a
        !byte $18,$00,$24,$00,$2b,$27,$24,$20,$1d,$00,$1a,$00,$18,$1a,$1d,$24
        !byte $2b,$00,$27,$00,$24,$20,$1d,$1a,$18,$00,$18,$00,$31,$2b,$24,$18
LeadCtl:
        !byte $21,$40,$41,$40,$21,$41,$41,$41,$21,$40,$41,$40,$21,$41,$41,$41
        !byte $21,$40,$41,$40,$21,$41,$41,$41,$21,$40,$41,$40,$21,$41,$41,$41
        !byte $21,$40,$41,$40,$21,$41,$41,$41,$21,$40,$41,$40,$21,$41,$41,$41
        !byte $21,$40,$41,$40,$21,$41,$41,$41,$21,$40,$41,$40,$21,$41,$41,$41
LeadPwLo:
        !byte $80,$2e,$d6,$71,$f9,$68,$bb,$ee,$00,$ee,$bb,$68,$f9,$71,$d6,$2e
        !byte $80,$d1,$29,$8e,$06,$97,$44,$11,$00,$11,$44,$97,$06,$8e,$29,$d1
        !byte $7f,$2e,$d6,$71,$f9,$68,$bb,$ee,$00,$ee,$bb,$68,$f9,$71,$d6,$2e
        !byte $80,$d1,$29,$8e,$06,$97,$44,$11,$00,$11,$44,$97,$06,$8e,$29,$d1
LeadPwHi:
        !byte $07,$08,$08,$09,$09,$0a,$0a,$0a,$0b,$0a,$0a,$0a,$09,$09,$08,$08
        !byte $07,$06,$06,$05,$05,$04,$04,$04,$04,$04,$04,$04,$05,$05,$06,$06
        !byte $07,$08,$08,$09,$09,$0a,$0a,$0a,$0b,$0a,$0a,$0a,$09,$09,$08,$08
        !byte $07,$06,$06,$05,$05,$04,$04,$04,$04,$04,$04,$04,$05,$05,$06,$06
DrumPat:
        ; K . hat . K . ghost . clap . hat . K . ghost
        ; 1=main kick, 2=ghost/pitch-drop, 3=clap layer, 4=hat
        !byte 1,0,4,0,1,0,2,0,3,0,4,0,1,0,2,0
        !byte 1,0,4,0,1,0,2,0,3,0,4,0,1,0,2,0
        !byte 1,0,4,0,1,0,2,0,3,0,4,0,1,0,2,0
        !byte 1,0,4,0,1,0,2,0,3,0,4,0,1,0,2,0
FilterCutHi:
        !byte $18,$20,$28,$32,$3c,$48,$56,$64,$72,$84,$98,$b0,$cc,$e0,$f4,$d8
        !byte $18,$20,$28,$32,$3c,$48,$56,$64,$72,$84,$98,$b0,$cc,$e0,$f4,$d8
        !byte $18,$20,$28,$32,$3c,$48,$56,$64,$72,$84,$98,$b0,$cc,$e0,$f4,$d8
        !byte $18,$20,$28,$32,$3c,$48,$56,$64,$72,$84,$98,$b0,$cc,$e0,$f4,$d8
FilterRes:
        !byte $f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3,$f3
        !byte $e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3,$e3
        !byte $d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3,$d3
        !byte $c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3,$c3
;

KickDropLo:
        !byte $14,$8a,$42,$14
KickDropHi:
        !byte $03,$02,$01,$01
KickDropCtl:
        !byte $81,$91,$11,$10
GhostDropLo:
        !byte $8a,$42,$21,$10
GhostDropHi:
        !byte $01,$01,$01,$01
GhostDropCtl:
        !byte $11,$11,$10,$10

BitmapColorNibbles:
        !byte $10,$30,$60,$e0,$f0,$70,$10,$f0,$e0,$60,$30,$10,$b0,$c0,$f0,$10

BitmapPattern:
        !byte $00,$18,$3c,$7e,$ff,$7e,$3c,$18,$00,$81,$42,$24,$18,$24,$42,$81
        !byte $11,$33,$77,$ff,$ee,$cc,$88,$00,$88,$cc,$ee,$ff,$77,$33,$11,$00
        !byte $0f,$1e,$3c,$78,$f0,$e1,$c3,$87,$0f,$87,$c3,$e1,$f0,$78,$3c,$1e
        !byte $55,$aa,$55,$aa,$99,$66,$99,$66,$f0,$0f,$f0,$0f,$cc,$33,$cc,$33
        !byte $00,$01,$03,$07,$0f,$1f,$3f,$7f,$ff,$7f,$3f,$1f,$0f,$07,$03,$01
        !byte $80,$c0,$e0,$f0,$f8,$fc,$fe,$ff,$fe,$fc,$f8,$f0,$e0,$c0,$80,$00
        !byte $18,$18,$3c,$3c,$7e,$7e,$ff,$ff,$e7,$c3,$81,$00,$81,$c3,$e7,$ff
        !byte $24,$66,$ff,$66,$24,$00,$24,$66,$ff,$66,$24,$00,$3c,$42,$81,$42
        !byte $00,$18,$3c,$7e,$ff,$7e,$3c,$18,$00,$81,$42,$24,$18,$24,$42,$81
        !byte $11,$33,$77,$ff,$ee,$cc,$88,$00,$88,$cc,$ee,$ff,$77,$33,$11,$00
        !byte $0f,$1e,$3c,$78,$f0,$e1,$c3,$87,$0f,$87,$c3,$e1,$f0,$78,$3c,$1e
        !byte $55,$aa,$55,$aa,$99,$66,$99,$66,$f0,$0f,$f0,$0f,$cc,$33,$cc,$33
        !byte $00,$01,$03,$07,$0f,$1f,$3f,$7f,$ff,$7f,$3f,$1f,$0f,$07,$03,$01
        !byte $80,$c0,$e0,$f0,$f8,$fc,$fe,$ff,$fe,$fc,$f8,$f0,$e0,$c0,$80,$00
        !byte $18,$18,$3c,$3c,$7e,$7e,$ff,$ff,$e7,$c3,$81,$00,$81,$c3,$e7,$ff
        !byte $24,$66,$ff,$66,$24,$00,$24,$66,$ff,$66,$24,$00,$3c,$42,$81,$42
BitmapRingPattern:
        !byte $00,$00,$18,$18,$3c,$3c,$7e,$7e,$ff,$ff,$7e,$7e,$3c,$3c,$18,$18
        !byte $81,$c3,$e7,$ff,$7e,$3c,$18,$00,$18,$3c,$7e,$ff,$e7,$c3,$81,$00
        !byte $aa,$55,$aa,$55,$cc,$33,$cc,$33,$f0,$0f,$f0,$0f,$99,$66,$99,$66
        !byte $0f,$0f,$1f,$1f,$3f,$3f,$7f,$7f,$ff,$ff,$fe,$fe,$fc,$fc,$f8,$f8
        !byte $00,$00,$18,$18,$3c,$3c,$7e,$7e,$ff,$ff,$7e,$7e,$3c,$3c,$18,$18
        !byte $81,$c3,$e7,$ff,$7e,$3c,$18,$00,$18,$3c,$7e,$ff,$e7,$c3,$81,$00
        !byte $aa,$55,$aa,$55,$cc,$33,$cc,$33,$f0,$0f,$f0,$0f,$99,$66,$99,$66
        !byte $0f,$0f,$1f,$1f,$3f,$3f,$7f,$7f,$ff,$ff,$fe,$fe,$fc,$fc,$f8,$f8
        !byte $00,$00,$18,$18,$3c,$3c,$7e,$7e,$ff,$ff,$7e,$7e,$3c,$3c,$18,$18
        !byte $81,$c3,$e7,$ff,$7e,$3c,$18,$00,$18,$3c,$7e,$ff,$e7,$c3,$81,$00
        !byte $aa,$55,$aa,$55,$cc,$33,$cc,$33,$f0,$0f,$f0,$0f,$99,$66,$99,$66
        !byte $0f,$0f,$1f,$1f,$3f,$3f,$7f,$7f,$ff,$ff,$fe,$fe,$fc,$fc,$f8,$f8
        !byte $00,$00,$18,$18,$3c,$3c,$7e,$7e,$ff,$ff,$7e,$7e,$3c,$3c,$18,$18
        !byte $81,$c3,$e7,$ff,$7e,$3c,$18,$00,$18,$3c,$7e,$ff,$e7,$c3,$81,$00
        !byte $aa,$55,$aa,$55,$cc,$33,$cc,$33,$f0,$0f,$f0,$0f,$99,$66,$99,$66
        !byte $0f,$0f,$1f,$1f,$3f,$3f,$7f,$7f,$ff,$ff,$fe,$fe,$fc,$fc,$f8,$f8

;
