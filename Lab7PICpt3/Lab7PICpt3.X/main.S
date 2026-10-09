// Ashton Tolman
// RCET3373
// Lab7PICpt3
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
ccp_next_l EQU 0x23
ccp_next_h EQU 0x24
 
GLOBAL  ccp_next_l, ccp_next_h
EXTRN   LookupAdc6ToCcp
      
W_TEMP EQU 0x70		; Temporary W register in global GR
STATUS_TEMP EQU 0x71	; Temporary Status register in global GR
ADCIndex EQU 0x72	;the ADC reading, squeezed down to 0-63
CustomStatus EQU 0x73   ;bit0: 1 while the servo pulse is actively HIGH
			;bit1: 1 once this frame's NEXT value is ready

 
; Reset Vector at 000h. Execution starts here after reset 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
    
    
; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    goto ISRHandler
    
; Main code section starts at 0008h. User code goes here
PSECT code,class=CODE,delta=2

Setup:
    ; main device setup here
    BSF 0x03, 06	    ;
    BSF 0x03, 05	    ; Set bank 3 active
    BSF ANSEL,0		    ; set RA0 is a analog input pin
    CLRF ANSELH
    
    BSF 0x03, 06	    ;
    BCF 0x03, 5		    ; Set bank 2 active
    BSF 0x09, 1		    ; Turn T1G-not function off
    
    BCF 0x03, 06	    ;
    BSF 0x03, 05	    ; Set bank 1 active 
    BSF TRISA,0		    ; RA0 is an input - this is where the pot wiper connects
    BCF TRISC,2		    ; RC2 is an output to the servo for control
    BCF ADCON1,7	    ; Left justified
    BCF ADCON1,4	    ; Top of the ADC's measuring range VDD
    BCF ADCON1,5	    ; Bottom of the ADC's measuring range VSS (ground)
		    
    BCF 0x03, 06	    ;
    BCF 0x03, 05	    ; Set bank 0 active
    BCF ADCON0,7	    ; Pick the ADCs internal speed
    BSF ADCON0,6	    ; Fosc/8
    CLRF ADRESH
    CLRF ADRESL
    BSF ADCON0,0	    ; Turn the ADC module on
    MOVLW 0b00001010	    ; CCP1 in Compare mode: just flag an interrupt on
    MOVWF CCP1CON	    ; Match, don't touch the pin directly ourselves
    MOVLW 0xB1
    MOVWF TMR1H		    ; Load the timer's starting count, high byte
    MOVLW 0xE0
    MOVWF TMR1L		    ; Low byte, so it takes exactly 20ms to roll over
    BCF PORTC,2		    ; Set the servo low so no weird glitch
    BCF PIR1,0		    ; Clear the timer1 interrupt flag
    BCF PIR1,2		    ; Clear the CCP1 interrupt flag 
    BANKSEL PIE1
    BSF PIE1,0		    ; Timer1 CAN now trigger an interrupt when it rolls over
    BSF PIE1,2		    ; CCP1 can now trigger an interrupt on a compare match
    BANKSEL ADCON0	    ; Back to Bank 0
    CLRF CustomStatus	    ; Clear all status so nothing happens on start 
    
    ; Load base info into CCP for first loop 
    ;(likely unneccessary past startup smoothness)
    
    BSF ADCON0,1	    ; Start ADC conversion
    BTFSC ADCON0,1	    ; Test if conversion is done
    goto $-1		    ; If it isnt retry
    MOVF ADRESH,W	    ; Put Analog info in high byte into Index
    MOVWF ADCIndex	    
    BCF STATUS,0	    ; Clear the Carry bit so no Bad data gets shifted in
    RRF ADCIndex,F	    ; Shift right once, RRF moves register right 
    BCF STATUS,0	    ; Clear carry bit during shift so its data doesnt go in
    RRF ADCIndex,F	    ; Again so ADCIndex is now a clean 0-63 number
    MOVF ADCIndex,W
    PAGESEL LookupAdc6ToCcp ; The lookup table is on a different page so call it
    CALL LookupAdc6ToCcp    ; The table will load the right info onto the ccp
    PAGESEL $		    ; general registers so they contain data here
    MOVF ccp_next_h,W
    MOVWF CCPR1H	    ; Manually load the very first pulse's end-time,
    MOVF ccp_next_l,W	    ; Since Timer1's ISR (which normally does this)
    MOVWF CCPR1L	    ; Hasn't run yet
    BSF CustomStatus,1	    ; This value is ready and waiting
    
    MOVLW 0b00000001	    ; Prescale 1:1, internal clock, and start Timer1
    MOVWF T1CON		    ; Counting right now, from 0xB1E0
    BSF INTCON,6	    ; Allow peripherals to interrupt at all
    BSF INTCON,7	    ; Enable global interrupts
    

Main:
    BTFSC CustomStatus,0    ; Is the servo pulse still high? 
    goto Main		    ; CCP didnt drop the pulse so poll again
    BTFSC CustomStatus,1    ; Have we already ADC converted this frame?
    goto Main		    ; If we have dont let the rest of main run
    
Conversion:
    BSF ADCON0,1	    ; Start conversion
    BTFSC ADCON0,1	    ; Is conversion complete
    goto $-1		    ; No, check again
    MOVF ADRESH,W	    ; Put Analog info in high byte into Index
    MOVWF ADCIndex	    
    BCF STATUS,0	    ; Clear the Carry bit so no Bad data gets shifted in
    RRF ADCIndex,F	    ; Shift right once, RRF moves register right 
    BCF STATUS,0	    ; Clear carry bit during shift so its data doesnt go in
    RRF ADCIndex,F	    ; Again so ADCIndex is now a clean 0-63 number
    MOVF ADCIndex,W
    PAGESEL LookupAdc6ToCcp ; The lookup table is on a different page so call it
    CALL LookupAdc6ToCcp    ; The table will load the right info onto the ccp
    PAGESEL $		    ; general registers so they contain data here
    BSF CustomStatus,1	    ; This completes the ADC data gather, so set bit high
    goto Main
    
    ;The ISRs of this code handle both setting and clearing the servos pulse
    ;The timer1 sets the pulse and reloads itself, the CCP clears the servo pulse
ISRHandler:
    MOVWF W_TEMP	    ;Copy W to TEMP register
    SWAPF STATUS,0	    ;Swap status to be saved into W
			    ;Swaps are used because they dont change the status bits
    MOVWF STATUS_TEMP	    ;Save status to bank zero STATUS_TEMP register
    
    BTFSC PIR1,0	    ; TMR1 rollover flag
    CALL ServiceTimer1
    BTFSC PIR1,2	    ; CCP1 match flag
    CALL ServiceCCP1
    
    SWAPF STATUS_TEMP,0	    ;Swap STATUS_TEMP register into W
			    ;(sets bank to original state)
    MOVWF STATUS	    ;Move W into STATUS register
    SWAPF W_TEMP,1	    ;Swap W_TEMP
    SWAPF W_TEMP,0	    ;Swap W_TEMP into W
    RETFIE
    
ServiceTimer1:
    BCF     PIR1,0	    ; Clear the flag
    
    MOVLW   0xB1	    ; Reload count for 2oms
    MOVWF   TMR1H	    ;
    MOVLW   0xE0	    ;
    MOVWF   TMR1L	    ;

    BSF     PORTC,2	    ; Pulse starts now - servo pin goes HIGH

    MOVF    ccp_next_h,W    ; Load Lookup table data into CCP
    MOVWF   CCPR1H	    ;
    MOVF    ccp_next_l,W    ;
    MOVWF   CCPR1L

    BCF     CustomStatus,1  ; Main can now run all code for ADC conversion
    BSF     CustomStatus,0  ; Pulse is now high so set CustomStatus bit
    RETURN
    
ServiceCCP1:
    BCF     PIR1,2	    ; Clear the flag
    BCF     PORTC,2	    ; Pulse ends now - servo pin goes LOW
    BCF     CustomStatus,0  ; Main now can take ADC data one time
    RETURN
    End