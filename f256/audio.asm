; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .cpu        "65c02"
        
        .namespace  platform
audio   .namespace        

        .section    dp
mixer   .byte       ?
        .send
        
        .section    kernel        

PORT = $D600

wm8776  .hardware.wm8776    $D620

init: 

.if true
        jmp qnd
.else        
        php
        sei
        stz     $1
        jsr     pjw_codec.INIT_CODEC
        jsr     pjw_sid.start
        ;jsr     pjw_psg.start
        plp
        rts
.endif

        jsr     init_sid
        jmp     init_psg

        jsr     init_mixer

        lda     #kernel.device.set.CH_ENABLE
        ldy     #1
        jsr     kernel.device.dev.set
        jsr     init_psg
        rts

init_psg

    lda #%1_00_1_1111
    sta PORT
    lda #%1_01_1_1111
    sta PORT
    lda #%1_10_1_1111
    sta PORT
    lda #%1_11_1_1111
    sta PORT
    rts

        lda     #%1_010_0000    ; 2nd osc. freq + upper frque bits
        sta     PORT
        lda     #%0_0010011      ; lower freq bits
        sta     PORT
        lda     #%1_011_0000    ; 2nd osc. attn + mid level
        sta     PORT
        clc
        rts
        
.if false
 0 REM *** C64-WIKI SOUND-DEMO ***
10 S = 54272: W = 17: ON INT(RND(TI)*4)+1 GOTO 12,13,14,15
12 W = 33: GOTO 15
13 W = 65: GOTO 15
14 W = 129
15 POKE S+24,15: POKE S+5,97: POKE S+6,200: POKE S+4,W
16 FOR X = 0 TO 255 STEP (RND(TI)*15)+1
17 POKE S,X :POKE S+1,255-X
18 FOR Y = 0 TO 33: NEXT Y,X
19 FOR X = 0 TO 200: NEXT: POKE S+24,0
20 FOR X = 0 TO 100: NEXT: GOTO 10
21 REM *** ABORT ONLY WITH RUN/STOP ! ***
.endif

SID = $D500

init_sid
    lda #15
    sta SID+24
    lda #97
    sta SID+5
    lda #200
    sta SID+6

    lda #65
    sta SID+4

    lda #120
    sta SID
    lda #135
    sta SID+1
    rts


init_mixer:
        jsr     wm8776.init
        bcs     _out
        stx     mixer

        inc     kernel.thread.lock  ; Token 0 is available and not thread safe

        ldy     #0
_loop   
        cmp     #_ilen
        beq     _done
        
        lda     _itab+1,y    ; high bits
        sta     kernel.token.entry.data+1   ; Token 0
        lda     _itab+0,y    ; low bits
        sta     kernel.token.entry.data+0   ; Token 0

        phy
        ldy     #0  ; Token 0
        lda     #kernel.device.set.REGISTER
        jsr     kernel.device.dev.set
        ply

        iny
        iny
        bra     _loop
_done   dec     kernel.thread.lock
_out    rts

_itab   
        .word   %0001101_000000000  ; $0d: enable headphones
        .word   %0010001_100000001  ; $11: ALC2; AGC 2.67ms
        .word   %0001010_000000010  ; $0a: DAC: 16 bit I2S mode
        .word   %0001011_000000010  ; $0b: ADC: 16 bit I2S mode
        .word   %0001100_001000101  ; $0c: ADC Master: 256fs, DAC Master 256fs
_ilen   = * - _itab        


qnd
INIT_CODEC 
    ; Sorry this is a little sloppy.  At the time, I was going in circles 
    ; only to eventually find that my board had a hardware problem...
    ; Might be nice to clean up the mess someday.  Until then, here's
    ; where we're doing the init...
    
            stz  $1

            ;                LDA #%00011010_00000000     ;R13 - Turn On Headphones
            lda #%00000000
            sta CODEC_LOW
            lda #%00011010
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH
            ; LDA #%0010101000000011       ;R21 - Enable All the Analog In
            jsr lines_for_board
            sta CODEC_LOW
            lda #%00101010
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH
            ; LDA #%0010001100000001      ;R17 - Enable All the Analog In
            lda #%00000001
            sta CODEC_LOW
            lda #%00100011
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH
            ;   LDA #%0010110000000111      ;R22 - Enable all Analog Out
            lda #%00000111
            sta CODEC_LOW
            lda #%00101100
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH
            ; LDA #%0001010000000010      ;R10 - DAC Interface Control
            lda #%00000010
            sta CODEC_LOW
            lda #%00010100
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH
            ; LDA #%0001011000000010      ;R11 - ADC Interface Control
            lda #%00000010
            sta CODEC_LOW
            lda #%00010110
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH
            ; LDA #%0001100111010101      ;R12 - Master Mode Control
            lda #%01000101
            sta CODEC_LOW
            lda #%00011000
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH
            rts
            
CODEC_WAIT_FINISH
CODEC_Not_Finished:
            lda CODEC_CTRL
            and #$01
            cmp #$01
            beq CODEC_Not_Finished
            rts

CODEC_LOW        = $D620
CODEC_HI         = $D621
CODEC_CTRL       = $D622

lines_for_board
    ; OUT:  A = aux input bits for the identified board.

            phx
            jsr     get_board
            lda     boards.codec_init,x
            plx

            bcc +
            lda     #1  ; minimal safe input.
            clc
          + rts


pjw_psg     .namespace

psg_l = $D600
psg_r = $D610

start:      ldy #0

            ; Get the note to play
loop:       lda score,y

            ; If we're at the end of the score, we're done
            bne playnote
done:       rts
            bra done

            ; Find the frequency for the note
playnote:   sec                     ; Convert the note character to an index
            sbc #'A'                ; Into the frequency table
            tax

            lda frequency,x         ; Get the low 4 bits of the frequency
            and #$0f
            ora #$80
            sta psg_l
            sta psg_r

            lda frequency,x         ; Get the upper bits of the frequency
            lsr a
            lsr a
            lsr a
            lsr a
            and #$3f
            sta psg_l
            sta psg_r

            ; Start playing the note
            lda #$90
            sta psg_l
            sta psg_r

            ; Wait for the length of the note (1/2 second)
            ldx #3
            jsr wait_tens

            ; Stop playing the note
            lda #$9f
            sta psg_l
            sta psg_r

            ; Wait for the pause between notes (1/5 second)
            ldx #3
            jsr wait_tens

            ; Try the next note
            iny
            bra loop

;
; Wait for about 1ms
;
wait_1ms:   phx
            phy

            ; Inner loop is 6 clocks per iteration or 1us
            ; Run the inner loop ~1000 times for 1ms

            ldx #3
wait_outr:  ldy #$ff
wait_inner: nop
            dey
            bne wait_inner
            dex
            bne wait_outr

            ply
            plx
            rts

;
; Wait for 100ms
;
wait_100ms: phx
            ldx #100
wait100l:   jsr wait_1ms
            dex
            bne wait100l
            plx
            rts

;
; Wait for some 10ths of seconds
;
; X = number of 10ths of a second to wait
;
wait_tens:  jsr wait_100ms
            dex
            bne wait_tens
            rts
;
; Assignment of notes to frequency
; NOTE: in general, this table should support 10-bit values
;       we're using just one octave here, so we can get away with bytes
;       PSG system clock is 3.57MHz
;
frequency:  .byte 127   ; A (Concert A)
            .byte 113   ; B
            .byte 212   ; C
            .byte 190   ; D
            .byte 169   ; E
            .byte 159   ; F
            .byte 142   ; G

;
; The notes to play
;
score:      .text "CCGGAAG"
            .text "FFEEDDC"
            .text "GGFFEED"
            .text "GGFFEED"
            .text "CCGGAAG"
            .text "FFEEDDC",0

            .endn

pjw_codec     .namespace

CODEC_LOW        = $D620
CODEC_HI         = $D621
CODEC_CTRL       = $D622

INIT_CODEC
            ;                LDA #%00011010_00000000     ;R13 - Turn On Headphones
            lda #%00000000
            sta CODEC_LOW
            lda #%00011010
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH

            ; LDA #%0010101000000011       ;R21 - Enable All the Analog In
            lda #%00000011
            sta CODEC_LOW
            lda #%00101010
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH

            ; LDA #%0010001100000001      ;R17 - Enable All the Analog In
            lda #%00000001
            sta CODEC_LOW
            lda #%00100011
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH

            ;   LDA #%0010110000000111      ;R22 - Enable all Analog Out
            lda #%00000111
            sta CODEC_LOW
            lda #%00101100
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH

            ; LDA #%0001010000000010      ;R10 - DAC Interface Control
            lda #%00000010
            sta CODEC_LOW
            lda #%00010100
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH

            ; LDA #%0001011000000010      ;R11 - ADC Interface Control
            lda #%00000010
            sta CODEC_LOW
            lda #%00010110
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH

            ; LDA #%0001100111010101      ;R12 - Master Mode Control
            lda #%01000101
            sta CODEC_LOW
            lda #%00011000
            sta CODEC_HI
            lda #$01
            sta CODEC_CTRL ;
            jsr CODEC_WAIT_FINISH
            rts

CODEC_WAIT_FINISH
CODEC_Not_Finished:
            lda CODEC_CTRL
            and #$01
            cmp #$01
            beq CODEC_Not_Finished
            rts
            
            .endn

pjw_sid     .namespace

SID_LEFT = $D400        ; Location of the first register for the left SID chip
SID_RIGHT = $D500       ; Location of the first register for the right SID chip

;
; Frequencies. SID system clock is 1.022714 MHz
;
NOTE_A = 7218           ; Concert A = 440Hz


start:
;
; Turn everything off on the SIDs
;

            ldx #0
            lda #0
clr_loop:   sta SID_LEFT,x
            sta SID_RIGHT,x
            inx
            cpx #25
            bne clr_loop

;
; Set the SID volume
;

            lda #15
            sta SID_LEFT+24
            sta SID_RIGHT+24

;
; Define the ADSR envelope
;

            lda #$87            ; Attack = 8 (0.1s), Decay = 7 (80ms)
            sta SID_LEFT+5
            sta SID_RIGHT+5

            lda #$8C            ; Sustain = 15, Release = 12 (3s)
            sta SID_LEFT+6
            sta SID_RIGHT+6

;
; Set the frequency, concert A = 440Hz, n = 7217
;

            lda #<NOTE_A
            sta SID_LEFT+0
            sta SID_RIGHT+0
            lda #>NOTE_A
            sta SID_LEFT+1
            sta SID_RIGHT+1

;
; Play the note by turning on the GATE
;

            lda #$11            ; GATE + TRIANGLE
            sta SID_LEFT+4
            sta SID_RIGHT+4

;
; Wait 1 second
;

            ldx #10
            jsr wait_tens

;
; Release the note
;

            stz SID_LEFT+4
            stz SID_RIGHT+4
 rts
;
; Wait forever
;

loop:       nop
            bra loop


;
; Wait for about 1ms
;
wait_1ms:   phx
            phy

            ; Inner loop is 6 clocks per iteration or 1us
            ; Run the inner loop ~1000 times for 1ms

            ldx #3
wait_outr:  ldy #$ff
wait_inner: nop
            dey
            bne wait_inner
            dex
            bne wait_outr

            ply
            plx
            rts

;
; Wait for 100ms
;
wait_100ms: phx
            ldx #100
wait100l:   jsr wait_1ms
            dex
            bne wait100l
            plx
            rts

;
; Wait for some 10ths of seconds
;
; X = number of 10ths of a second to wait
;
wait_tens:  jsr wait_100ms
            dex
            bne wait_tens
            rts

            .endn

        .send
        .endn
        .endn

