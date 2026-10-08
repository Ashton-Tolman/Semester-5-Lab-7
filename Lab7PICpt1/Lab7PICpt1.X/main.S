// Ashton Tolman
// RCET3373
// Lab7PICpt1
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
    BSF  0x03, 06   ;
    BSF  0x03, 05   ; Set bank 3 active
    CLRF ANSEL      ; PortA Digital, set specific measured pins later
    CLRF ANSELH     ; PortB Digital
    BSF ANSEL,0     ; AN0 / RA0 = analog input
    
    BSF  0x03, 06   ;
    BCF  0x03, 5    ; Set bank 2 active
    BSF  0x09, 1    ; Turn T1G-not function off
    
    BCF  0x03, 06   ;
    BSF  0x03, 05   ; Set bank 1 active 
    MOVLW 0x01	    ;
    MOVWF 0x85      ; TRISA: RA0 input, other PORTA pins outputs
    CLRF 0x86       ; TRISB: PORTB outputs
    CLRF 0x87       ; TRISC: PORTC outputs
    CLRF ADCON1     ; Clear ADCON1
    BSF ADCON1,7    ; ADFM = 1, right justify result
    BCF ADCON1,5    ; VREF- = VSS
    BCF ADCON1,4    ; VREF+ = VDD
		    
    BCF  0x03, 06   ;
    BCF  0x03, 05   ; Set bank 0 active
    CLRF 0x06	    ; clear port B
    CLRF 0x05	    ; clear port A
    CLRF 0x07	    ; Clear portC	 
		    
    CLRF ADCON0
    BCF ADCON0,7
    BSF ADCON0,6	    
    BSF ADCON0,0
    goto Main
    

Main:
    ; Acquisition Delay that allows sample/hold capacitor to charge
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    
    ; Start ADC Conversion
    BANKSEL PORTA
    BSF PORTA,1     ; Diagnostic HIGH
    BANKSEL ADCON0
    BSF ADCON0,1    ; GO/DONE = 1, start conversion
    
WaitADC:
    BTFSC ADCON0,1  ; Is GO/DONE still 1?
    goto WaitADC    ; Yes -> conversion still running

    ; Conversion Complete
    BANKSEL PORTA
    BCF PORTA,1     ; Diagnostic LOW

    ; Display ADRESH on PORTC
    BANKSEL ADRESH
    MOVF ADRESH,W
    BANKSEL PORTC
    MOVWF PORTC

    ; Display ADRESL on PORTB
    BANKSEL ADRESL
    MOVF ADRESL,W
    BANKSEL PORTB
    MOVWF PORTB
    goto Main
End