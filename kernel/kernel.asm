; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "w65c02"

            .namespace  kernel

            
            .section    dp
blocks      .byte       ?
driver_mem  .byte       ?   
ticks       .word       ?

irq_tmp     .word       ? 

src         .word       ?
dest        .word       ?
count       .word       ?

cur_event   .byte       ?

caller_y    .byte       ?
caller_io   .byte       ?
caller_mmu  .byte       ?

kcheck      .word       ?
stable      .byte       ?

time        .dstruct    time_t

            .send

            .section    global

init
            stz     cur_event
            
            lda     #8      ; Just reserve the first 64k
            sta     blocks

          ; Initialize the kernel pools.
            jsr     thread.init
            jsr     log.init
            jsr     event.init
            jsr     token.init
            jsr     device.init
            jsr     stream.init
            jsr     clock.init
            jsr     delay.init

          ; Initialize the kernel's devices.
            jsr     fs.init
            jsr     net.init

          ; Initialize the rest of the hardware.
            jsr     platform.hardware_init
 ldx #$41
 ;jsr kernel.flash.start_rom
 ;bra _log
        ; Run the first processes

          ; If dip1 is on, try to start a binary in low RAM.
            jsr     start_ram
            
          ; If dip1 is off, check for a binary on the cartridge.
            jsr     start_expansion
            
          ; If we're still here, search the flash
          ; Might disable this if DIP1 is on.
            jsr     start_flash
            
          ; If we're still here, spin on the kernel logs
_log          
            jsr     platform.console.my_font
_loop       jsr     startup.wait
            jmp     _loop                    


start_ram
        ; If DIP1 is on, and the user has uploaded a ROM image into RAM, 
        ; start it.

          ; Only scan the RAM if DIP1 is on.
            jsr     platform.dips.read
            and     #platform.dips.BOOT_MENU
            beq     _done
            
          ; Scan the first few slots for a ROM image.
            ldx     #1
_loop       jsr     kernel.flash.is_rom
            bcc     _start
            inx
            cpx     #6
            bne     _loop
_done       rts
_start      jmp     kernel.flash.start_rom

start_expansion
          ; Only scan the cart if DIP1 is off.
            jsr     platform.dips.read
            and     #platform.dips.BOOT_MENU
            bne     _done
            
            ldx     #$80
_loop       jsr     kernel.flash.is_rom
            bcc     _found
            inx
            cpx     #$a0
            bne     _loop
_done       rts
_found      jmp     kernel.flash.start_rom

start_flash
            ldx     #$40
_loop       jsr     kernel.flash.is_rom
            bcc     _found
            inx
            cpx     #$80
            bne     _loop
            rts
_found      jmp     kernel.flash.start_rom





drain
; Hack -- drain the keyboard
 ldx #0
_loop ;jsr cbm.GETIN
 ldy #0
_lp
 iny
 bne _lp
 inx
 bne _loop 
 rts



block_alloc
        lda     blocks
        inc     blocks
        clc
        rts
        
block_free
        rts
            
tick
      ; Increment the tick count.
        inc     kernel.ticks
        bne     _done
        inc     kernel.ticks+1

      ; Dispatch delay events
_done   jmp     kernel.delay.dispatch

set_timer

        lda     user.timer.units
        and     #$7f
        cmp     #args.timer.FRAMES
        beq     _frame
        cmp     #args.timer.SECONDS
        beq     _seconds
        sec
        rts
        
_frame
        lda     user.timer.absolute
        jmp     delay.request
        
_seconds
        jmp     clock.request

            .send
            .endn

