; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "w65c02"

            .namespace  hardware
           
            .mkstr  fat_init,   "FAT32 + SPI driver." 

            .mkstr  fat,    "fat32 "
        
fat32       .namespace

            .virtual    fat_base
fat         .namespace
magic       .word   ?
dirent      .word   ?
size        .word   ?

init        .fill   3

get_error   .fill   3
get_size    .fill   3
set_size    .fill   3
set_ptr     .fill   3
set_ptr2    .fill   3
set_time    .fill   3

ctx_alloc   .fill   3
ctx_set     .fill   3
ctx_free    .fill   3

mkfs        .fill   3

file_open   .fill   3
file_new    .fill   3
file_read   .fill   3
file_write  .fill   3
file_wbyte  .fill   3
file_seek   .fill   3
file_close  .fill   3

file_rename .fill   3
file_delete .fill   3

dir_open    .fill   3
dir_name    .fill   3
dir_read    .fill   3
dir_avail   .fill   3
dir_close   .fill   3

dir_mkdir   .fill   3
dir_rmdir   .fill   3
            .endn
            .endv                   

call        .macro  name
            phx
            phy
            inc     mmu_ctrl    ; Switch to MMU1
            jsr     \name
            dec     mmu_ctrl    ; Switch back to MMU0
            ply
            plx
            .endm

state       .struct
DELAY       .word       read_delay
DATA        .word       read_data
VOLUME      .word       read_volume
DIRENT      .word       read_dirent
            .ends

self        .namespace
            .virtual    DevState
this        .byte   ?   ; Copy of the device address
            .endv
            .endn

            .section    dp
fname       .word       ?
fnlen       .byte       ?
cookie      .byte       ?
cmd         .byte       ?
fpos        .dword      ?
            .send
            
            .section    kmem    ; Most of these should be per-instance.
id          .word       ?
requested   .byte       ?
driver      .byte       ?   ; For a later call to probe_devices.
count       .byte       ?   ; count of open streams against the card.
initialized .byte       ?   ; Currently inserted card is initialized.
            .send

            .section    kernel2

vectors     .kernel.device.mkdev    dev

led_on:
       inc count
       stz io_ctrl
       lda $d6a0
       ora #2
       sta $d6a0
       rts
       
led_off
        dec count
        bne _done
        stz io_ctrl
        lda $d6a0
        and #253
        sta $d6a0
_done   rts        


init
          ; Check for a loaded driver
            lda     fat.magic+0
            eor     #$fa
            cmp     #1
            bcs     _out
            lda     fat.magic+1
            eor     #$32
            cmp     #1
            bcs     _out

          ; Allocate the device table.
            stz     driver
            jsr     kernel.device.alloc
            bcs     _out
            stx     driver
        
            txa
            sta     self.this,x

          ; Device not yet active.
            stz     count
            stz     initialized
            stz     io_ctrl
            lda     $d6a0
            and     #253
            sta     $d6a0
        
          ; Install our vectors.
            lda     #<vectors
            sta     kernel.src
            lda     #>vectors
            sta     kernel.src+1
            jsr     kernel.device.install

          ; Associate ourselves with the card insert interrupt
            txa
            ldy     #irq.sdc        ; should be parameterized.
            jsr     irq.install

          ; Enable the hardware interrupt.
            lda     #irq.sdc
    	    jsr     irq.enable
    	
          ; Mount C
            lda     #0
            jsr     register_drive
_done
            phy
            txa
            tay
            lda     #hardware.fat_init_str
            jsr     kernel.log.dev_message
            ply

_out
            clc
            rts     
            
register_drive
    ; A = device ID

            pha
            phy

            jsr     kernel.token.alloc
            bcs     _out
            
            sta     kernel.fs.entry.device,y
            and     #7
            sta     kernel.fs.entry.index,y
            txa
            sta     kernel.fs.entry.driver,y
            lda     #0
            sta     kernel.fs.entry.partition,y
            
            jsr     kernel.fs.register
            bcc     _out

            jsr     kernel.token.free
            sec
            
_out
            ply
            pla
            rts
                        
dev_data
        ; Card inserted interrupt

          ; flag card for re-initialization.
            stz     initialized   
            rts

dev_open
dev_close
dev_fetch
dev_status
        clc
        rts

dev_get

        cmp     #kernel.device.get.READY
        beq     _ready

        phy

        ldy     #hardware.afs_str
        cmp     #kernel.device.get.CLASS
        beq     _found
        
        ldy     #hardware.fat_str
        cmp     #kernel.device.get.DEVICE
        beq     _found
        
        ldy     #hardware.fat_str
        cmp     #kernel.device.get.PORT
        beq     _found
        
        ply
        sec
        rts
        
_ready

      ; Make sure the card is inserted
      
        stz     io_ctrl
        lda     $d6a0
        and     #64
        cmp     #64
        bcs     _out

      ; Only partition zero for now.
        lda     kernel.fs.entry.partition,y
        cmp     #1
        bcs     _out

      ; Make sure the card is initialized.
        lda     initialized
        bne     _out

      ; initialize the card
        call    fat.init
        adc     #1 ; existing carry value is irrelevant.
        bcs     _out
        inc     initialized

_out        
        rts

_found
        tya
        ply
        clc
        rts

dev_set
        sec
        rts
        
dev_send
    ; X=device, Y=args

_ready
      ; Reduce overhead of MMU manipulation
        ldx     #$80
        stx     mmu_ctrl

      ; Call the handler
        ldx     kernel.fs.args.command,y
        jsr     _call

      ; Restore mmu_ctrl
        stz     mmu_ctrl
_out        
        rts
_call        
        jmp     (_ops,x)
_ops            
        .word   open
        .word   open_dir
        .word   open_new
        .word   read_int
        .word   write
        .word   seek
        .word   close
        .word   close_dir
        .word   rename
        .word   delete
        .word   mkfs
        .word   format
        .word   mkdir
        .word   rmdir
        
read_delay
    sec
    rts

open
    ; Y->event

      ; X->stream
        ldx     kernel.fs.args.stream,y

      ; Allocate a file handle
        lda     kernel.stream.entry.partition,x
        call    fat.ctx_alloc
        bcc     _err
        sta     kernel.stream.entry.channel,x 

      ; Make it the current context.
        call    fat.ctx_set
        bcc     _context

      ; Terminate the file name
        jsr     terminate_name

      ; Open the file.
        lda     kernel.fs.args.buf,y
        call    fat.set_ptr
        lda     #0 ; TODO: code placement!??!
        call    fat.file_open 
        bcc     _context    ; TODO: error vs not-found

      ; This is a read stream
        lda     #kernel.stream.entry.READ
        sta     kernel.stream.entry.status,x

      ; Reads call the read_data function
        lda     #state.DATA
        sta     kernel.stream.entry.state,x

      ; Mark the device as busy
        jsr     led_on
            
      ; Send the event
        lda     #kernel.event.file.OPENED
        bra     _send

_context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free
_err
        jsr     kernel.stream.free
        lda     #kernel.event.file.ERROR
_send        
        clc
        sta     kernel.event.entry.type,y
        jmp     kernel.event.enque

open_new
    ; Y->event

      ; X->stream
        ldx     kernel.fs.args.stream,y

      ; Check the write-protect.  Not the idea place,
      ; but checking here prevents resource leaks.
        stz     io_ctrl
        sec
        bit     $d6a0
        bmi     _err        

      ; Allocate a file handle
        lda     kernel.stream.entry.partition,x
        call    fat.ctx_alloc
        bcc     _err
        sta     kernel.stream.entry.channel,x 

      ; Make it the current context.
        call    fat.ctx_set
        bcc     _context

      ; Terminate the file name
        jsr     terminate_name 

      ; Open the file.
        lda     kernel.fs.args.buf,y
        call    fat.set_ptr
        sec     ; overwrite  
        call    fat.file_new 
        bcc     _context

      ; This is a write stream
        lda     #kernel.stream.entry.WRITE
        sta     kernel.stream.entry.status,x

      ; Mark the device as busy
        jsr     led_on
            
      ; Send the event
        lda     #kernel.event.file.OPENED
        clc
        bra     _send

_context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free
_err
        jsr     kernel.stream.free
        lda     #kernel.event.file.ERROR
        sec
_send        
        sta     kernel.event.entry.type,y
        jmp     kernel.event.enque

read_data

          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Fast fail if EOF encountered
            lda     kernel.stream.entry.eof,x
            bne     _eof

          ; Set the buf pointer
            lda     kernel.fs.args.buf,y
            call    fat.set_ptr
          
          ; Set the buf length
            lda     kernel.fs.args.requested,y
            call    fat.set_size

          ; Read the data
            lda     kernel.stream.entry.channel,x 
            call    fat.ctx_set
            bcc     _err
            call    fat.file_read
            call    fat.get_error
            ora     #0
            bne     _err
            
          ; Report the number of bytes read.
            call    fat.get_size
            ora     #0
            beq     _eof
            sta     kernel.event.entry.file.data.read,y

          ; Send the event
            lda     #kernel.event.file.DATA
            bra     _send
_err
            lda     #kernel.event.file.ERROR
            bra     _out
_eof
            lda     #kernel.event.file.EOF
_out
          ; mark the stream as in EOF
            dec     kernel.stream.entry.eof,x
_send
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque

write

          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Mount the embedded buffer
            jsr     mount_buf
          
          ; Set the buf length
            lda     kernel.fs.args.requested,y
            sta     requested

          ; Set the context
            lda     kernel.stream.entry.channel,x 
            call    fat.ctx_set
            bcc     _err
            
          ; Write the data
            phy
            ldy     #0
_loop       lda     (kernel.dest),y
            call    fat.file_wbyte
            bcc     _done
            iny
            cpy     requested
            bne     _loop
            sec
_done       tya
            ply
            bcc     _err
                      
          ; Report the number of bytes written.
            sta     kernel.event.entry.file.wrote.wrote,y

          ; Send the event
            lda     #kernel.event.file.WROTE
            bra     _send
_err
            lda     #kernel.event.file.ERROR
_send
            sta     kernel.event.entry.type,y
            clc
            jmp     kernel.event.enque

seek
    ; Y->event
    
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Set the context
            lda     kernel.stream.entry.channel,x 
            call    fat.ctx_set
            bcc     _err

          ; Populate the seek data
            lda     kernel.fs.args.buf,y
            sta     fpos+0
            lda     kernel.fs.args.ext,y
            sta     fpos+1
            lda     kernel.fs.args.requested,y
            sta     fpos+2
            lda     kernel.fs.args.fulfilled,y
            sta     fpos+3

          ; Perform the seek
            lda     #fpos       ; ZP offset of seek data
            call    fat.file_seek

          ; Send the event
            lda     #kernel.event.file.SEEK
            bra     _send

_err
            jsr     kernel.stream.free
            lda     #kernel.event.directory.ERROR
_send        
          ; Set the type
            sta     kernel.event.entry.type,y

          ; Clear the overloaded buffer pointers
            lda     #0
            sta     kernel.fs.args.buf,y
            sta     kernel.fs.args.ext,y

          ; Queue the event.
            clc
            jmp     kernel.event.enque



close
    ; Y->event
    
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Set the context
            lda     kernel.stream.entry.channel,x 
            call    fat.ctx_set
            bcc     _error
            
          ; Set the time (fat writes the time on close)
            lda     #kernel.time.century
            call    fat.set_time

          ; Perform the close
            call    fat.file_close

_error
          ; Free the context
            lda     kernel.stream.entry.channel,x 
            call    fat.ctx_free
_free
          ; Free the stream
            txa
            jsr     kernel.stream.free
            
          ; Mark the device as no longer busy
            jsr     led_off
            
          ; Return the event
            clc
            lda     #kernel.event.file.CLOSED
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque



open_dir
    ; Y->event

      ; X->stream
        ldx     kernel.fs.args.stream,y

      ; Allocate a file handle
        lda     kernel.stream.entry.partition,x
        call    fat.ctx_alloc
        bcc     _err
        sta     kernel.stream.entry.channel,x 

      ; Make it the current context.
        call    fat.ctx_set
        bcc     _context

      ; This is a read stream
        lda     #kernel.stream.entry.READ
        sta     kernel.stream.entry.status,x

      ; Set state to expect a volume name
        lda     #state.VOLUME
        sta     kernel.stream.entry.state,x

      ; Open_dir
        jsr     terminate_dir
        lda     kernel.fs.args.buf,y
        call    fat.set_ptr
        call    fat.dir_open
        bcc     _context

      ; Mark the device as busy
        jsr     led_on
            
      ; Send the event
        lda     #kernel.event.directory.OPENED
        bra     _send

_context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free
_err
        jsr     kernel.stream.free
        lda     #kernel.event.directory.ERROR
_send        
        clc
        sta     kernel.event.entry.type,y
        jmp     kernel.event.enque

close_dir
    ; Y->event
    
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Set the context
            lda     kernel.stream.entry.channel,x 
            call    fat.ctx_set
            bcc     _free
            
          ; Perform the close
            call    fat.dir_close

          ; Free the context
_free       lda     kernel.stream.entry.channel,x 
            call    fat.ctx_free

          ; Free the stream
            txa
            jsr     kernel.stream.free
            
          ; Mark the device as no longer busy
            jsr     led_off
            
          ; Return the event        ]
            clc
            lda     #kernel.event.directory.CLOSED
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque

read_int

      ; X->stream
        ldx     kernel.fs.args.stream,y 

      ; Read Mode in A
        lda     kernel.stream.entry.state,x

      ; Dispatch
        tax
        jmp     (_ops,x)
_ops    
        .dstruct    state

read_volume
        
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Fast fail if EOF encountered
            sec
            lda     kernel.stream.entry.eof,x
            bne     _eof

          ; Next call should read a DIRENT
            lda     #state.DIRENT
            sta     kernel.stream.entry.state,x
            
          ; Read the volume label from a temp context

            lda     kernel.stream.entry.partition,x
            call    fat.ctx_alloc
            bcc     _err
            pha

            call    fat.ctx_set
            bcc     _cleanup

            call    fat.dir_name
            bcc     _cleanup

            jsr     copy_name
            pla
            call    fat.ctx_free

_okay
          ; Return a directory entry
            lda     #kernel.event.directory.VOLUME
            bra     _send

_eof
            dec     kernel.stream.entry.eof,x
            lda     #kernel.event.directory.EOF
            bra     _send

_cleanup
            pla
            call    fat.ctx_free
_err
            lda     #kernel.event.directory.ERROR
            bra     _send
_send
            clc
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque
            

read_dirent
        
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Fast fail if EOF encountered
            sec
            lda     kernel.stream.entry.eof,x
            bne     _eof

          ; Set the context
            lda     kernel.stream.entry.channel,x 
            call    fat.ctx_set
            bcc     _err
            
          ; Read the next entry
            call    fat.dir_read
            bcc     _free

            jsr     copy_name
            jsr     copy_details

          ; Return a directory entry
            lda     #kernel.event.directory.FILE
            bra     _send

_free
          ; No more entries; read the free space
            call    fat.dir_avail
            bcc     _eof

          ; Mount the source
            lda     fat.size+0
            sta     kernel.src+0
            lda     fat.size+1
            clc
            adc     #$60    ; $2000 in lib; $8000 here.
            sta     kernel.src+1

          ; Mount the dest
            stz     kernel.dest+0
            lda     kernel.event.entry.ext,y
            sta     kernel.dest+1

          ; Map in FAT32's RAM
            lda     mmu+4
            pha
            lda     #7
            sta     mmu+4
            
          ; Copy the size
            phy
            ldy     #0
_loop       lda     (kernel.src),y
            sta     (kernel.dest),y
            iny
            cpy     #4
            bne     _loop
            tya
            ply            

          ; Restore the kernel map
            pla
            sta     mmu+4

            dec     kernel.stream.entry.eof,x
            lda     #kernel.event.directory.FREE
            bra     _send
            
_eof
            dec     kernel.stream.entry.eof,x
            lda     #kernel.event.directory.EOF
            bra     _send
_err
            lda     #kernel.event.directory.ERROR
            bra     _send
_send
            clc
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque


copy_name

          ; Mount the buffer
            jsr     mount_buf

          ; Map in fat32's RAM
          ; Can't just do this globally b/c
          ; the event queue needs access to user RAM.
            lda     mmu+4
            pha
            lda     #7  ; fat32 ram block
            sta     mmu+4
            
          ; Copy the file name
            phy
            ldy     #0
_loop       lda     $82CE,y     ; TODO: WTF, fix.
            beq     _done
            sta     (kernel.dest),y
            iny
            bra     _loop
_done       tya
            ply            

          ; Set the read length
            sta     kernel.event.entry.directory.file.len,y 
            
          ; Restore the std map
            pla
            sta     mmu+4

          ; Restore the length
            lda     kernel.event.entry.directory.file.len,y 

            rts

copy_details

          ; Mount the source
            lda     fat.dirent+0
            clc
            adc     #5  ; attrs(1) + start(4)
            sta     kernel.src+0
            lda     fat.dirent+1
            adc     #1  ; skip the name
            adc     #$60    ; $2k there, $8k here.
            sta     kernel.src+1

          ; Mount the dest
            stz     kernel.dest+0
            lda     kernel.event.entry.ext,y
            sta     kernel.dest+1

          ; Map in fat32's RAM
          ; Can't just do this globally b/c
          ; the event queue needs access to user RAM.
            lda     #7  ; fat32 ram block
            sta     mmu+4
                    
          ; Round up the size
            phy
            ldy     #0
            lda     #$ff
_round      clc
            adc     (kernel.src),y
            sta     (kernel.src),y
            lda     #0
            rol     a
            iny
            cpy     #4
            bne     _round
            ply

          ; Adjust the source pointer to block size
            inc     kernel.src+0
            bne     _copy
            inc     kernel.src+1

_copy
            phy
            ldy     #0
_loop       lda     (kernel.src),y
            sta     (kernel.dest),y
            iny
            cpy     #3
            bne     _loop
            tya
            ply            

          ; Restore the map
            pha
            lda     mmu+5
            dec     a
            sta     mmu+4
            pla

            rts

mount_buf

        stz     kernel.dest+0
        lda     kernel.event.entry.buf,y
        sta     kernel.dest+1

_out    rts

terminate_dir

      ; Mount the buffer
        lda     kernel.fs.args.buf,y
        sta     fname+1
        stz     fname+0

      ; Point Y at the end of it
        lda     kernel.fs.args.requested,y
        phy
        tay
        beq     _append ; Shouldn't be possible.

      ; Are we already ending in a slash?
        dey
        lda     (fname),y
        iny
        cmp     #'/'
        beq     _done

      ; append a slash
_append
        lda     #'/'
        sta     (fname),y
        iny
        
_done
        lda     #0
        sta     (fname),y
        ply
        rts                  

terminate_name

      ; Mount the buffer
        lda     kernel.fs.args.buf,y
        sta     fname+1
        stz     fname+0

      ; Terminate the file name
        lda     kernel.fs.args.requested,y
        phy
        tay
        lda     #0
        sta     (fname),y
        ply

        rts

terminate_rename

      ; Mount the buffer
        lda     kernel.fs.args.ext,y
        sta     fname+1
        stz     fname+0

      ; Terminate the file name
        lda     kernel.fs.args.fulfilled,y
        phy
        tay
        lda     #0
        sta     (fname),y
        ply

        rts
        
mkfs:
format:

      ; Make sure the device isn't already in use.
        lda     count
        cmp     #1
        bcs     _err

      ; Check the write-protect.  Not the ideal place,
      ; but checking here prevents resource leaks.
        stz     io_ctrl
        lda     $d6a0
        cmp     #$80
        bcs     _err
            
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Terminate the label
        jsr     terminate_name
        
      ; Mark the device as busy
        jsr     led_on
            
        lda     kernel.fs.args.buf,y
        call    fat.mkfs
        bcc     _err

      ; Mark the device as no longer busy
        jsr     led_off
            
      ; Send the event
        lda     #kernel.event.fs.CREATED
        sta     kernel.event.entry.type,y
        bra     _out

_err
        lda     #kernel.event.fs.ERROR
        sta     kernel.event.entry.type,y

_out
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque


rename
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Mark the device as busy
        jsr     led_on

      ; Check the write-protect.
        stz     io_ctrl
        lda     $d6a0
        cmp     #$80
        bcs     _err

      ; Allocate a file handle
        lda     kernel.stream.entry.partition,x
        call    fat.ctx_alloc
        bcc     _err
        sta     kernel.stream.entry.channel,x 
        
      ; Terminate the old
        jsr     terminate_name

      ; Terminate the new
        jsr     terminate_rename

      ; Set the context
        lda     kernel.stream.entry.channel,x 
        call    fat.ctx_set
        bcc     _context
        
        lda     kernel.fs.args.buf,y
        call    fat.set_ptr
        lda     kernel.fs.args.ext,y
        call    fat.set_ptr2
        call    fat.file_rename
        bcc     _context

      ; Free the context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free

      ; Send the event
        lda     #kernel.event.file.RENAMED
        sta     kernel.event.entry.type,y
        bra     _out

_context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free
_err
        lda     #kernel.event.file.ERROR
        sta     kernel.event.entry.type,y

_out
      ; Mark the device as no longer busy
        jsr     led_off
            
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque

delete
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Mark the device as busy
        jsr     led_on

      ; Check the write-protect.
        stz     io_ctrl
        lda     $d6a0
        cmp     #$80
        bcs     _err

      ; Allocate a file handle
        lda     kernel.stream.entry.partition,x
        call    fat.ctx_alloc
        bcc     _err
        sta     kernel.stream.entry.channel,x 

      ; Terminate the label
        jsr     terminate_name
        
      ; Set the context
        lda     kernel.stream.entry.channel,x 
        call    fat.ctx_set
        bcc     _context
        
        lda     kernel.fs.args.buf,y
        call    fat.set_ptr
        call    fat.file_delete
        bcc     _context

      ; Free the context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free

      ; Send the event
        lda     #kernel.event.file.DELETED
        sta     kernel.event.entry.type,y
        bra     _out

_context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free
_err
        lda     #kernel.event.file.ERROR
        sta     kernel.event.entry.type,y

_out
      ; Mark the device as no longer busy
        jsr     led_off
            
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque

mkdir
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Mark the device as busy
        jsr     led_on

      ; Check the write-protect.
        stz     io_ctrl
        lda     $d6a0
        cmp     #$80
        bcs     _err

      ; Allocate a file handle
        lda     kernel.stream.entry.partition,x
        call    fat.ctx_alloc
        bcc     _err
        sta     kernel.stream.entry.channel,x 
        
      ; Terminate the label
        jsr     terminate_name

      ; Set the context
        lda     kernel.stream.entry.channel,x 
        call    fat.ctx_set
        bcc     _context
                
        lda     kernel.fs.args.buf,y
        call    fat.set_ptr
        call    fat.dir_mkdir
        bcc     _context

      ; Free the context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free

      ; Send the event
        lda     #kernel.event.directory.CREATED
        sta     kernel.event.entry.type,y
        bra     _out

_context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free

_err
        lda     #kernel.event.directory.ERROR
        sta     kernel.event.entry.type,y

_out
      ; Mark the device as no longer busy
        jsr     led_off
            
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque

rmdir
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Terminate the label
        jsr     terminate_name
        
      ; Mark the device as busy
        jsr     led_on

      ; Check the write-protect.  Not the ideal place,
      ; but checking here prevents resource leaks.
        stz     io_ctrl
        lda     $d6a0
        cmp     #$80
        bcs     _err
            
      ; Allocate a file handle
        lda     kernel.stream.entry.partition,x
        call    fat.ctx_alloc
        bcc     _err
        sta     kernel.stream.entry.channel,x 

      ; Set the context
        lda     kernel.stream.entry.channel,x 
        call    fat.ctx_set
        bcc     _context
        
        lda     kernel.fs.args.buf,y
        call    fat.set_ptr
        call    fat.dir_rmdir
        bcc     _err

      ; Free the context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free

      ; Send the event
        lda     #kernel.event.directory.DELETED
        sta     kernel.event.entry.type,y
        bra     _out

_context
        lda     kernel.stream.entry.channel,x
        call    fat.ctx_free
_err
        lda     #kernel.event.directory.ERROR
        sta     kernel.event.entry.type,y

_out
      ; Mark the device as no longer busy
        jsr     led_off
            
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque

        .send
        .endn
        .endn

