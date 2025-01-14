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
LCD_CMD_CMD             = $dd40    ;Write Command Here
LCD_RST                 = $10      ; 0 to Reset (RSTn)
LCD_BL                  = $20      ; 1 = ON, 0 = OFF 
; Read Only
LCD_TE                  = $40      ; Tear Enable 
LCD_CMD_DTA             = $dd41    ;Write Data (For Command) Here
; Always Write in Pairs, otherwise the State Machine will Lock
LCD_PIX_LO              = $dd42    ; {G[2:0], B[4:0]}
LCD_PIX_HI              = $dd43    ; {R[4:0], G[5:3]}

LCD_CTRL_REG            = $dd44 

init
			lda     #LCD_RST | LCD_BL
			sta     LCD_CTRL_REG

			lda     #$11
            sta     LCD_CMD_CMD
			jsr     WAIT_100ms
			jsr     WAIT_100ms	
			; 36     Command
			lda     #$36	; Viewing Side
            sta     LCD_CMD_CMD
			lda     #$00	; Vertical - 70 8 = Invert Color
			sta     LCD_CMD_DTA
			; 3A     Command
			lda     #$3A
            sta     LCD_CMD_CMD
			lda     #$05
			sta     LCD_CMD_DTA
			; B2     Command
			lda     #$B2
            sta     LCD_CMD_CMD
			lda     #$0C
			sta     LCD_CMD_DTA
			sta     LCD_CMD_DTA
			lda     #$00
			sta     LCD_CMD_DTA
			lda     #$33
			sta     LCD_CMD_DTA
			sta     LCD_CMD_DTA
			; B7     Command
			lda     #$B7
            sta     LCD_CMD_CMD
			lda     #$35
			sta     LCD_CMD_DTA
			; BB     Command
			lda     #$BB
            sta     LCD_CMD_CMD
			lda     #$35
			sta     LCD_CMD_DTA
			; C0     Command
			lda     #$C0
            sta     LCD_CMD_CMD
			lda     #$2C
			sta     LCD_CMD_DTA
			; C2     Command
			lda     #$C2
            sta     LCD_CMD_CMD
			lda     #$01
			sta     LCD_CMD_DTA
			; C3     Command
			lda     #$C3
            sta     LCD_CMD_CMD
			lda     #$13
			sta     LCD_CMD_DTA
			; C4     Command
			lda     #$C4
            sta     LCD_CMD_CMD
			lda     #$20
			sta     LCD_CMD_DTA
			; C6     Command
			lda     #$C6
            sta     LCD_CMD_CMD
			lda     #$0F
			sta     LCD_CMD_DTA
			; D0     Command
			lda     #$D0
            sta     LCD_CMD_CMD
			lda     #$A4
			sta     LCD_CMD_DTA
			lda     #$A1
			sta     LCD_CMD_DTA
			; D6     Command
			lda     #$D0
            sta     LCD_CMD_CMD
			lda     #$A4
			sta     LCD_CMD_DTA
			; E0     Command
			ldx     #$00
			lda     #$E0
            sta     LCD_CMD_CMD

_Init_CMDE0_Loop:    			
			lda     LCD_Init_CMD_E0_SEQ, x
			sta     LCD_CMD_DTA
		    inx     
			cpx     #size(LCD_Init_CMD_E0_SEQ)
			bne     _Init_CMDE0_Loop
    
			; E1     Command
			ldx     #$00
			lda     #$E1
            sta     LCD_CMD_CMD

_Init_CMDE1_Loop:    			
			lda     LCD_Init_CMD_E1_SEQ, x
			sta     LCD_CMD_DTA
		    inx     
			cpx     #size(LCD_Init_CMD_E1_SEQ)
			bne     _Init_CMDE1_Loop
    
			; 21     Command
			lda     #$21
            sta     LCD_CMD_CMD
			; 11     Command
			lda     #$11
            sta     LCD_CMD_CMD
			jsr     WAIT_100ms
			jsr     WAIT_100ms		
			lda     #$29
            sta     LCD_CMD_CMD		
			rts

LCD_Init_CMD_E0_SEQ   .text $F0, $00, $04, $04, $04, $05, $29, $33, $3E, $38, $12, $12, $28, $30
LCD_Init_CMD_E1_SEQ   .text $F0, $07, $0A, $0D, $0B, $07, $28, $33, $3E, $36, $14, $14, $29, $32


SetWindows
            ; FIRST HALF
			; 2A Command ( Window X)
            ; XS = 0
            ; XE = 239
			lda #$2A
            sta LCD_CMD_CMD
			lda #$00	; XStart_High
			sta LCD_CMD_DTA
			lda #$00	; XStart_Low
			sta LCD_CMD_DTA
			lda #$00	; XEnd_High
			sta LCD_CMD_DTA
			lda #239	; Xend_Low
			sta LCD_CMD_DTA
			; 2B Command (Window Y)
            ; YS = 0
            ; YS = 139
			lda #$2B
            sta LCD_CMD_CMD
			lda #$00	; YStart_High
			sta LCD_CMD_DTA
			lda #20	; YStart_Low
			sta LCD_CMD_DTA
			lda #$00	; YEnd_High	; 280
			sta LCD_CMD_DTA
			lda #159		; Yend_Low
			sta LCD_CMD_DTA
			
			lda #$2C
            sta LCD_CMD_CMD

            jsr Clear_Block240x140
           
            ; SECOND HALF
			; 2A Command ( Window X)
            ; XS = 0
            ; XE = 239            
			lda #$2A
            sta LCD_CMD_CMD
			lda #$00	; XStart_High
			sta LCD_CMD_DTA
			lda #$00	; XStart_Low
			sta LCD_CMD_DTA
			lda #$00	; XEnd_High
			sta LCD_CMD_DTA
			lda #239	; Xend_Low
			sta LCD_CMD_DTA
			; 2B Command (Window Y)
            ; YS = 140
            ; YS = 139            
			lda #$2B
            sta LCD_CMD_CMD
			lda #$00	; YStart_High
			sta LCD_CMD_DTA
			lda #160	; YStart_Low
			sta LCD_CMD_DTA
			lda #$01	; YEnd_High	; 280
			sta LCD_CMD_DTA
			lda #$2C		; Yend_Low
			sta LCD_CMD_DTA
			
			lda #$2C
            sta LCD_CMD_CMD
            jsr Clear_Block240x140
			rts

Clear_Block240x140
            ldy #$00 

_Fill_Branch_X_Clear0:
            ldx #$00

_Fill_Branch0
    		lda #$00
			sta LCD_PIX_LO
			lda #$00
			sta LCD_PIX_HI
            inx 
            cpx #240        ; 240 Pixel Wide
            bne _Fill_Branch0
            iny 
            cpy #140
            bne _Fill_Branch_X_Clear0
			rts



            .send
            .endn
            .endn
