; This file is part of the TinyCore MicroKernel for the Foenix F256.
; Copyright 2022, 2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>.
; SPDX-License-Identifier: GPL-3.0-only

            .cpu        "w65c02"


mkstr       .segment   label, data
            .section    kernel2
\1_msg      .null       \2
            .send
            .section    strings
\1_ptr      .word       \1_msg
            .send
\1_str      = <\1_ptr            
            .endm                   

            .namespace  hardware


            .mkstr      ps2,    "ps2   "
            .mkstr      green,  "green "
            .mkstr      purple, "purple"
            .mkstr      fpga,   "fpga  "            

            ;.mkstr      ack,    "Received an ack ($fa)."
            ;.mkstr      echo,   "Received an echo reply ($ee)."
            ;.mkstr      resend, "Received a resent request ($fe)."
            ;.mkstr      passed, "Received a self-test passed ($aa)."
            .mkstr      data,   "rx #."
            .mkstr      txd,    "tx #."
            .mkstr      mouse,  "Standard PS2 mouse detected."
            .mkstr      intel,  "Intellimouse detected."
            .mkstr      mode1,  "Mode-1 keyboard detected."
            .mkstr      mode2,  "Mode-2 keyboard detected."
            .mkstr      auto,   "Detecting device based on activity."
            .mkstr      iwait,  "Waiting for ident bytes."
            .mkstr      imatch, "Matching ident bytes."
            .mkstr      upgrade,"Requesting Intellimouse upgrade."
            .mkstr      ps2err, "FPGA lost sync; disabling device."
            

ps2         .namespace
auto        .namespace

self        .namespace
            .virtual    DevState
this        .byte   ?   ; self     

          ; Received data
rx1         .byte   ?   ; first received byte after ack
rx2         .byte   ?   ; second received byte after ack
rx3         .byte   ?   ; third received byte after ack
rx4         .byte   ?   ; fourth byte received
rx_count    .byte   ?   ; count of data bytes received.

click_count .byte   ?
click_state .byte   ?

            .fill   248

wait_state  .byte   ?   ; Current wait state
kbd_lower               ; Keyboard driver.
mouse_type  .byte   ?   ; Last known mouse type.

          ; Receiver state-machine
rx_state    .byte   ?   ; Current receive state
sending     .byte   ?   ; Data being sent
retry_count .byte   ?   ; Number of retry attempts
arg         .byte   ?   ; Argument
next_action .byte   ?   ; Next action
handler     .byte   ?   ; Current device handler

            .endv
            .endn

            .section    kernel2

log_data = false
RETRIES  = 3

init:
    ; X->this
            txa
            sta     self.this,x
            stz     self.click_state,x
            stz     self.click_count,x
            jmp     idle

open:
    ; X->this

          ; Idle the receive state machine.
            jsr     idle

.if false
          ; TODO: fix the bloody i8042 core...
          ; HACK: If we're direct-booting into BASIC, skip
          ; device init and jump directly to auto-detect.
            jsr     platform.dips.read
            bit     #platform.dips.BOOT_MENU
            bne     _full_init
            
            lda     #rx.auto
            sta     self.rx_state,x
            sta     self.handler,x
            bra     _out
.endif

_full_init
          ; Schedule an init
            lda     #wait.init
            sta     self.wait_state,x
            lda     #40
            jsr     kernel.delay.insert

_out        
            clc
            rts

            
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Commands

idle
          ; Just count and ring the incoming bytes.
            lda     #rx.idle
            sta     self.rx_state,x
            sta     self.handler,x
            rts

reset
          ; Mark the mouse type as unidentified.
            lda     #$ff
            sta     self.mouse_type,x

          ; Set the success action to action_wait_reset
            lda     #action.wait_reset
            sta     self.next_action,x

          ; Send a reset command.
            lda     #$ff
            bra     send_command

identify
          ; Set the success action to action_wait_ident
            lda     #action.wait_ident
            sta     self.next_action,x

          ; Send the command.
            lda     #$f2
            bra     send_command

auto_detect
            jsr     auto_wait

            lda     self.sending,x
            cmp     #$f4
            bne     _enable
            rts
            
_enable
            lda     #auto_str
            jsr     kernel.log.dev_message

          ; Send a reset/scan-enable.
            lda     #$ff
            lda     #$f4
            jmp     send_command

auto_wait
          ; Resume to the auto-detect state machine.
            lda     #rx.auto
            sta     self.handler,x
            sta     self.rx_state,x
            lda     #action.resume
            sta     self.next_action,x

            rts
            
send_command
    ; Send the command byte in A, wait for an ACK, and resume.

          ; Stuff the command into 'sending'.
            sta     self.sending,x

          ; Set the rx state machine to rx_until_ack.
            lda     #rx.until_ack
            sta     self.rx_state,x

          ; Send the command.
            lda     #RETRIES
            sta     self.retry_count,x
            lda     self.sending,x
            jmp     send
            
send_command_with_arg
    ; Send the command byte in A, arg in Y.

          ; Stuff the command in 'sending'.
            sta     self.sending,x

          ; Stuff the arg in 'arg'.
            tya
            sta     self.arg,x

          ; Set the success action to action_send_arg.
            lda     #action.send_arg
            sta     self.next_action,x
            
          ; Switch the state machine to rx_until_ack.
            lda     #rx.until_ack
            sta     self.rx_state,x
            
          ; Send the command.          
            lda     #RETRIES
            sta     self.retry_count,x
            lda     self.sending,x
            jmp     send
            
send
.if log_data
            pha
            tay
            lda #txd_str
            jsr kernel.log.dev_message
            pla
.endif            
            jmp     kernel.device.dev.fetch ; TODO: rename upper
            

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Ack handlers; mostly called from the rx handler.

action      .struct
identify    .word   action_identify
wait_reset  .word   action_wait_reset
wait_ident  .word   action_wait_ident
send_arg    .word   action_send_arg
upgrade     .word   action_upgrade_mouse
resume      .word   action_resume
            .ends

action_identify
            ldx     self.this,y
            jmp     identify        

action_wait_reset
            ldx     self.this,y
            
          ; Set the state machine to gather bytes.
            lda     #rx.idle
            sta     self.rx_state,x
            stz     self.rx_count,x ; Track number of bytes received.

          ; Call wait.reset on timeout.
            lda     #wait.reset
            sta     self.wait_state,x

          ; Request the timeout.
            lda     #30    ; Be really generous.
            jmp     kernel.delay.insert
            
action_wait_ident
            ldx     self.this,y

    ;lda #iwait_str
    ;jsr kernel.log.dev_message
            
          ; Set the state machine to gather bytes.
            lda     #rx.idle
            sta     self.rx_state,x
            stz     self.rx_count,x ; Track number of bytes received.

          ; Call wait.ident on timeout.
            lda     #wait.ident
            sta     self.wait_state,x

          ; Request the timeout.
            lda     #4  ; Probably plenty.
            jmp     kernel.delay.insert

action_send_arg
    ; Send self.arg; on success, resume.

            ldx     self.this,y

          ; On success, resume device handler.
            lda     #action.resume
            sta     self.next_action,x

          ; Set byte to send (for retry)
            lda     self.arg,x
            sta     self.sending,x

          ; Send the byte
            jmp     send

action_upgrade_mouse
            ldx     self.this,y
            
            lda     #action.upgrade
            sta     self.next_action,x

            ldy     self.arg,x
            inc     self.arg,x
            lda     _mouse,y
            beq     _done
            jmp     send_command
_done
            jmp     identify
_mouse
            .byte   $f3, 200, $f3, 100, $f3, 80, 0

            
            
action_resume
          ; Switch the rx state machine back to the device handler.
            lda     self.handler,y
            sta     self.rx_state,y
            rts


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; wait handlers

wait        .struct
init        .word   wait_init
reset       .word   wait_reset
ident       .word   wait_ident
clicks      .word   wait_clicks
            .ends

dev_status
          ; Chain to the handler.        
            ldy     self.this,x
            ldx     self.wait_state,y
            jmp     (_table,x)

_table      .dstruct    wait

            
wait_init
    ; The init delay timer has expired; send a reset.
            ldx     self.this,y
            jmp     reset

wait_reset
    ; We've given the device time to perform a self-test.
    ; Ideally, rx4 = $aa, or rx3/rx4=$aa/$00.
    ; Otherwise, the device failed to resent, and we should switch
    ; to auto-detect.

            ldx     self.this,y

            lda     self.rx4,x

          ; Keyboard self-test passed.
            cmp     #$aa
            beq     _ident
            
          ; Mouse self-test passed
            cmp     #$00
            bne     _auto   ; nope
            lda     self.rx3,x
            cmp     #$aa
            bne     _auto   ; nope

_ident
          ; Call identify after the next command is ack'd.
            lda     #action.identify
            sta     self.next_action,x

          ; Send command: Disable data reporting.
            lda     #$f5    ; Stop scanning

          ; Some keyboards stop understanding our messages during ident.
          ; Instead of disabling reporting during the ident phase,
          ; send a dummy command and just live with any possible
          ; interference...
            lda #$f6 ; Reset, leave the keyboard scanning.
            jmp     send_command
            
_auto
            jmp     auto_detect

wait_ident
    ; We've given the device time to spew its ident bytes.

            ldx     self.this,y

    lda #imatch_str
    ;jsr kernel.log.dev_message

          ; If device didn't identify itself, auto-detect.
            lda     self.rx_count,x
            beq     _auto
          
          ; Pre-identify by response count.
            cmp     #2
            beq     _keyboard
            bcs     _auto

          ; A one-byte identity should be a mouse.
_mouse
            lda     self.rx4,x
            beq     _std
            cmp     #3
            bcc     _auto
            cmp     #5
            cmp     #4      ; Don't handle 5-button yet
            bcs     _auto

_intelli
          ; Intellimouse.
            lda     #intel_str
            jsr     kernel.log.dev_message
           
            lda     #rx.intelli
            sta     self.handler,x
            bra     _found

_std
          ; Std PS2 mouse.
            lda     #mouse_str
            jsr     kernel.log.dev_message

            lda     #rx.std_mouse
            sta     self.handler,x
            ; fall through to found
            
_found
            lda     self.rx4,x

          ; If it's the same type as last time, we're done.
            cmp     self.mouse_type,x
            beq     _enable
            
          ; If it's mode 3, we're done.
            cmp     #3
            beq     _enable

          ; Save the new type.
            sta     self.mouse_type,x

          ; Try to upgrade
            tay
            lda     #upgrade_str
            jsr     kernel.log.dev_message
            stz     self.arg,x
            ldy     self.this,x
            jmp     action_upgrade_mouse

_enable
          ; Reset the counter (now packet length).
            stz     self.rx_count,x

          ; Enable reporting
            lda     #action.resume
            sta     self.next_action,x      
            lda     #$f4
            jmp     send_command

_keyboard
            lda     self.rx3,x
            cmp     #$ab
            bne     _auto

            lda     self.rx4,x
            cmp     #$83
            bne     _auto
            
            lda     #mode2_str
            jsr     kernel.log.dev_message

            jsr     hardware.kbd2.init
            lda     #rx.keyboard
            sta     self.handler,x
            jmp     _enable

_auto
            lda     #auto_str
            jsr     kernel.log.dev_message

            lda     #rx.auto
            sta     self.handler,x

  lda #$ff
  ldy #$f4
  jmp send_command_with_arg


            jmp     _enable

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; rx handlers

            ; Receiver states.
rx          .struct
idle        .word   rx_idle 
auto        .word   rx_auto
until_ack   .word   rx_until_ack
std_mouse   .word   rx_std_mouse
intelli     .word   rx_intellimouse
keyboard    .word   rx_keyboard
            .ends

dev_data
.if log_data
            pha
            tay
            lda     #data_str
            jsr     kernel.log.dev_message
            pla
.endif

.if false
            pha
            phx
            lda     self.port,x
            ora     #48
            tax
            lda     kernel.ticks
            jsr     platform.console.poke
            plx
            pla
.endif            

          ; Todo: check for hot-plug

          ; Chain to the handler.
            ldy     self.this,x
            ldx     self.rx_state,y
            jmp     (_table,x)
            
_table      .dstruct    rx

rx_idle
    ; Track the past four received bytes.
            ldx     self.this,y

          ; Buffer the data.
            tay
            lda     self.rx2,x
            sta     self.rx1,x
            lda     self.rx3,x
            sta     self.rx2,x
            lda     self.rx4,x
            sta     self.rx3,x
            tya
            sta     self.rx4,x

          ; Update the count.
            inc     self.rx_count,x

            rts

rx_until_ack
            ldx     self.this,y
            
            cmp     #$fa        ; ack
            beq     _ack

            cmp     #$fe        ; resend
            beq     _resend

            cmp     #$aa        ; Device reset
            beq     _reset

          ; TODO: fix the i8042
          ; Disabling the port (below) is great for debugging,
          ; but for now, ignore failures...
            bra     _ack

          ; If we get anything else, the FPGA has gone off
          ; the rails, and, outside of a full port reset,
          ; there's nothing we can do, so drop the port.
            lda     #ps2err_str
            jsr     kernel.log.dev_message
            lda     #rx.idle
            sta     self.rx_state,x
            sta     self.handler,x
            lda     #wait.reset
            sta     self.wait_state,x
            rts
            
_reset
          ; Did we request a reset?
            lda     self.sending,x
            cmp     #$ff
            bne     _auto

          ; Device reset w/out ACKing the request.
            ldy     self.this,x
            jsr     action_wait_reset
            ldx     self.this,y
            lda     #$aa
            bra     dev_data
            
_resend
            dec     self.retry_count,x
            bne     _send

            lda     self.sending,x
            cmp     #$f4
            bne     _auto
            jmp     auto_wait   ; Hopefully we got through.

_auto
            ;jmp     reset
            jmp     auto_detect ; Give up and auto-detect

_send       lda     self.sending,x
            jmp     send        

_ack
            ldy     self.this,x
            ldx     self.next_action,y
            jmp     (_table,x)

_table      .dstruct    action


rx_auto
            ldx     self.this,y
            jsr     rx_idle

          ; Mode1 keyboard?
_check1     lda     self.rx4,x
            bpl     _not1
            and     #$7f
            cmp     self.rx3,x
            beq     _mode1
_not1       nop
            
          ; Mode2 keyboard?  
_check2     lda     self.rx3,x
            cmp     #$f0    ; release
            bne     _not2
            lda     self.rx2,x
            cmp     self.rx4,x
            beq     _mode2
_not2       nop  
            
          ; Mouse?
            lda     self.rx1,x
            and     #$cf
            eor     #$08
            bne     _out
            
            lda     self.rx2,x
            ora     self.rx3,x
            beq     _out

            lda     self.rx4,x
            beq     Intellimouse
            
            and     #$cf
            eor     #$08
            beq     _mouse

_out        rts

_mode1
            rts
_mode2
            lda     #mode2_str
            jsr     kernel.log.dev_message
            
            jsr     hardware.kbd2.init
            lda     #rx.keyboard
            sta     self.rx_state,x
            lda     self.rx2,x
            jsr     rx_keyboard
            lda     self.rx3,x
            jsr     rx_keyboard
            lda     self.rx4,x
            jsr     rx_keyboard
            rts

_mouse
            lda     #mouse_str
            jsr     kernel.log.dev_message

            lda     #rx.std_mouse
            sta     self.rx_state,x
            sta     self.handler,x
            lda     #1  ; First byte received
            sta     self.rx_count,x
            rts

Intellimouse
            lda     #intel_str
            jsr     kernel.log.dev_message
           
            lda     #rx.intelli
            sta     self.handler,x
            rts


rx_keyboard
            jmp     hardware.kbd2.accept

rx_std_mouse

          ; Rotate in the next byte.
            jsr     rx_idle     ; x->self

          ; Act based on the byte count.
            lda     self.rx_count,x

          ; Std mouse packet is three bytes.
            cmp     #3
            beq     _accept
            bcs     _reset  ; 4+ is right out!
            
          ; First byte should have bit 3 set.
            cmp     #1
            bne     _out
            lda     self.rx4,x
            bit     #8
            beq     _reset
_out
            rts     ; Gather more data.

_accept
.if true
          ; Discard overflows
            lda     self.rx2,x
            bit     #$c0
            bne     _reset
.endif
          ; Convert to Intellimouse and chain.
            ldy     self.this,x
            lda     #0
            jsr     rx_idle
            jmp     mouse_accept            
_reset
            stz     self.rx_count,x
            bra     _out
             
rx_intellimouse ; TODO: discard overflows

          ; Rotate in the next byte.
            jsr     rx_idle

          ; Act based on the byte count.
            lda     self.rx_count,x

          ; Intellimouse packet is four bytes.
            cmp     #4
            beq     mouse_accept
            bcs     _reset  ; 5+ is right out!
            
          ; First byte should have bit 3 set.
            cmp     #1
            bne     _out
            lda     self.rx4,x
            bit     #8
            bne     _out
_reset
            stz     self.rx_count,x
_out
            rts     ; Gather more data.
            
normalize
        ; Mask off the non-button bits of A;
        ; Reverse the bits when the mouse is left-handed.
            and     #7
            bit     self.click_count,x
            bpl     _done
            phy
            tay
            lda     _reverse,y
            ply
_done       rts
_reverse    .byte   0,2,1,3,4,6,5,7  


mouse_accept

        ; In theory, we should update the mouse
        ; pointer here so it's always smooth.
        ; In practice, we are letting the user
        ; do everything.

          ; Always accept the packet
            stz     self.rx_count,x
            
          ; Report the raw state
            jsr     mouse_report

          ; If we're counting clicks, chain to the click counter.
            lda     self.wait_state,x
            cmp     #wait.clicks
            beq     count_clicks

          ; If self.click_state is still holding a button press,
          ; wait until something changes.
            lda     self.rx1,x
            eor     #$ff
            eor     self.click_state,x
            and     #7
            beq     _done
          
          ; If this is a new button press, start the counter.
            lda     self.rx1,x
            and     #7
            bne     mouse_click

          ; The state is clear; re-enable the new press check.
            eor     #$ff
            sta     self.click_state,x
_done
            rts

mouse_click
        ; User has activated a button;
        ; record the button states, and start the timer.

          ; Record the inverted button states
            eor     #$ff
            sta     self.click_state,x

          ; Zero the clicks count, preserving the handedness.
            lda     self.click_count,x
            and     #$80
            sta     self.click_count,x

          ; Grab the timer.
            lda     #wait.clicks
            sta     self.wait_state,x

          ; Schedule a ~500ms timeout.
            lda     #25
            jmp     kernel.delay.insert 
            

count_clicks:

          ; Grab a copy of the previous state
            ldy     self.click_state,x

          ; Update the previous state with the new state.
            lda     self.rx1,x
            eor     #$ff
            sta     self.click_state,x

          ; Find the buttons that have changed
            tya                         ; Old state
            eor     self.click_state,x  ; new state

          ; Keep the buttons that are now released (1s)
            and     self.click_state,x
            
          ; Normalize and count
            jsr     normalize

_inside
            bit     #1
            beq     _outside
            inc     self.click_count,x
_outside
            bit     #2
            beq     _middle
            inc     self.click_count,x
            inc     self.click_count,x
            inc     self.click_count,x
            inc     self.click_count,x
_middle
            bit     #4
            beq     _done

            lda     self.click_count,x
            clc
            adc     #16
            sta     self.click_count,x
_done
            rts

wait_clicks
        ; The click timer has expired; let's see where we are.

          ; Switch back to X
            ldx     self.this,y
        
          ; Reset the timer handler, so the mouse handler
          ; stops counting.
            stz     self.wait_state,x

          ; If this was a clean, off-hand double-click, swap.
            lda     self.click_count,x
            and     #$7f
            cmp     #8
            bne     _report


          ; Swap hands; move outside count to inside.
            lda     self.click_count,x
            eor     #$80
            cmp     #$80
            ror     a
            cmp     #$80
            ror     a
            and     #$83            
            sta     self.click_count,x

_report
          ; Generate the report
          ; Allocate the event
            jsr     kernel.event.alloc
            bcs     _drop

          ; Send an event reporting the clicks
            lda     #kernel.event.mouse.CLICKS
            sta     kernel.event.entry.type,y

            lda     self.click_count,x
            and     #3
            sta     kernel.event.entry.mouse.clicks.inner,y

            lda     self.click_count,x
            lsr     a
            lsr     a
            and     #3
            sta     kernel.event.entry.mouse.clicks.outer,y

            lda     self.click_count,x
            lsr     a
            lsr     a
            lsr     a
            lsr     a
            and     #3
            sta     kernel.event.entry.mouse.clicks.middle,y
.if false
 lda kernel.event.entry.mouse.clicks.inner,y
 ora #'0'
 jsr platform.console.puts
 lda kernel.event.entry.mouse.clicks.middle,y
 ora #'0'
 jsr platform.console.puts
 lda kernel.event.entry.mouse.clicks.outer,y
 ora #'0'
 jsr platform.console.puts
 lda #' '
 jsr platform.console.puts
.endif
            jmp     kernel.event.enque

_drop
            rts

mouse_report
        ; Just a movement change; report it.

          ; Allocate the event; loss of a delta is no big deal.
            jsr     kernel.event.alloc
            bcs     _out
            
          ; Fill type
            lda     #kernel.event.mouse.DELTA
            sta     kernel.event.entry.type,y
            
          ; Fill dx
            lda     self.rx1,x
            and     #%0001_0000
            clc
            adc     #$ff            ; sign bit in carry
            lda     self.rx2,x
            ror     a
            sta     kernel.event.entry.mouse.delta.x,y

          ; Fill dy
            lda     self.rx1,x
            and     #%0010_0000
            clc
            adc     #$ff            ; sign bit in carry
            lda     self.rx3,x
            ror     a
            eor     #$ff            ; invert delta
            inc     a
            sta     kernel.event.entry.mouse.delta.y,y

          ; Fill buttons
            lda     self.rx1,x
            jsr     normalize
            sta     kernel.event.entry.mouse.delta.buttons,y
          
          ; Fill dz
            lda     self.rx4,x
            and     #$0f
            cmp     #$1
            beq     _up
            cmp     #$0f
            bne     _report
_down       lda     #$ff
            bra     _setz
_up         lda     #$01
_setz       sta     kernel.event.entry.mouse.delta.z,y       

_report     jmp     kernel.event.enque
_out        rts               

            .send
            .endn
            .endn
            .endn
 
