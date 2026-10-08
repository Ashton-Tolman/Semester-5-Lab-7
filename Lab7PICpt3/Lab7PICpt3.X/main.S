// Ashton Tolman
// RCET3373
// Lab7PICpt2
// https://github.com/Ashton-Tolman/Semester-5-Lab-7.git
// linker code:-Wl,-presetVect=0000h,-pisrVect=0004h,-pcode=0008h

; PIC16F883 Configuration Bit Settings

; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

// config statements should precede project file includes.
#include <xc.inc>
  
Index EQU 0x70	    ; Temporary register for the 21 positions
DelayCount EQU 0x71 ; Count for delay loop

W_TEMP EQU 0x70		; Temporary W register in global GR
STATUS_TEMP EQU 0x71	; Temporary Status register in global GR
 
; Reset Vector at 000h. Execution starts here after reset 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
    
    
; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    goto Main
    
; Main code section starts at 0008h. User code goes here
PSECT code,class=CODE,delta=2

Setup:
    ; add device setup here
    BSF 0x03, 06    ;
    BSF 0x03, 05    ; Set bank 3 active
    CLRF ANSEL      ; PortA Digital, set specific measured pins later
    CLRF ANSELH     ; PortB Digital
    BSF ANSEL,0     ; AN0 / RA0 = analog input
    
    BSF 0x03, 06    ;
    BCF 0x03, 5	    ; Set bank 2 active
    BSF 0x09, 1	    ; Turn T1G-not function off
    
    BCF 0x03, 06    ;
    BSF 0x03, 05    ; Set bank 1 active 
    BSF TRISA,0     ;RA0 is an input - this is where the pot wiper connects
    BCF TRISA,1     ;RA1 is an output - this is the wire that goes to the servo
    BCF ADCON1,7    ;left justified results this time
    BCF ADCON1,4    ;top of the ADC's measuring range = VDD
    BCF ADCON1,5    ;bottom of the ADC's measuring range = VSS (ground)
		    
    BCF 0x03, 06    ;
    BCF 0x03, 05    ; Set bank 0 active
    BCF ADCON0,7    ;pick the ADCs internal speed
    BSF ADCON0,6    ;Fosc/8
    CLRF ADRESH
    CLRF ADRESL
    CLRF PORTA      ;make sure nothing is on port a
    BSF ADCON0,0    ;turn the ADC module on
    MOVLW 0xF6
    MOVWF TMR1H     ;load the timer's starting count, high byte
    MOVLW 0x3C
    MOVWF TMR1L     ;low byte, so it takes exactly 20ms to roll over
    BCF PIR1,0      ;make sure the timer's flag starts out clean
    BANKSEL PIE1
    BCF PIE1,0      ;let Timer1 actually trigger an interrupt when it rolls over
    BANKSEL T1CON
    MOVLW 0b00110001;prescale 1:8, use the chip's own clock, and start the timer
    MOVWF T1CON
    BCF PIR1,0      ;clear Timer1 overflow interrupt flag bit

    goto Main
    

Main:
    BANKSEL PIR1
    BTFSS   PIR1,0	    ; Has Timer1 overflow happened (No interrupt)
    goto    Main	    ; No, check again
    BCF     PIR1,0	    ; Yes, clear flag and continue code function
    BANKSEL TMR1H	    ; Reload Timer1 for the next 20ms delay set
    MOVLW   0xF6	    
    MOVWF   TMR1H
    MOVLW   0x3C
    MOVWF   TMR1L
    NOP			    ; Wait time so ADC can charge measuring cap
    NOP                   
    NOP
    NOP
    NOP
    BSF     ADCON0,1	    ; Start conversion
Conversion:
    BTFSC   ADCON0,1	    ; Is conversion complete
    goto    Conversion	    ; No, check again
    CLRF    Index	    ; Yes, clear index and continue code
IndexLoop:
    MOVLW   12		    ; Move 12 to be subtracted from 255
    SUBWF   ADRESH,F	    ; Subtracte 12 from ADRESH 
    BTFSS   STATUS,0	    ; Did ADRESH go negitive? yes then GOTO IndexDone
    goto    IndexDone	    ; Indexdone checks to see if the index was 20 or 21
    INCF    Index,F	    ; If still a positive count then increment index until 0
    goto    IndexLoop	    ; Stay in the loop until the count is zero or negitve 
IndexDone:
    MOVLW   20		    ; Checks to make sure in desired range
    SUBWF   Index,W	    ; W = Index - 20
    BTFSS   STATUS,0	    ; Carry = 0 if Index is less than 20
    goto    MakePulse	    ; Index is 0-19, so keep it
    MOVLW   20		    ; 20 is the max limit of index count
    MOVWF   Index	    ; Index was 20 or 21, so limit it to 20
;         turn the position number into an actual pulse
MakePulse:
    MOVLW   5		    ; 5 will be added to index
    ADDWF   Index,F	    ; Index is how many 100us for PWM
    BSF     PORTA,1	    ; Start the pulse RA1 goes HIGH here
PulseLoop:
    CALL    Delay	    ; Call the delay section for a 100us delay
    DECFSZ  Index,F	    ; Do the delay the Index amount of times
    goto    PulseLoop	    ; Keeps going until index is zero
    BCF     PORTA,1	    ; Once zero set RA1 low 
    goto    Main	    ; Return
; Delay is producing a 100us
Delay:
    MOVLW   30            ;run the DelayCount 30 times
    MOVWF   DelayCount    ;move 30 into DelayCount
    NOP                   ;1 Tcy
    NOP                   ;1 Tcy
DelayLoop:
    DECFSZ  DelayCount,F  ;Decrement from 30 until zero for the delay
    goto    DelayLoop     ;keeps looping until DelayCount is zero
    RETURN                ;Return to PulseLoop 
End