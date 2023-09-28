; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

        .PC02
        .include "fat32.inc"

        .export fat_test
        .export print, print_space, print_hex_byte
 
        .import sdcard_init
        .import skip_mask

        .import fat32_ptr       : zeropage
        .import fat32_ptr2      : zeropage
        .import fat32_bufptr    : zeropage

        .segment    "ZEROPAGE" : zeropage
screen: .res    2
used:   .res    1

        .code

        .byte   $fa, $32
        .word   fat32_dirent
        .word   fat32_size

        jmp     fat_test; fat32_init
        
        jmp     get_error
        jmp     get_size
        jmp     set_size
        jmp     set_ptr
        jmp     set_ptr2
        jmp     set_time

        jmp     fat32_alloc_context
        jmp     fat32_set_context
        jmp     fat32_free_context

        jmp     my_mkfs

        jmp     fat32_open
        jmp     fat32_create
        jmp     fat32_read
        jmp     fat32_write
        jmp     fat32_write_byte
        jmp     seek
        jmp     fat32_close

        jmp     fat32_rename
        jmp     fat32_delete

        jmp     fat32_open_dir
        jmp     fat32_get_vollabel
        jmp     fat32_read_dirent
        jmp     fat32_get_free_space
        jmp     fat32_close
        
        jmp     fat32_mkdir
        jmp     fat32_rmdir

get_error:
        lda     fat32_errno
        rts

get_size:
        lda     fat32_size
        rts

set_size:
        sta     fat32_size+0
        stz     fat32_size+1
        stz     fat32_size+2 
        stz     fat32_size+3
        cmp     #0
        bne     @done
        inc     fat32_size+1
@done:  rts

set_ptr:
        sta     fat32_ptr+1
        stz     fat32_ptr+0
        rts

set_ptr2:
        sta     fat32_ptr2+1
        stz     fat32_ptr2+0
        rts

seek:
        tax
        lda     0,x
        sta     fat32_size+0
        lda     1,x
        sta     fat32_size+1
        lda     2,x
        sta     fat32_size+2
        lda     3,x
        sta     fat32_size+3

        jmp     fat32_seek

set_time:
        phx
        tax

      ; Set year
        lda     1,x     ; BCD of the decade+year
        sed             ; Use bcd to get the correct wrap-around
        sec
        sbc     #$80    ; Year is 1980 based.
        cld
        jsr     bcd2int
        sta     fat32_time_year

        lda     2,x
        jsr     bcd2int
        sta     fat32_time_month
        
        lda     3,x
        jsr     bcd2int
        sta     fat32_time_day
        
        lda     4,x
        jsr     bcd2int
        sta     fat32_time_hours
        
        lda     5,x
        jsr     bcd2int
        sta     fat32_time_minutes
        
        lda     6,x
        jsr     bcd2int
        sta     fat32_time_seconds
        
        plx
        rts

bcd2int:
        phx
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tax             ; x = the multiple of 10
        pla
        and     #$0f    ; a = 0..9
        clc
        adc     @tab,x
        plx
        rts        
@tab:   .byte   0, 10, 20, 30, 40, 50, 60, 70, 80, 90

fat_test:

        stz     $1
        stz     screen+0
        lda     #$c0
        sta     screen+1
        stz     used

        jsr     sdcard_init
        bcc     @error
        
        jsr     fat32_init
        stz     skip_mask

@out:
        lda     #'K'
        jsr     print
        lda     #0
        tax
        rts
@error:        
        lda     #'X'
        jsr     print
        lda     #$ff
        tax
        rts

my_mkfs:
        
      ; Alloc and set the context.
        pha
        lda     #0
        jsr     fat32_alloc_context
        bcs     @ctx
        pla
        rts
@ctx:   jsr     fat32_set_context
        pla

      ; Set the label name
        jsr     set_ptr

      ; Set the volume ID to the time
        lda     #<fat32_time_day
        sta     fat32_ptr2+0
        lda     #<fat32_time_day
        sta     fat32_ptr2+1

      ; Set the OEM name
        lda     #<@oem
        sta     fat32_bufptr+0
        lda     #>@oem
        sta     fat32_bufptr+1
        
        lda     #0  ; partition 0
        ldx     #0  ; default sectors per cluster
        jsr     fat32_mkfs
        
        php
        jsr     fat32_get_context
        jsr     fat32_free_context
        plp
        rts
@oem:   .asciiz "SteilFAT"

print_hex_byte:
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     print_hex
        pla
        and     #$0f
        jsr     print_hex
        rts

print_hex:
        phy
        tay
        lda     @hex,y
        jsr     print
        ply
        rts
@hex:   .asciiz "0123456789abcdef"        

print_space:
        lda     #32
        jmp     print

print: rts
        cmp     #13
        beq     @lf
        pha
        lda     #2
        sta     $1
        pla
        sta     (screen)
        inc     used
        inc     screen+0
        bne     @done
        inc     screen+1
        lda     screen+1
        cmp     #$d2
        bne     @done
        lda     #$c0
        sta     screen+1
@done:  
        stz     $1
        rts
@lf:
        lda     used
        cmp     #80
        ;bcs     @fix
        beq     @next
        inc     used
        inc     screen+0
        bne     @lf
        inc     screen+1
        bra     @lf        
@next:
        stz     used
        bra     @done
@fix:
        sec
        sbc     #80
        sta     used
        bra     @lf
