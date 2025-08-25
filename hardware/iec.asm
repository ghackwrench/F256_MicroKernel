; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "w65c02"

            .namespace  hardware
           
            .mkstr  iec_init,   "Commodore IEC Bus Driver."

            .mkstr  iec,    "iec   "
            .mkstr  afs,    "afs   "
        
iec         .namespace

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
path        .word       ?
path_len    .byte       ?
fname       .word       ?
fnlen       .byte       ?
cookie      .byte       ?
cmd         .byte       ?
            .send
            
            .section    kmem
id          .word       ?
requested   .byte       ?
driver      .byte       ?   ; For a later call to probe_devices.
awake       .byte       ?
cur_stream  .byte       ?   ; Currently active stream
channels    .fill       8   ; One for each device >= 8; overkill, but meh.
probed      .fill       8   ; One for each device >= 8; overkill, but meh.
tmp         .byte       ?   ; groan
            .send

            .section    kernel2

vectors     .kernel.device.mkdev    dev

init
          ; Allocate the device table.
            stz     driver
            jsr     kernel.device.alloc
            bcs     _out
            stx     driver
        
            txa
            sta     self.this,x

          ; Init the channel sets.
            phx
            ldx     #0
            lda     #$ff
_loop       sta     channels,x
            stz     probed,x
            inx
            cpx     #8
            bne     _loop
            plx

          ; No active stream.
            stz     cur_stream
        
          ; Install our vectors.
            lda     #<vectors
            sta     kernel.src
            lda     #>vectors
            sta     kernel.src+1
            jsr     kernel.device.install

          ; Register two drives (A and B)
            lda     #8
            jsr     register_drive
            lda     #9
            jsr     register_drive

          ; Wait before enabling IEC operations.
            stz     awake
            lda     #1
            jsr     kernel.clock.insert

            phy
            txa
            tay
            lda     #hardware.iec_init_str
            jsr     kernel.log.dev_message
            ply

_out
            rts     
            
dev_status
            inc     awake
            rts

probe_devices   ; Should prolly preserve registers

          ; Stall until awake.
            lda     awake
            beq     probe_devices

          ; Probe (on the user's thread)            
            ldx     driver
            lda     #8
            jsr     test_device
            lda     #9
            jsr     test_device
            clc
_out
            rts

test_device
            clc
            pha
            jsr     platform.iec.probe_device
            pla
            bcc     register_drive
            rts

register_drive
    ; A = device ID

            pha
            phy

            jsr     kernel.token.alloc
            bcs     _out
            
            sta     kernel.fs.entry.device,y
            and     #7
            inc     a
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
                        

  

dev_open
dev_close
dev_fetch
dev_data
        clc
        rts

dev_get

        cmp     #kernel.device.get.READY
        beq     _ready

        phy

        ldy     #hardware.afs_str
        cmp     #kernel.device.get.CLASS
        beq     _found
        
        ldy     #hardware.iec_str
        cmp     #kernel.device.get.DEVICE
        beq     _found
        
        ldy     #hardware.iec_str
        cmp     #kernel.device.get.PORT
        beq     _found
        
        ply
        sec
        rts
        
_ready
      ; If the device has passed a probe, it's ready.
        lda     kernel.fs.entry.index,y
        phy
        tay
        lda     probed,y
        bne     _go
        ply

      ; If it's too early to probe, wait.
        lda     awake
        beq     _ready

      ; Probe both devices
        lda     #8
        jsr     platform.iec.probe_device
        lda     #1
        adc     #0
        sta     probed+1

        lda     #9
        jsr     platform.iec.probe_device
        lda     #1
        adc     #0
        sta     probed+2

      ; Check again
        bra     _ready

_go
        ply
        cmp     #2
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

      ; If we have no current stream, do the command.
        ldx     cur_stream
        beq     _go

      ; If the stream hasn't changed, do the command.
        txa
        cmp     kernel.fs.args.stream,y
        beq     _go
        
      ; Stream changing; pause the current stream.
        jsr     pause
        
      ; If this is a new stream, do the command.
        ldx     kernel.fs.args.stream,y
        lda     kernel.stream.entry.status,x
        beq     _go
        
      ; If the new stream is in EOF, do the command.
      ; This is a hack ... the 1571 gets confused
      ; if you ask a finished stream to TALK.
        lda     kernel.stream.entry.eof,x
        bne     _go

      ; Resume the command's existing stream.
        ldx     kernel.fs.args.stream,y
        jsr     resume
            
_go
        ldx     kernel.fs.args.command,y
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
        
seek
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

channel_alloc
    ; A = allocated channel number on device in X; carry set on error.
    
        phy

      ; Get the channel set for the current device.
        ldy     kernel.stream.entry.device,x
        lda     channels-8,y

      ; If it's empty, return an error
        sec
        beq     _out

      ; tmp the set.
        sta     tmp

      ; Get and stash the index of the first set bit.
        tay
        lda     irq.first_bit,y
        pha      

      ; Remove the first set bit from the set.
        tay
        lda     irq.bit,y
        eor     tmp
        ldy     kernel.stream.entry.device,x
        sta     channels-8,y        

      ; Pop and and adjust the bit number into a channel number.
        pla
        inc     a   ; Channel zero is reserved for DIR.
        inc     a   ; Channel one is reserved for SAVE.
        
        clc
_out
        ply
        rts        

channel_free
    ; Free channel in A on device in X.
     
        phy

        tay
        beq     _done

      ; Convert A from channel # to bit.
        tay
        dey
        dey
        lda     irq.bit,y

      ; Get the channel set for the current device.
        ldy     kernel.stream.entry.device,x

      ; Restore (free) the bit in A
        sta     tmp
        lda     channels-8,y
        ora     tmp
        sta     channels-8,y
        
_done
        ply
        rts

parse_name
        lda     kernel.fs.args.buf,y
        sta     path+1
        sta     fname+1

        stz     path+0
        stz     fname+0

      ; A = the end of the path segment; may be zero.
        phy
        lda     kernel.fs.args.requested,y
        tay
        beq     _end
        dey
_loop   lda     (path),y
        cmp     #'/'
        beq     _done
        tya
        beq     _end
        dey
        bra     _loop
_done   iny     ; Point Y just beyond the slash.
_end    tya
        ply
        
      ; Set the path length; may be zero.
        sta     path_len

      ; Start the name
        sta     fname+0 
      
      ; Terminate the name
        lda     kernel.fs.args.requested,y
        sec
        sbc     fname+0
        sta     fnlen
        
        rts

open

      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Allocate a channel
        jsr     channel_alloc
        bcs     _err
        sta     kernel.stream.entry.channel,x   ; Zero on failure.
        
      ; No command prefix
        lda     #cmd_str.none
        sta     cmd

      ; Set the filename info
        jsr     parse_name

      ; Open the file ... alas, always succeeds.
        jsr     open_read
        bcs     _channel
        
      ; Try to read the first byte.  This will fail on
      ; a file-not-found.
        jsr     platform.iec.IECIN
        bcs     _nsf
        bvc     _delay

      ; We also had an EOI on the first byte...
        dec     kernel.stream.entry.eof,x

      ; Set state to include the delayed byte in the first read.
_delay  sta     kernel.stream.entry.delay,x
        lda     #state.DELAY
        sta     kernel.stream.entry.state,x

      ; Send the event
        stx     cur_stream
        lda     #kernel.event.file.OPENED
        bra     _send

_nsf
    ; File not found.  Close, free, and return the event.

        jsr     send_close
        lda     #kernel.event.file.NOT_FOUND
        bra     _send

_channel
    ; Open failed; free the channel and error
        lda     kernel.stream.entry.channel,x
        jsr     channel_free

_err
        lda     #kernel.event.file.ERROR
_send
        sta     kernel.event.entry.type,y
        jmp     kernel.event.enque
            


open_dir
        ; Consider supporting file timestamps ("$=T")

    ; Y->event

      ; X->stream
        ldx     kernel.fs.args.stream,y

      ; Allocate a channel:
      ; Always zero for directories.  TODO: block nested requests.
        stz     kernel.stream.entry.channel,x
        
      ; Request Directory command
        lda     #cmd_str.dir
        sta     cmd

      ; Set state to expect a volume name
        lda     #state.VOLUME
        sta     kernel.stream.entry.state,x

      ; Set the path info; later handle wildcards.
        lda     kernel.fs.args.buf,y
        sta     path+1
        stz     path+0
        lda     kernel.fs.args.requested,y
        sta     path_len

      ; IEC directories are synthetic files  
      ; TODO: fine for the user to specify a path and/or filter      
        lda     #<_fname
        sta     fname+0
        lda     #>_fname
        sta     fname+1
        lda     #1
        sta     fnlen
        
        jsr     open_read
        bcs     _err

      ; Send the event
        stx     cur_stream
        lda     #kernel.event.directory.OPENED
        bra     _send
_err
        jsr     kernel.stream.free
        lda     #kernel.event.directory.ERROR
_send        
        sta     kernel.event.entry.type,y
        jmp     kernel.event.enque

_fname  .null   "*"        

open_new

    ; Y->event

      ; X->stream
        ldx     kernel.fs.args.stream,y
        
      ; Allocate a channel
        jsr     channel_alloc
        bcs     _err
        sta     kernel.stream.entry.channel,x

      ; Overwrite existing files command
        lda     #cmd_str.over
        sta     cmd

      ; TODO: set state to fail on read

      ; Set the filename info
        jsr     parse_name

        jsr     open_write
        bcs     _channel

        stx     cur_stream
        lda     #kernel.event.file.OPENED
        bra     _send

_channel
        lda     kernel.stream.entry.channel,x
        jsr     channel_free
_err
        jsr     kernel.stream.free
        lda     #kernel.event.file.ERROR
_send
        sta     kernel.event.entry.type,y
        jmp     kernel.event.enque
            
_fname  .null   "T"        

        

open_read
    ; X->stream

      ; This is a read stream
        lda     #kernel.stream.entry.READ
        sta     kernel.stream.entry.status,x

        jsr     open_name
        bcs     _out

        lda     kernel.stream.entry.device,x
        jsr     platform.iec.TALK
        bcs     _out

        lda     kernel.stream.entry.channel,x
        jsr     platform.iec.DEV_SEND
        bcs     _out

_out            
        rts

open_write
    ; X->stream

      ; This is a write stream
        lda     #kernel.stream.entry.WRITE
        sta     kernel.stream.entry.status,x

        jsr     open_name
        bcs     _out

        lda     kernel.stream.entry.device,x
        jsr     platform.iec.LISTEN
        bcs     _out

        lda     kernel.stream.entry.channel,x
        jsr     platform.iec.DEV_RECV
        bcs     _out

_out            
        rts

open_name
    ; X->stream
        
        lda     kernel.stream.entry.device,x
        jsr     platform.iec.LISTEN
        bcs     _out

        lda     kernel.stream.entry.channel,x
        jsr     platform.iec.OPEN
        bcs     _out

        jsr     send_name
        bcs     _out

        jsr     platform.iec.UNLISTEN
        bcs     _out

_out
        rts

send_name
    ; IN: X->stream
    ; IN: fname and fnlen initialized
    ; OUT: carry set on error

      ; Send any command prefix bytes
        jsr     send_cmd_prefix
        bcs     _out

      ; Send the partition ID
        lda     kernel.stream.entry.partition,x
        ora     #'0'
        jsr     platform.iec.IECOUT
        bcs     _out

      ; Send the path
        jsr     send_path_string

      ; Send colon (TODO: handle paths)
        lda     #':'
        jsr     platform.iec.IECOUT
        bcs     _out

      ; Send the name
        jsr     send_name_string
        
      ; Send the mode; TODO: expand for append
        lda     kernel.stream.entry.status,x
        eor     #kernel.stream.entry.WRITE
        bne     _out
        
      ; Append the write mode
        lda     #','
        jsr     platform.iec.IECOUT
        bcs     _out
        lda     #'W'
        jsr     platform.iec.IECOUT
        bcs     _out

_out    rts        


cmd_str .struct
none    .byte   0
dir     .null   "$"
over    .null   "@"
rename  .null   "R"
delete  .null   "S"
mkfs    .null   "N"
mkdir   .null   "MD"
rmdir   .null   "RD"
        .ends

send_cmd_prefix
        phy
        clc
        ldy     cmd
_loop   lda     _str,y
        beq     _done
        iny
        jsr     platform.iec.IECOUT
        bcc     _loop
_done   ply
        rts
_str    .dstruct cmd_str

send_path_string
        lda     path_len
        beq     _done
        
        lda     #'/'
        jsr     platform.iec.IECOUT
        bcs     _out

        phy
        ldy     #0
        bra     _next
_loop   
        lda     (path),y
        jsr     platform.iec.IECOUT
        bcs     _out
        iny
_next   cpy     path_len
        bne     _loop
        clc
_out
        ply
_done
        rts                

send_name_string
        phy
        ldy     #0
        bra     _next
_loop   
        lda     (fname),y
        jsr     platform.iec.IECOUT
        bcs     _out
        iny
_next   cpy     fnlen
        bne     _loop
        clc
_out
        ply
        rts                

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

write
    ; Y->event
    
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Mount the embedded buffer
            jsr     mount_buf
            
          ; Limit the requested byte count
            lda     kernel.fs.args.requested,y
            cmp     #64
            bcc     _write
            lda     #64

_write      sta     requested
            phy
            ldy     #0
_loop       lda     (kernel.dest),y
            jsr     platform.iec.IECOUT
            bcs     _done
            iny
            cpy     requested
            bne     _loop
            clc
_done       tya
            ply
            bcs     _err
            
          ; Export the number of bytes actually written
            sta     kernel.event.entry.file.wrote.wrote,y

          ; signal completion
            lda     #kernel.event.file.WROTE
            bra     _send
_err
            lda     #kernel.event.file.ERROR
_send
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque
                
close
    ; Y->event
    
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Free the channel before send_close frees the stream.
          ; We can do this here b/c the rest is presently synchronous.
            lda     kernel.stream.entry.channel,x
            jsr     channel_free

          ; Perform the close
            jsr     send_close
        
            lda     #kernel.event.file.CLOSED
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque

close_dir
    ; Y->event
    
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Perform the close
            jsr     send_close
        
            lda     #kernel.event.directory.CLOSED
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque

send_close
    ; Everything but the event.

          ; UNTALK or UNLISTEN
            jsr     pause
           
          ; close
            lda     kernel.stream.entry.device,x
            jsr     platform.iec.LISTEN
            lda     kernel.stream.entry.channel,x
            jsr     platform.iec.CLOSE
            jsr     platform.iec.UNLISTEN
            
          ; HACK: read status to clear last error
            lda     kernel.stream.entry.device,x
            jsr     platform.iec.clear_status
            
          ; Free the channel
            lda     kernel.stream.entry.channel,x
            jsr     channel_free

          ; Free the stream
            txa
            jmp     kernel.stream.free
            
pause
    ; Pause the stream in X by sending UNTALK or UNLISTEN.

          ; There won't be a cur_stream after this.
            stz     cur_stream

          ; Call UNTALK or UNLISTEN appropriately
            lda     kernel.stream.entry.status,x
            and     #kernel.stream.entry.WRITE
            cmp     #1 ; WRITE bit in carry
            bcc     _reading
            bcs     _writing
_reading    jmp     platform.iec.UNTALK     ; reading
_writing    jmp     platform.iec.UNLISTEN   ; writing

resume
    ; Resume the stream in X by sending TALK or LISTEN.
    
          ; cur_stream will be X after this (assuming no errors).
            stx     cur_stream

          ; Call UNTALK or UNLISTEN appropriately
            lda     kernel.stream.entry.status,x
            and     #kernel.stream.entry.WRITE
            cmp     #1  ; WRITE bit in carry
            lda     kernel.stream.entry.device,x
            bcc     _reading
            bcs     _writing
_reading    
            jsr     platform.iec.TALK
            lda     kernel.stream.entry.channel,x
            jmp     platform.iec.DEV_SEND
_writing    
            jsr     platform.iec.LISTEN
            lda     kernel.stream.entry.channel,x
            jmp     platform.iec.DEV_RECV

read_delay
    ; Y->args/event

          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Mount the embedded buffer
            jsr     mount_buf
            
          ; "Read" in the delayed byte from the open.
            lda     kernel.stream.entry.delay,x
            sta     (kernel.dest)

          ; Set the buflen
            lda     #1
            sta     kernel.event.entry.file.data.read,y

          ; The next Read call will be normal.
            lda     #state.DATA
            sta     kernel.stream.entry.state,x

          ; Return success
            lda     #kernel.event.file.DATA
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque


read_data
    ; Y->args/event

          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Fast fail if EOF encountered
            sec
            lda     kernel.stream.entry.eof,x
            bne     _out

          ; Mount the embedded buffer
            jsr     mount_buf
            
          ; Limit the requested byte count
            lda     kernel.fs.args.requested,y
            beq     _limit  ; Zero is max
            cmp     #64
            bcc     _read
_limit
            lda     #64

          ; Read what we can
_read       sta     requested
            phy
            ldy     #0

_loop       jsr     platform.iec.IECIN
            bcs     _err
            sta     (kernel.dest),y
            iny
            bvs     _eof    ; Received EOI
            cpy     requested
            bne     _loop
_done
          ; Set the buflen
            tya
            ply
            sta     kernel.event.entry.file.data.read,y

          ; Send the event
            lda     #kernel.event.file.DATA
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque
_eof
          ; mark the stream as in EOF
            dec     kernel.stream.entry.eof,x

          ; Signal the received data
            bra     _done

_err
            ply

          ; mark the stream as in EOF
            dec     kernel.stream.entry.eof,x

            lda     #kernel.event.file.ERROR
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque

_out
          ; Report the EOF as a separate response event.
            lda     #kernel.event.file.EOF
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque


read_volume      

        ; TODO: populate the extended statistics

          ; X->steam
            ldx     kernel.fs.args.stream,y

          ; Fast fail if EOF encountered
            sec
            lda     kernel.stream.entry.eof,x
            bne     _eof

          ; Next call should read a DIRENT
            lda     #state.DIRENT
            sta     kernel.stream.entry.state,x

          ; Mount the buffer
            jsr     mount_buf

          ; Read the entry
            phy
            jsr     _read
            tya
            ply
            bcs     _err

          ; Set the read length
            sta     kernel.event.entry.directory.volume.len,y            

          ; Set the extended data
            stz     kernel.dest+0
            lda     kernel.event.entry.ext,y
            sta     kernel.dest+1
            lda     id+0
            sta     (kernel.dest)
            inc     kernel.dest
            lda     id+1
            sta     (kernel.dest)
            
          ; Set the event type
            lda     #kernel.event.directory.VOLUME
            bra     _send
_eof        
            lda     #kernel.event.directory.EOF
            bra     _send            
_err        
            lda     #kernel.event.directory.ERROR
_send
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque

_read
          ; Skip the load address
            jsr     read_pair
            bcs     _err
            
          ; Skip the link pair
            jsr     read_pair
            bcs     _err
            
          ; Read the block count
            jsr     read_pair
            bcs     _err

          ; Read the volume string.
            jsr     read_volname
            bcs     _err

          ; skip 1 byte
            jsr     read   

          ; Read the disk ID
            jsr     read
            sta     id+0
            jsr     read
            sta     id+1

          ; eat the rest of the line
_loop       jsr     read
            bne     _loop

            rts                
                
read_volname
          ; Skip to the first quote
            jsr     find_quote
            bcs     _out

          ; Read the 16-byte body (could include quotes...)
            ldy     #0 
_loop       jsr     read
            sta     (kernel.dest),y 
            iny
            cpy     #16
            bne     _loop

          ; trim
            jsr     _trim
              
          ; Read the trailing quote  
            jsr     read
_out
            rts

_trim
            dey
            beq     _trimmed
            lda     (kernel.dest),y
            cmp     #' '
            beq     _trim
            iny
_trimmed    rts                
                
read_quoted
            jsr     find_quote
            bcs     _err
            ldy     #0
_loop       jsr     read
            sta     (kernel.dest),y
            iny
            beq     _err
            eor     #$22
            bne     _loop
_done                
            dey
            rts
_err            
            sec
            rts

find_quote
            jsr     read    ; returns for us
            eor     #$22
            bne     find_quote 
            rts

read
            lda     kernel.stream.entry.eof,x
            bne     _err 

            jsr     platform.iec.IECIN
            bcs     _err
            bvc     _out

            dec     kernel.stream.entry.eof,x
_out
            rts
_err
          ; Return to the caller's caller.
            sec
            pla
            pla
            rts                


read_dirent; TODO: on free, set next event to EOF
        
          ; X->stream
            ldx     kernel.fs.args.stream,y

          ; Fast fail if EOF encountered
            sec
            lda     kernel.stream.entry.eof,x
            bne     _eof

            jsr     mount_buf

          ; Zero link header implies end-of-file
            jsr     read_pair
            bcs     _err
            lda     id+0
            ora     id+1
            beq     _err

          ; Next pair is file size or free blocks count
            jsr     read_pair
            bcs     _err

          ; Entry contains either a quoted string or 'BLOCKS FREE.'.
            phy
            jsr     read_quoted
            tya
            ply
            bcs     _last

          ; Set the read length
            sta     kernel.event.entry.directory.file.len,y 

          ; Eat the rest of the line
_loop       jsr     read
            bne     _loop

          ; Set the extended data
            stz     kernel.dest+0
            lda     kernel.event.entry.ext,y
            sta     kernel.dest+1
            lda     id+0
            sta     (kernel.dest)
            inc     kernel.dest
            lda     id+1
            sta     (kernel.dest)
            
          ; Report the entry as a DIRENT
            lda     #kernel.event.directory.FILE
            bra     _send

_last
          ; Set the extended data
            stz     kernel.dest+0
            lda     kernel.event.entry.ext,y
            sta     kernel.dest+1
            lda     id+0
            sta     (kernel.dest)
            inc     kernel.dest
            lda     id+1
            sta     (kernel.dest)

          ; Set EOF and report the entry as an FS_FREE
            dec     kernel.stream.entry.eof,x
            lda     #kernel.event.directory.FREE
            bra     _send

_eof
            lda     #kernel.event.directory.EOF
            bra     _send
_err
            lda     #kernel.event.directory.ERROR
            bra     _send
_send
            sta     kernel.event.entry.type,y
            jmp     kernel.event.enque

read_pair
          ; read the link header
            jsr     read
            sta     id+0    ; # blocks LSB
            jsr     read
            sta     id+1    ; # blocks MSB
            rts

mount_buf

        stz     kernel.dest+0
        lda     kernel.event.entry.buf,y
        sta     kernel.dest+1

_out    rts

rename

      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Always uses the command channel.
        lda     #$0f
        sta     kernel.stream.entry.channel,x
        
      ; 'R' for "Rename"
        lda     #cmd_str.rename
        sta     cmd

    ; We need to do this one a little differently
    
        lda     kernel.stream.entry.device,x
        jsr     platform.iec.LISTEN
        bcs     _err

        lda     kernel.stream.entry.channel,x
        jsr     platform.iec.OPEN
        bcs     _err

      ; Set the new name info and append
        stz     fname+0
        lda     kernel.fs.args.ext,y
        sta     fname+1
        lda     kernel.fs.args.fulfilled,y
        sta     fnlen      
        jsr     send_name
        bcs     _err

      ; Magic syntax...
        lda     #'='
        jsr     platform.iec.IECOUT
        bcs     _err
        
      ; Set the old name info
        stz     fname+0
        lda     kernel.fs.args.buf,y
        sta     fname+1
        lda     kernel.fs.args.requested,y
        sta     fnlen
        jsr     send_name_string
        bcs     _err
    
      ; TODO: these delays may be bogus ... my hardware is failing    
        jsr     platform.iec.sleep_1ms          ; for the SD2IEC
        jsr     platform.iec.sleep_1ms          ; for the SD2IEC
        jsr     platform.iec.UNLISTEN
        bcs     _err
        
      ; Not sure how to know when it's done.
      ; Anecdotally, a status request will hang until completed.
        jsr     platform.iec.sleep_1ms          ; for the SD2IEC
        jsr     platform.iec.sleep_1ms          ; for the SD2IEC
        lda     kernel.stream.entry.device,x    ; TODO: move here &c
        jsr     platform.iec.request_status
        bcs     _err
        
      ; Send the event
        lda     #kernel.event.file.RENAMED
        sta     kernel.event.entry.type,y
        bra     _out
_err
        lda     #kernel.event.file.ERROR
        sta     kernel.event.entry.type,y

_out
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque

delete
   
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Always uses the command channel.
        lda     #$0f
        sta     kernel.stream.entry.channel,x
        
      ; 'S' for "Scratch"
        lda     #cmd_str.delete
        sta     cmd

      ; Set the filename info
        stz     fname+0
        lda     kernel.fs.args.buf,y
        sta     fname+1
        lda     kernel.fs.args.requested,y
        sta     fnlen

      ; Send a named open
        jsr     open_name
        bcs     _err

      ; Not sure how to know when it's done.
      ; Anecdotally, a status request will hang until completed.
        lda     kernel.stream.entry.device,x    ; TODO: move here &c
        jsr     platform.iec.request_status
        bcs     _err

      ; Send the event
        lda     #kernel.event.file.DELETED
        sta     kernel.event.entry.type,y
        bra     _out

_err
        lda     #kernel.event.file.ERROR
        sta     kernel.event.entry.type,y

_out
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque

mkfs:
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Always uses the command channel.
        lda     #$0f
        sta     kernel.stream.entry.channel,x
        
      ; 'N' for new.
        lda     #cmd_str.mkfs
        sta     cmd

      ; Set the filename info
        stz     fname+0
        lda     kernel.fs.args.buf,y
        sta     fname+1
        lda     kernel.fs.args.requested,y
        sta     fnlen

      ; Send a named open
        jsr     open_name
        bcs     _err

      ; Not sure how to know when it's done.
      ; Anecdotally, a status request will hang until completed.
        lda     kernel.stream.entry.device,x    ; TODO: move here &c
        jsr     platform.iec.request_status
        bcs     _err

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


format:
      ; An IEC format is just a mkfs with an extra argument, which the
      ; user can actually supply.  The only challenge is, we can't block
      ; that long, so for now, this function will just return an error,

_err
        lda     #kernel.event.fs.ERROR
        sta     kernel.event.entry.type,y

_out
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque


mkdir
   
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Always uses the command channel.
        lda     #$0f
        sta     kernel.stream.entry.channel,x

      ; Set the filename info
        jsr     parse_name        

      ; Set the command.
        lda     #cmd_str.mkdir
        sta     cmd

      ; Send a named open
        jsr     open_name
        bcs     _err

      ; Not sure how to know when it's done.
      ; Anecdotally, a status request will hang until completed.
        lda     kernel.stream.entry.device,x    ; TODO: move here &c
        jsr     platform.iec.request_status
        bcs     _err

      ; Send the event
        lda     #kernel.event.directory.CREATED
        sta     kernel.event.entry.type,y
        bra     _out

_err
        lda     #kernel.event.directory.ERROR
        sta     kernel.event.entry.type,y

_out
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque

rmdir
   
      ; Extract what we need from the arg
        ldx     kernel.fs.args.stream,y

      ; Always uses the command channel.
        lda     #$0f
        sta     kernel.stream.entry.channel,x
        
        lda     #cmd_str.rmdir
        sta     cmd

      ; Set the filename info
        jsr     parse_name        

      ; Send a named open
        jsr     open_name
        bcs     _err

      ; Not sure how to know when it's done.
      ; Anecdotally, a status request will hang until completed.
        lda     kernel.stream.entry.device,x    ; TODO: move here &c
        jsr     platform.iec.request_status
        bcs     _err

      ; Send the event
        lda     #kernel.event.directory.DELETED
        sta     kernel.event.entry.type,y
        bra     _out

_err
        lda     #kernel.event.directory.ERROR
        sta     kernel.event.entry.type,y

_out
        txa
        jsr     kernel.stream.free
        jmp     kernel.event.enque

        .send
        .endn
        .endn

