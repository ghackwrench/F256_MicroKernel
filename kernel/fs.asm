; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "r65c02"

            .namespace  kernel
fs          .namespace

            .virtual    0
ERANGE      .byte       ?       ; Device out of range
EDEV        .byte       ?       ; No such device  
EREADY      .byte       ?       ; Device not ready          
ESTREAM     .byte       ?       ; Out of streams
EEVENT      .byte       ?       ; Out of events
EBUF        .byte       ?       ; Out of buffers
            .endv

            .virtual    0
OPEN        .word   ?
OPEN_DIR    .word   ?
OPEN_NEW    .word   ?
READ        .word   ?
WRITE       .word   ?
SEEK        .word   ?
CLOSE       .word   ?
CLOSE_DIR   .word   ?
RENAME      .word   ?
DELETE      .word   ?
MKFS        .word   ?
FORMAT      .word   ?
MKDIR       .word   ?
RMDIR       .word   ?
            .endv

MAX_ENTRIES = 8

entry       .namespace
            .virtual    Tokens
index       .byte   ?   ; 0..(MAX_ENTRIES-1)            
driver      .byte   ?   ; offset to installed bus driver
device      .byte   ?   ; per-driver device number (0 for SD, 8/9 for IEC)
partition   .byte   ?   ; optional partition id
            .endv
            .endn

args        .namespace
            .virtual    Events
next        .byte       ?   ; event.next
command     .byte       ?   ; event.type
buf         .byte       ?   ; page
ext         .byte       ?   ; event.ext
stream      .byte       ?
cookie      .byte       ?
requested   .byte       ?
fulfilled   .byte       ?
            .endv
            .endn            

            .section    kmem
registered  .byte       ?            
entries     .fill       MAX_ENTRIES ; Just a table for now.
            .send

            .section    kernel

init
          ; No drives registered yet
            stz     registered

          ; Zero the entries table
            phx
            ldx     #0
_loop       stz     entries,x
            inx
            cpx     #MAX_ENTRIES
            bne     _loop
            plx

            clc
            rts

register
    ; IN:   Y->entry token
    ; OUT:  Carry clear on success
    
            pha
            phx

          ; Make sure it's a valid index
            ldx     entry.index,y
            cpx     #MAX_ENTRIES
            bcs     _out
            
          ; Make sure it isn't already registered
            lda     entries,x
            cmp     #1
            bcs     _out
            
          ; Install it
            tya
            sta     entries,x
            inc     registered
_out
            plx
            pla
            rts
            

get_drives
    ; OUT: A contains a bit-set of registered devices.
            phx
            phy
            ldy     #MAX_ENTRIES-1
            lda     #0
_loop       ldx     entries,y
            cpx     #1
            rol     a
            dey
            bpl     _loop
            ply
            plx
            clc
            rts

open
            lda     $2000+kernel.args.file.open.fname_len
            beq     _out

            lda     $2000+kernel.args.file.open.mode
            cmp     #kernel.args.file.open.END
            bcs     _out

            asl     a
            tax
            jmp     (_modes,x)
_out        
            sec
            rts
_modes      .word   open_read, open_new
        

open_common
    ; OUT:  Y->token, X->stream, carry set on error
    
          ; Make sure the user has given us a valid device
            lda     #ERANGE
            ldx     $2000+kernel.args.file.open.drive
            cpx     #MAX_ENTRIES
            bcs     _out

          ; Y->entry; err if device not registered.
            lda     #EDEV
            ldy     entries,x
            sec
            beq     _out

          ; Ask the device if it's ready.
            ldx     entry.driver,y
            lda     #kernel.device.get.READY
            jsr     kernel.device.dev.get   
            lda     #EREADY  
            bcs     _out

          ; X->new stream
            jsr     kernel.stream.alloc
            tax
            lda     #ESTREAM
            bcs     _out

          ; Pre-populate the stream
            lda     entry.driver,y
            sta     kernel.stream.entry.driver,x

            lda     entry.device,y
            sta     kernel.stream.entry.device,x

            lda     entry.partition,y
            sta     kernel.stream.entry.partition,x
            
            stz     kernel.stream.entry.status,x
            stz     kernel.stream.entry.eof,x

            lda     $2000+kernel.args.file.open.cookie
            sta     kernel.stream.entry.cookie,x

          ; Y->event to send args to the driver
            jsr     event.alloc
            bcs     _stream

          ; Set the event's cookie
            sta     args.cookie,y

          ; Set the event's stream
            txa
            sta     args.stream,y

          ; Allocate a buffer for the path.
            jsr     kernel.page.alloc_a
            bcs     _event
            sta     args.buf,y
            
          ; Set the path length; don't copy if it is zero.
            lda     $2000+kernel.args.file.open.fname_len
            beq     _default
            sta     args.requested,y

          ; Copy the data
            lda     args.buf,y
            jmp     import_data

_default
            stz     kernel.dest+0
            lda     args.buf,y
            sta     kernel.dest+1
            lda     #'/'
            sta     (kernel.dest)
            lda     #1
            sta     args.requested,y
            clc
_out            
            rts

_event  ; Free event and stream (no bufs)
            jsr     kernel.event.free
            jsr     _stream
            lda     #EBUF
            rts
            
_stream ; Free stream (b/c out of events)
            txa
            jsr     kernel.stream.free
            lda     #EEVENT
            sec
            bra     _out
           
open_read
            jsr     open_common
            bcs     _out
 
          ; Set the command
            lda     #OPEN
            sta     args.command,y

          ; Stash the stream
            phx

          ; Queue the command; TODO: pull from stream
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
_out
            rts

open_dir
            jsr     open_common ; Sets cookie
            bcs     _out
 
          ; Set the command
            lda     #OPEN_DIR
            sta     args.command,y

          ; Stash the stream
            phx

          ; Queue the command
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
_out
            rts

open_new
            jsr     open_common
            bcs     _out
 
          ; Set the command
            lda     #OPEN_NEW
            sta     args.command,y

          ; Save the stream for later return
            phx

          ; Queue the command
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
_out
            rts


read
    ; stream, opt max bytes

            jsr     event.alloc
            bcs     _out
        
          ; X->stream   ; TODO: verify
            ldx     $2000+kernel.args.file.read.stream

          ; Install the command
            lda     #READ
            sta     args.command,y

          ; Install the stream
            txa
            sta     args.stream,y

          ; Install the cookie
            lda     kernel.stream.entry.cookie,x
            sta     args.cookie,y
            
          ; Install the requested byte-count
            lda     $2000+kernel.args.file.read.buflen
            sta     args.requested,y

          ; Install the data buffer
            jsr     kernel.page.alloc_a
            bcs     _free2
            sta     args.buf,y
            
          ; Install the extended buffer
            jsr     kernel.page.alloc_a
            bcs     _free1
            sta     args.ext,y
            
          ; Dispatch
            lda     kernel.stream.entry.driver,x
            tax
            jmp     kernel.device.dev.send            

_free1
            lda     args.buf,y
            jsr     kernel.page.free
_free2
            jsr     kernel.event.free
            sec
_out
            rts
            
write
          ; Allocate the event
            jsr     event.alloc
            bcs     _out
            
          ; X->stream
            ldx     $2000+kernel.args.file.write.stream

          ; Install the command
            lda     #WRITE
            sta     args.command,y

          ; Install the stream
            txa
            sta     args.stream,y

          ; Install the cookie
            lda     kernel.stream.entry.cookie,x
            sta     args.cookie,y

          ; Import the user's data
            jsr     kernel.page.alloc_a
            bcs     _event
            sta     args.buf,y
            jsr     import_data
                        
          ; Install the byte count
            lda     $2000+kernel.args.file.write.buflen
            sta     args.requested,y

          ; Dispatch
            lda     kernel.stream.entry.driver,x
            tax
            jmp     kernel.device.dev.send            

_event
            jsr     kernel.event.free
            sec
_out
            rts


seek
          ; Allocate the event
            jsr     event.alloc
            bcs     _out
            
          ; Install the command
            lda     #SEEK
            sta     args.command,y
            
          ; Install the stream; leaves X->stream
            lda     $2000+kernel.args.file.seek.stream
            sta     args.stream,y
            tax

          ; Install the cookie
            lda     kernel.stream.entry.cookie,x
            sta     args.cookie,y

          ; Install the position in the stream
            lda     $2000+kernel.args.file.seek.position+0
            sta     args.buf,y
            lda     $2000+kernel.args.file.seek.position+1
            sta     args.ext,y
            lda     $2000+kernel.args.file.seek.position+2
            sta     args.requested,y
            lda     $2000+kernel.args.file.seek.position+3
            sta     args.fulfilled,y

          ; Dispatch
            lda     kernel.stream.entry.driver,x
            tax
            jmp     kernel.device.dev.send            

_out
            rts

close
          ; Allocate the event
            jsr     event.alloc
            bcs     _out
            
          ; Install the command
            lda     #CLOSE
            sta     args.command,y
            
            bra     close_common
_out
            rts

close_dir
          ; Allocate the event
            jsr     event.alloc
            bcs     _out
            
          ; Install the command
            lda     #CLOSE_DIR
            sta     args.command,y
            
            bra     close_common
_out
            rts

close_common
          ; Install the stream; leaves X->stream
            lda     $2000+kernel.args.file.close.stream
            sta     args.stream,y
            tax

          ; Install the cookie
            lda     kernel.stream.entry.cookie,x
            sta     args.cookie,y

          ; Dispatch
            lda     kernel.stream.entry.driver,x
            tax
            jmp     kernel.device.dev.send            

rename
          ; Rename takes two arguments; allocate the second
          ; before calling open_common.
            jsr     kernel.page.alloc_a
            bcs     _out

            pha
            jsr    open_common
            pla
            bcs     _free 

          ; Set the new name's block while we have it
            sta     args.ext,y
            sta     $2000+kernel.args.ptr+1
            
          ; Set the new name's length
            lda     $2000+kernel.args.file.rename.new_len
            sta     $2000+kernel.args.ptr+0
            sta     args.fulfilled,y

          ; Import the user's data
            jsr     import_ext
            ;jsr     print_ext
            
          ; Set the command
            lda     #RENAME
            sta     args.command,y

          ; Save the stream for later return
            phx

          ; Queue the command
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
            clc
            rts
            
_free
            jsr     kernel.page.free
            sec
_out
            rts

delete
            jsr     open_common
            bcs     _out
            
          ; Set the command
            lda     #DELETE
            sta     args.command,y

          ; Save the stream for later return
            phx

          ; Queue the command
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
_out
            rts

mkfs
            jsr     open_common
            bcs     _out
            
          ; Set the command
            lda     #MKFS
            sta     args.command,y

          ; Save the stream for later return
            phx

          ; Queue the command
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
_out
            rts

format
            jsr     open_common
            bcs     _out
            
          ; Set the command
            lda     #FORMAT
            sta     args.command,y

          ; Save the stream for later return
            phx

          ; Queue the command
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
_out
            rts

mkdir
            jsr     open_common
            bcs     _out
            
          ; Set the command
            lda     #MKDIR
            sta     args.command,y

          ; Save the stream for later return
            phx

          ; Queue the command
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
_out
            rts

rmdir
            jsr     open_common
            bcs     _out
            
          ; Set the command
            lda     #RMDIR
            sta     args.command,y

          ; Save the stream for later return
            phx

          ; Queue the command
            lda     kernel.stream.entry.driver,x
            tax
            jsr     kernel.device.dev.send
            
          ; Return the stream
            pla
_out
            rts

            .send
            .endn
            .endn
