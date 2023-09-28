; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "r65c02"

            .namespace  kernel

mkapi       .macro  CALL
            lda     #kernel.gates.\CALL
            bra     call_gate
            .endm

mkcall      .macro  ADDR
            jmp     \ADDR
            nop
            .endm

*           = $ff00

            .mkcall kernel.next_event
            .mkcall kernel.read_data
            .mkcall kernel.read_ext
            .mkcall platform.yield
            .mkcall kernel.putchar
            .mkcall kernel.flash.start_by_number
            .mkcall kernel.flash.start_by_name
            .fill   4, 0
            
            .mkapi  BlockDevice.List
            .mkapi  BlockDevice.GetName
            .mkapi  BlockDevice.GetSize
            .mkapi  BlockDevice.Read
            .mkapi  BlockDevice.Write
            .mkapi  BlockDevice.Format
            .mkapi  BlockDevice.Export

            .mkapi  FileSystem.List
            .mkapi  FileSystem.GetSize
            .mkapi  FileSystem.MkFS
            .mkapi  FileSystem.CheckFS
            .mkapi  FileSystem.Mount
            .mkapi  FileSystem.Unmount
            .mkapi  FileSystem.ReadBlock
            .mkapi  FileSystem.WriteBlock

            .mkapi  File.Open
            .mkapi  File.Read
            .mkapi  File.Write
            .mkapi  File.Close
            .mkapi  File.Rename
            .mkapi  File.Delete
            .mkapi  File.Seek

            .mkapi  Directory.Open
            .mkapi  Directory.Read
            .mkapi  Directory.Close
            .mkapi  Directory.MkDir
            .mkapi  Directory.RmDir

call_gate   .mkcall kernel.gate

            .mkapi  Net.GetIP
            .mkapi  Net.SetIP
            .mkapi  Net.GetDNS
            .mkapi  Net.SetDNS
            .mkapi  Net.SendICMP
            .mkcall kernel.socket_match

            .mkcall kernel.udp_init
            .mkcall kernel.udp_send
            .mkcall kernel.udp_recv
            
            .mkcall kernel.tcp_open
            .mkcall kernel.tcp_accept
            .mkcall kernel.tcp_reject
            .mkcall kernel.tcp_send
            .mkcall kernel.tcp_recv
            .mkcall kernel.tcp_close

            .mkapi  Display.Reset
            .mkcall kernel.screen_size
            .mkcall kernel.draw_text
            .mkapi  Display.DrawColumn

            .mkcall kernel.get_time
            .mkapi  Clock.SetTime
            .fill   12  ; 65816 vectors
            .mkapi  Clock.SetTimer

            .section    dp
user_mmu    .byte       ?
            .send            

            .section    global

gates       .struct

NextEvent   .word   kernel.next_event
ReadData    .word   kernel.read_data
ReadExt     .word   kernel.read_ext
Yield       .word   platform.yield
Putch       .word   putchar
RunBlock    .word   dummy
RunNamed    .word   dummy
            .word   dummy

BlockDevice .namespace
List        .word   dummy
GetName     .word   dummy
GetSize     .word   dummy
Read        .word   dummy
Write       .word   dummy
Format      .word   dummy
Export      .word   dummy
            .endn

FileSystem  .namespace
List        .word   kernel.fs.get_drives
GetSize     .word   dummy
MkFS        .word   kernel.fs.mkfs
CheckFS     .word   dummy
Mount       .word   dummy
Unmount     .word   dummy
ReadBlock   .word   dummy
WriteBlock  .word   dummy
            .endn
            
File        .namespace
Open        .word   kernel.fs.open
Read        .word   kernel.fs.read
Write       .word   kernel.fs.write
Close       .word   kernel.fs.close
Rename      .word   kernel.fs.rename
Delete      .word   kernel.fs.delete
Seek        .word   kernel.fs.seek
            .endn
            
Directory   .namespace
Open        .word   kernel.fs.open_dir
Read        .word   kernel.fs.read
Close       .word   kernel.fs.close_dir
MkDir       .word   kernel.fs.mkdir
RmDir       .word   kernel.fs.rmdir      
            .endn

Net         .namespace

GetIP       .word   dummy
SetIP       .word   dummy
GetDNS      .word   dummy
SetDNS      .word   dummy
SendICMP    .word   dummy
Match       .word   dummy   ; Direct call

UDP         .namespace
Init        .word   kernel.udp_init
Send        .word   kernel.udp_send
Recv        .word   kernel.udp_recv
            .endn

TCP         .namespace            
Open        .word   dummy   ; Direct call
Accept      .word   dummy   ; Direct call
Reject      .word   dummy   ; Direct call
Send        .word   dummy   ; Direct call
Recv        .word   dummy   ; Direct call
Close       .word   dummy   ; Direct call
            .endn

            .endn

Display     .namespace
Reset       .word   platform.console.init
GetSize     .word   kernel.screen_size
DrawRow     .word   kernel.draw_text
DrawColumn  .word   dummy
            .endn

Clock       .namespace
GetTime     .word   kernel.get_time
SetTime     .word   dummy
            .fill   6       ; 65816 vectors.
SetTimer    .word   kernel.set_timer
            .endn

            .ends
gate
        phx     ; on their stack

        ldx     mmu_ctrl
        stz     mmu_ctrl
        phx     ; on our stack
        stx     user_mmu

        ldx     io_ctrl
        stz     io_ctrl
        phx

        tax
        jsr     _call

        plx
        stx     io_ctrl

        plx                 ; from our stack
        stx     mmu_ctrl    ; on their stack

        plx     ; from their stack
        ora     #0
        rts

_call   jmp     (_table,x)
_table  .dstruct    gates
        
dummy
        sec
        rts
        
putchar
        phx
        ldx     mmu_ctrl
        stz     mmu_ctrl
        jsr     platform.console.puts
        stx     mmu_ctrl
        plx
        rts

get_time
        lda     io_ctrl
        pha
        lda     #4
        sta     io_ctrl
        phy
        ldy     #0
_loop   lda     kernel.time+$C000,y
        sta     (kernel.args.buf),y
        iny
        cpy     #time_t.size
        bne     _loop
        ply
        pla
        sta     io_ctrl
        clc
        rts        

next_event
        phx
        phy

      ; Switch to kernel mode
        ldx     mmu_ctrl
        stz     mmu_ctrl

      ; Free the previous event.
        ldy     cur_event
        beq     _pop
        jsr     kernel.event.free

_pop
      ; Pop the next event into Y
        jsr     kernel.event.deque
        sty     cur_event

      ; Back to user mode
        stx     mmu_ctrl
        bcs     _out        ; No events

      ; Move event offset to X
        tya
        tax

        ldy     io_ctrl
        phy
        ldy     #4
        sty     io_ctrl
        
      ; Copy the data
        ldy     #0
_loop1
        lda     kernel.event.alias+1,x
        sta     (args.events.dest),y
        inx
        iny
        cpy     #7
        bne     _loop1       

        clc
        ply
        sty     io_ctrl
_out        
        ply
        plx
        rts      

read_data
        phx
        phy

        ldy     io_ctrl
        phy
        ldy     #4
        sty     io_ctrl

        ldy     args.recv.buflen

        ldx     $c000+kernel.cur_event
        lda     $c000+kernel.event.entry.buf,x
        sec
        beq     _done   ; TODO: return zero length copy

      ; Copy the data to the user's memory
        jsr     export_data        

_done
        ply
        sty     io_ctrl

        ply
        plx
        rts

read_ext
        phx
        phy

        ldy     io_ctrl
        phy
        ldy     #4
        sty     io_ctrl

        ldy     args.recv.buflen

        ldx     $c000+kernel.cur_event
        lda     $c000+kernel.event.entry.ext,x
        sec
        beq     _done   ; TODO: return zero length copy

      ; Copy the data to the user's memory
        jsr     export_data        

_done
        ply
        sty     io_ctrl
        ply
        plx
        rts

export_data
    ; A = buffer (page id)
    ; Y = length of data

        stz     args.ptr+0  ; Internal buffers are always aligned.
        ora     #$c0        ; Buffers are mapped under the io
        sta     args.ptr+1

_loop        
        dey
        lda     (args.ptr),y
        sta     (args.recv.buf),y
        tya     ; cheap zero test
        bne     _loop
        rts

import_data
    ; IN: A=page, user_mmu contains the user's mmu

        phy

      ; Switch to the user's map
        ldy     user_mmu
        sty     mmu_ctrl    ; Now on user's stack!

      ; Set up the dest pointer
        stz     args.ptr+0
        ora     #$c0
        sta     args.ptr+1
    
      ; Get the buffer size
        ldy     args.recv.buflen

      ; Bring in our memory under the I/O
        lda     #4
        sta     io_ctrl

      ; Copy the data
_loop   dey
        lda     (args.recv.buf),y
        sta     (args.ptr),y
        tya
        bne     _loop

      ; Return to the kernel's map and I/O
        stz     io_ctrl
        stz     mmu_ctrl

        ply
        clc
        rts

import_ext
    ; IN:   args.ptr+0 = size,
    ;       args.ptr+1 = page
    ;       user_mmu contains the user's mmu

        phy

      ; Switch to the user's map
        ldy     user_mmu
        sty     mmu_ctrl    ; Now on user's stack!

      ; Get the buffer size
        ldy     args.ptr+0  ; Redundant if we are trusting recv.ext

      ; Adjust the dest pointer
        stz     args.ptr+0
        lda     args.ptr+1  ; buffer in kernel memory
        ora     #$c0
        sta     args.ptr+1  ; Buffer in aliased kernel memory
    
      ; Bring in our memory under the I/O
        lda     #4
        sta     io_ctrl

      ; Copy the data
_loop   dey
        lda     (args.ext),y
        sta     (args.ptr),y
        tya
        bne     _loop

      ; Return to the kernel's map and I/O
        stz     io_ctrl
        stz     mmu_ctrl

        ply
        clc
        rts

screen_size
        lda     #80
        sta     kernel.args.display.x
        lda     #60
        sta     kernel.args.display.y
        clc
        rts

draw_text 
    ; TODO: bounds checking, 40/80 mode?

        lda     args.display.buflen
        beq     _done

        phy

      ; Compute the start offset.
      ; TODO: replace with a lookup table
        stz     args.ptr+1
        lda     args.display.y
        asl     a
        asl     a
        rol     args.ptr+1
        adc     args.display.y
        bcc     _ok
        inc     args.ptr+1
_ok     asl     a
        rol     args.ptr+1
        asl     a
        rol     args.ptr+1
        asl     a
        rol     args.ptr+1
        asl     a
        rol     args.ptr+1
        adc     args.display.x
        sta     args.ptr+0

        lda     args.ptr+1
        adc     #$c0
        sta     args.ptr+1

      ; Save the map
        lda     io_ctrl
        pha

      ; Copy the text.
        lda     #2
        sta     $1
        ldy     #0
_loop   lda     (args.display.buf),y
        sta     (args.ptr),y
        iny
        cpy     args.display.buflen
        bne     _loop

      ; Copy the color.
        lda     #3
        sta     $1
        ldy     #0
_loop2  lda     (args.display.buf2),y
        sta     (args.ptr),y
        iny
        cpy     args.display.buflen
        bne     _loop2

      ; Restore the map
        pla
        sta     $1
        
        ply
_done
        clc
        rts        

            .send
            .endn
