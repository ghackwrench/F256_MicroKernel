; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu    "r65c02"

            .namespace  kernel
            .namespace  fs

fs_iec      .namespace

            .section    kmem
id          .word       ?
eof         .byte       ?
writing     .byte       ?
sa          .byte       ?
            .send           

            .section    kernel

init
            jmp     platform.iec.IOINIT

open
    jsr platform.iec.sleep_300us
    jsr platform.iec.sleep_300us
    jsr platform.iec.sleep_300us
    jsr platform.iec.sleep_300us
    jsr platform.iec.sleep_300us
    jsr platform.iec.sleep_300us
    
            stz     eof
            stz     sa
            stz     writing

            jsr     open_read_name
            bcs     _out

            lda     #8
            jsr     platform.iec.TALK
            bcs     _out

            lda     sa
            jsr     platform.iec.DEV_SEND
            bcs     _out

.if false
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
.endif                        
          ; Hacky
            lda     #kernel.event.FS_OPENED
            ldy     #0
            stz     kernel.dest+1
            jsr     send_event
_out            
            rts

report
            php
            phy
            ldy     #0
_loop       lda     _txt,y
            beq     _done
            jsr     platform.console.puts
            iny
            bra     _loop
_done
            ply         
            plp
            rts
_txt        .null   "finished sent TALK"

open_read_name
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us


            lda     #8          ; device
            jsr     platform.iec.LISTEN  ; Carry set on dead bus
            bcs     _err

            lda     sa          ; channel        
            jsr     platform.iec.OPEN
            bcs     _err

            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
                        
            ldy     #0
_loop       lda     _fname,y
            beq     _done
            jsr     platform.iec.IECOUT
            bcs     _err
            iny
            bra     _loop
_done
            jsr     platform.iec.UNLISTEN
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            
_err
            rts
            
_fname          
            .null   "$"

open_write
            stz     eof
            lda     #1
            sta     sa
            sta     writing

            jsr     open_write_name

            lda     #8
            jsr     platform.iec.LISTEN

            lda     sa
            jsr     platform.iec.DEV_RECV
            bcs     _out
            
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            
          ; Hacky
            lda     #kernel.event.FS_WROTE
            ldy     #0
            stz     kernel.dest+1
            jsr     send_event
_out            
            rts

open_write_name
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            
            lda     #8          ; device
            jsr     platform.iec.LISTEN  ; Carry set on dead bus

            lda     sa          ; channel        
            jsr     platform.iec.OPEN

     jsr platform.iec.sleep_1ms


            ldy     #0
_loop       lda     _fname,y
            beq     _done
            jsr     platform.iec.IECOUT
            iny
            bra     _loop
_done
            jsr     platform.iec.UNLISTEN
            
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            
            rts
            
_fname          
            .null   "@:T"

close
            lda     writing
            bne     _unlisten
            beq     _untalk
_unlisten
            jsr     platform.iec.UNLISTEN ;/3F
            bra     _close2
_untalk
            jsr     platform.iec.UNTALK  ;/5F
            bra     _close2
                
_close2

            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            jsr     platform.iec.sleep_300us
            

            lda     #8
            jsr     platform.iec.LISTEN

            lda     sa
            jsr     platform.iec.CLOSE
                
            jsr     platform.iec.UNLISTEN

          ; Hacky
            lda     #kernel.event.FS_CLOSED
            ldy     #0
            stz     kernel.dest+1
            jsr     send_event

            rts


read_data

          ; Fast fail if EOF encountered
            sec
            lda     eof
            bne     _err

          ; Allocate a buffer
            jsr     alloc_buf
            bcs     _err

          ; Read what we can
            ldy     #0
_loop       jsr     platform.iec.IECIN
            sta     (kernel.dest),y
            iny
            bvs     _eof    ; Received EOI
            cpy     #254    ; Sectors contain 254 bytes of data.
            bne     _loop            
_done
          ; Signal data available
            lda     #kernel.event.FS_DATA
            jmp     send_event

_eof
          ; mark the stream as in EOF
            dec     eof

          ; Signal the received data
            jsr     _done

          ; Signal eof
            lda     #kernel.event.FS_EOF
            stz     kernel.dest+1
            ldy     #0
            jmp     send_event
            
_err
            rts            
            


write_data

          ; Write 0..9
            ldy     #0
_loop       tya
            jsr     platform.iec.IECOUT
            iny
            cpy     #10
            bne     _loop

          ; signal completion
            lda     #kernel.event.FS_WROTE
            ldy     #0
            stz     kernel.dest+1
            jmp     send_event
        
read_volume      
          ; Allocate a buffer
            jsr     alloc_buf
            bcs     _out

          ; Read the entry
            jsr     _read
            bcs     _err

          ; Send the event and return
            lda     #kernel.event.FS_VOLUME
            jmp     send_event
            
_err        jmp     free_buf    ; TODO: send an error event!!!

_out        rts

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
            lda     eof
            bne     _err 

            jsr     platform.iec.IECIN
            bcs     _err
            bvc     _out
            dec     eof
_out
            rts
_err
          ; Return to the caller's caller.
            sec
            pla
            pla
            rts                


read_dirent
            jsr     alloc_buf
            bcs     _out

            jsr     _read
            bcs     _err

            pha
            jsr     send_event
            pla
            rts

_err        jmp     free_buf            

_read                            
          ; Zero link header implies end-of-file
            jsr     read_pair
            bcs     _out
            lda     id+0
            ora     id+1
            beq     _out

          ; Next pair is file size or free blocks count
            jsr     read_pair
            bcs     _out

          ; Entry contains either a quoted string or 'BLOCKS FREE.'.
            jsr     read_quoted
            bcs     _last

          ; Eat the rest of the line
_loop       jsr     read
            bne     _loop

          ; Report the entry as a DIRENT
            lda     #kernel.event.FS_DIRENT
            rts

          ; Report the entry as an FS_FREE
_last
            clc
            lda     #kernel.event.FS_FREE
            ldy     #0
            rts

_out        
            rts                                

read_pair
          ; read the link header
            jsr     read
            sta     id+0    ; # blocks LSB
            jsr     read
            sta     id+1    ; # blocks MSB
            rts

                
alloc_buf
      ; Allocate and set the event buffer
        jsr     kernel.page.alloc_a
        bcs     _out

      ; Mount it at kernel.dest
        stz     kernel.dest+0
        sta     kernel.dest+1

_out    rts

free_buf
        lda     kernel.dest+1
        jsr     kernel.page.free
        sec
        rts

alloc_event
        ; Returns event in Y
        jmp     kernel.event.alloc

alloc_ext_event
        pha
        jsr     kernel.event.alloc
        bcs     _out
        tya
        jsr     kernel.event.alloc
        bcc     _okay
        tay
        jsr     kernel.event.free
        sec     ; TODO: free should probably preserve the carry
        bra     _out
_okay
        sta     kernel.event.entry.ext,y
_out
        pla
        rts        


send_event
    ; A = event type, Y = buflen
    ; kernel.dest = buffer

      ; Stash the buflen
        phy

      ; Alloc an event
        jsr     kernel.event.alloc
        bcs     _err

      ; Set the event type
        sta     kernel.event.entry.type,y

      ; Set the buffer
        lda     kernel.dest+1
        sta     kernel.event.entry.buf,y
        
      ; Set the buflen
        pla
        sta     kernel.event.entry.fs.volume.len,y

      ; Set the blocks
        lda     id+0
        sta     kernel.event.entry.fs.dirent.blocks+0,y
        lda     id+1
        sta     kernel.event.entry.fs.dirent.blocks+1,y

      ; Queue and return
        jmp     kernel.event.enque
        
_err
        ply
        jmp     free_buf


        .send
        .endn
        .endn
        .endn
