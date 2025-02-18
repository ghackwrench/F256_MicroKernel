; This file is part of the TinyCore MicroKernel for the Foenix F256K2.
; Copyright 2024 <stef@c256foenix.com>.

            .cpu    "65816"

            .namespace  platform
k2lcd       .namespace

            .section    dp

            .send

            .section    kmem

            .send            

            ;.section    kernel
            .section    global

; F256K2 Splash LCD
LCD_CMD_CMD             = $DD40    ;Write Command Here
LCD_RST                 = $10      ; 0 to Reset (RSTn)
LCD_BL                  = $20      ; 1 = ON, 0 = OFF 
; Read Only
LCD_TE                  = $40      ; Tear Enable 
LCD_CMD_DTA             = $DD41    ;Write Data (For Command) Here
; Always Write in Pairs, otherwise the State Machine will Lock
LCD_PIX_LO              = $DD42    ; {G[2:0], B[4:0]}
LCD_PIX_HI              = $DD43    ; {R[4:0], G[5:3]}
LCD_CTRL_REG            = $DD44 
; On all new product there is a SPI Flash on board that hold Splash Screen Bootup Graphics! ;)
; THe SPI FLASH can only be read. (No circuit to go write, at least not now)
SPLASH_FLASH_SPI_CTRL   = $DD60
SPLASH_FLASH_SPI_CMD    = $DD61
SPLASH_FLASH_SPI_SIZLo  = $DD62
SPLASH_FLASH_SPI_SIZHi  = $DD63
SPLASH_FLASH_SPI_AD_Lo  = $DD64
SPLASH_FLASH_SPI_AD_Mi  = $DD65
SPLASH_FLASH_SPI_AD_Hi  = $DD66
SPLASH_FIFO_DATA_IN     = $DD68

init								; *** IMPORTANT -> If there is no LCD and if passes the Tests, the machine will hang, you need to have a LCD Installed ***
			lda     $d6a7			; Check the Machine ID, this needs to be done only for a K2 with Optical Keyboard 
			and     #$1F        	; Stefany - Make sure to isolate the MID only
			cmp     #$11        	; Stefany - K2 Optical Keyboard
			bne 	init_No_Splash	; 

	        lda     $ddc1       	; If the Unit is a K2, Then let's figure out which Keyboard is installed
            bmi     init_No_Splash  ; if the bit[7] is 1, then it is a Traditional Mechanical Keyboard, so it is like a F256K

									; Tests have been passed and so we may proceed

			;lda     #$00
			;sta     LCD_CTRL_REG	; We don't really a reset, it is already happened.						
			;jsr 	WAIT_100ms
			lda     #LCD_RST | LCD_BL
			sta     LCD_CTRL_REG			

			jsr 	LCD_1_69_Init			; Go Init the LCD
			jsr 	Splash_LCD_Download		; Go Get the SPI Flash Data and Feed the Display

init_No_Splash:
			rts

LCD_1_69_Init
			lda 	#$11
            sta 	LCD_CMD_CMD
			jsr 	WAIT_100ms
			jsr 	WAIT_100ms	
			; 36 Command
			lda 	#$36	; Viewing Side
            sta 	LCD_CMD_CMD
			lda 	#$00	; Vertical - 70 8 = Invert Color
			sta 	LCD_CMD_DTA
			; 3A Command
			lda 	#$3A
            sta 	LCD_CMD_CMD
			lda 	#$05
			sta 	LCD_CMD_DTA
			; B2 Command
			lda 	#$B2
            sta 	LCD_CMD_CMD
			lda 	#$0C
			sta 	LCD_CMD_DTA
			sta 	LCD_CMD_DTA
			lda 	#$00
			sta 	LCD_CMD_DTA
			lda 	#$33
			sta 	LCD_CMD_DTA
			sta 	LCD_CMD_DTA
			; B7 Command
			lda 	#$B7
            sta 	LCD_CMD_CMD
			lda 	#$35
			sta 	LCD_CMD_DTA
			; BB Command
			lda 	#$BB
            sta 	LCD_CMD_CMD
			lda 	#$35
			sta 	LCD_CMD_DTA
			; C0 Command
			lda 	#$C0
            sta 	LCD_CMD_CMD
			lda 	#$2C
			sta 	LCD_CMD_DTA
			; C2 Command
			lda 	#$C2
            sta 	LCD_CMD_CMD
			lda 	#$01
			sta 	LCD_CMD_DTA
			; C3 Command
			lda 	#$C3
            sta 	LCD_CMD_CMD
			lda 	#$13
			sta 	LCD_CMD_DTA
			; C4 Command
			lda 	#$C4
            sta 	LCD_CMD_CMD
			lda 	#$20
			sta 	LCD_CMD_DTA
			; C6 Command
			lda 	#$C6
            sta 	LCD_CMD_CMD
			lda 	#$0F
			sta 	LCD_CMD_DTA
			; D0 Command
			lda 	#$D0
            sta 	LCD_CMD_CMD
			lda 	#$A4
			sta 	LCD_CMD_DTA
			lda 	#$A1
			sta 	LCD_CMD_DTA
			; D6 Command
			lda 	#$D0
            sta 	LCD_CMD_CMD
			lda 	#$A4
			sta 	LCD_CMD_DTA
			; E0 Command
			ldx 	#$00
			lda 	#$E0
            sta 	LCD_CMD_CMD
Init_CMDE0_Loop:				
			lda 	LCD_Init_CMD_E0_SEQ, x
			sta 	LCD_CMD_DTA
		    inx 	
			cpx 	#size(LCD_Init_CMD_E0_SEQ)
			bne 	Init_CMDE0_Loop
			
			; E1 Command
			ldx 	#$00
			lda 	#$E1
            sta 	LCD_CMD_CMD
Init_CMDE1_Loop:				
			lda 	LCD_Init_CMD_E1_SEQ, x
			sta 	LCD_CMD_DTA
		    inx 	
			cpx 	#size(LCD_Init_CMD_E1_SEQ)
			bne 	Init_CMDE1_Loop
			
			; 21 Command
			lda 	#$21
            sta 	LCD_CMD_CMD
			; 11	 Command
			lda 	#$11
            sta 	LCD_CMD_CMD
			jsr 	WAIT_100ms
			jsr 	WAIT_100ms		
			lda 	#$29
            sta 	LCD_CMD_CMD	
			rts 

; Init Sequence with different command
;LCD_Init_SEQ_CMD		.text $36, $3A, $B2, $B2, $B2, $B2, $B2, $B7, $BB, $C0, $C2, $C3, $C4, $C6, $D0, $D0 
;LCD_Init_SEQ_DAT		.text $00, $05, $0C, $0C, $00, $33, $33, $35, $35, $2C, $01, $13, $20, $0F, $A4, $A1
; Specific Command String of Data for setup $E0, $E1
LCD_Init_CMD_E0_SEQ   	.text $F0, $00, $04, $04, $04, $05, $29, $33, $3E, $38, $12, $12, $28, $30
LCD_Init_CMD_E1_SEQ   	.text $F0, $07, $0A, $0D, $0B, $07, $28, $33, $3E, $36, $14, $14, $29, $32


Splash_LCD_Download:
; The Data on the FLASH for the LCD is made of a BMP File (2 Bytes 565 Encoded) but the file doesn't have a header, so the file needs to be read inverted
            ; Setup the LCD Windows to go Write into - In this case it is the whole Memory (240x320)
            ; Full Screen
            ; FIRST HALF
			; 2A Command ( Window X)
            ; XS = 0
            ; XE = 239
			lda 	#$2A
            sta 	LCD_CMD_CMD
			lda 	#$00	; XStart_High
			sta 	LCD_CMD_DTA
			lda 	#$00	; XStart_Low
			sta 	LCD_CMD_DTA
			lda 	#$00	; XEnd_High
			sta 	LCD_CMD_DTA
			lda 	#$EF	; Xend_Low
			sta 	LCD_CMD_DTA
			; 2B Command (Window Y)
            ; YS = 0
            ; YS = 319
			lda 	#$2B
            sta 	LCD_CMD_CMD
			lda 	#$00	; YStart_High
			sta 	LCD_CMD_DTA
			lda 	#$00	; YStart_Low
			sta 	LCD_CMD_DTA
			lda 	#$01	; YEnd_High	; 280
			sta 	LCD_CMD_DTA
			lda 	#$3F		; Yend_Low
			sta 	LCD_CMD_DTA

			lda 	#$2C        ; Tell the LCD to expect Data
            sta 	LCD_CMD_CMD
; $80/$81 Size
; $82/$83/$84 Address in Flash to get Data
; $86/$87 Destination
; $88/$89 Number of Lines (320)
            ; 240 x 2 (2 bytes per pixel) ($01E0)
            lda 	#$E0
            sta 	$80
            lda 	#$01
            sta 	$81
            ; 0x16000 Starting Address in Flash
            ; We need to go backward
            ; 0x03B620
            lda 	#$20
            sta 	$82
            lda 	#$B6
            sta 	$83
            lda 	#$03
            sta 	$84
            ; Number of Lines (320 Lines total - THe display shows only 280)
            ; However, the Matrix in the Flash is 240x320 ($0140)
            lda 	#$00
            sta 	$88
            sta 	$89

Splash_TRF_Main_Loop

            jsr 	Splash_LCD_Read_A_Line  ;So Let's go fetch the first line

            ;Data has been transfered
            clc 
            lda 	$88
            adc 	#$01
            sta 	$88
            bcc 	Splash_LCD_No_C
            inc 	$89

Splash_LCD_No_C:
            lda 	$88
            cmp 	#$40
            bne 	Splash_TRF_Main_Loop
            lda 	$89
            cmp 	#$01
            bne 	Splash_TRF_Main_Loop
            rts

;; ********************************
;; *********** LCD ****************
;; ********************************
; Start Address is @ $016000 - Ends @ $03B800
;3 B620
Splash_LCD_Read_A_Line:
            ; Setup Pointer for Flash Access
            lda #$03        ; FLash Command $03 READ
            sta SPLASH_FLASH_SPI_CMD
            lda $80
            sta SPLASH_FLASH_SPI_SIZLo
            lda $81
            sta SPLASH_FLASH_SPI_SIZHi
            lda $82    ;
            sta SPLASH_FLASH_SPI_AD_Lo
            lda $83
            sta SPLASH_FLASH_SPI_AD_Mi
            lda $84
            sta SPLASH_FLASH_SPI_AD_Hi
            lda #$01    ; Start Transfer
            sta SPLASH_FLASH_SPI_CTRL

            ; I requested 1024 bytes, the FIFO can contain 2048
Splash_LCD_FIFO_Wait:          
            lda SPLASH_FLASH_SPI_SIZHi      ; Read FIFO Count Hi
            cmp #$01
            bne Splash_LCD_FIFO_Wait        ; Make sure the Count = $1E0 (2x $F0)

; We fetch only 240 Bytes Per Line - So We Fetch 1 Line from the Flash, then Program the LCD, then we do it again 320 times.
; Buffer $0400
            ldx #$00

FIFO_LCD_Read_LUT:          
            lda SPLASH_FIFO_DATA_IN
            sta LCD_PIX_LO
            lda SPLASH_FIFO_DATA_IN
            sta LCD_PIX_HI
            inx 
            cpx #$F0
            bne FIFO_LCD_Read_LUT

            lda #$00
            sta SPLASH_FLASH_SPI_CTRL ;; THis allows the State_machine to go back to IDLE.
            ; Ho Sweet Math Copro - I Love you so much!             
            jsr LCD_FIFO_Addy_Add ; Readjust the pointer for the Flash for next Fetching
            rts

; Let's use the local Math Copro to do the 24Bits For me! I Love Hardware Stuff!
; Addy Pointer = Actual Addy + 480 (2x 240)
LCD_FIFO_Addy_Add:
            lda 	$82
            sta 	$DE08 ; A[0] 
            lda 	$83
            sta 	$DE09 ; A[1]
            lda 	$84
            sta 	$DE0A ; A[2]
            lda 	#$00   
            sta 	$DE0B ; A[3]
            ; We are substracting (-480 $FFFF_FE20)
            lda 	#$20
            sta 	$DE0C ; B[0]
            lda 	#$FE
            sta 	$DE0D ; B[1]
            lda 	#$FF
            sta 	$DE0E ; B[2]
            sta 	$DE0F ; B[3]
            ; Ho Yeah! Instant Results!
            lda 	$DE18 ; Results[0]
            sta 	$82
            lda 	$DE19 ; Results[1]
            sta 	$83
            lda 	$DE1A ; Results[2]
            sta 	$84
            rts

;
; Wait for 100ms
;
; Not Super Sexy but so early in the initialisation of the system that'd prolly the best way to go (to be changed with something more sexy?)
WAIT_100ms: phx
            ldx 	#100
WAIT100L:   jsr 	WAIT_1MS
            dex
            bne 	WAIT100L
            plx
            rts

; Wait for about 1ms
;
WAIT_1MS:   phx
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

            .send
            .endn
            .endn
