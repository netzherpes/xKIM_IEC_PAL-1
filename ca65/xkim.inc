;=====================================================
; This file contains vectors for Corsham Technologies'
; xKIM monitor.  Last update 12/12/2021 for v1.8.
;
; Note that some subroutine names have changed
; slightly to fix duplicate names in the KIM monitor.
;
; See the xKIM User Manual for documentation on the
; data in this file.
;
; www.corshamtech.com
; https://github.com/CorshamTech/xKIM
;
; 01/30/2024 - Eduardo Casino
;		CA65 port

; origBss	equ	*	;SAVE BSS!!!
;		org	xKIM_BASE

                .segment        "xkim_code"
;
; Main functions
;
extKIM:		.res	3	;extended monitor
xkOUTCH:        .res	3	;output A to console
xkGETCH:	.res	3	;get a key and echo
xkGETCHne:	.res	3	;no echo - KIM can't do it
xKIM_res_0:	.res	3	;future - console stat
putsil:		.res	3	;print string after JSR
getHex:		.res	3	;get hex value in A
xkPRTBYT:	.res	3	;print A as hex
getStartAddr:	.res	3
getEndAddr:	.res	3
getAddrRange:	.res	3
;
; future use
;
xkHexDump:	.res	3	;perform a hex dump
xkMemEdit:	.res	3	;edit memory
loadHexConsole:	.res	3	;load hex via console
loadHexFile:	.res	3	;load hex from SD
doDiskDir:	.res	3	;do directory of SD card
calcOffset:	.res	3	;compute branch offset
;
; SD card functions
;
;		org	xKIM_BASE+$0033
xParInit:	.res	3
xParSetWrite:	.res	3
xParSetRead:	.res	3
xParWriteByte:	.res	3
xParReadByte:	.res	3
DiskPing:	.res	3
DiskDir:	.res	3
DiskDirNext:	.res	3
DiskOpenRead:	.res	3
DiskRead:	.res	3
DiskClose:	.res	3
DiskOpenWrite:	.res	3
DiskWrite:	.res	3
;
;                .segment        "public_data"
;
;AutoRun:	.res	2
;ColdFlag:	.res	2
;ExtensionAddr:	.res	2
;HighestAddress:	.res	2
;
; New vectors will go here.
;
;
; Now restore BSS!
;
;		org	origBss

