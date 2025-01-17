;*****************************************************
; Extended KIM monitor, written 2015 by Bob Applegate
; K2UT - bob@corshamtech.com
; Ported to ca65 by Eduardo Casino
; mail@eduardocasino.es
;
; This code was written as part of the Corsham Tech
; 60K RAM/EPROM board.  It provides a working area for
; an extended version of the KIM-1 monitor capabilities,
; mostly based on a TTY interface, not the keypad and
; hex display.
;
; This extensions contains an assortment of basic
; tools that are missing from the KIM-1's built in
; console monitor.  It has commands for loading hex
; files (as opposed to KIM format), accessing an SD
; card system, memory edit, hex dump, etc.  It also
; has the ability for user-defined extensions to be
; added.  And a number of common entry points have
; vectors so the monitor can be modified without
; breaking programs that use it.
;
; I'm not claiming copyright; I wrote most of this,
; but also borrowed from others (credit is given in
; those sections of code).  All of the portions I've
; written are free to use, but please keep my name
; in the comments somewhere.  Even better, consider
; buying a board from us: www.corshamtech.com
;
; 12/01/2015	Bob Applegate
;		Initial development - V0.X
; 03/15/2016	Bob Applegate
;		v1.0 - First official release
; 01/03/2017	Bob Applegate
;		v1.1 - Added S command
; 09/20/2018	Bob Applegate
;		v1.2 - Added auto-run vector
; 01/25/2019	Bob Applegate
;		v1.3 - Added 'X' command.
;		Added the 'C' command to get time.
; 03/09/2019	Bob Applegate
;		v1.4 - Added 'O' command.
; 07/26/2020	Bob Applegate
;		v1.5 - Fixed bug that caused the S
;		command to create empty file with no
;		contents.
;		Minor typo fixes.
;		Added CLD instructions.
; 11/14/2020	Bob Applegate
;		v1.6 - On SD error, display reason code.
; 09/15/2021	Bob Applegate
;		v1.7
;		Added offset calculator command O.
;		Added R command in Edit mode.
;		Removed '.' when loading from console.
; 09/20/2021	Bob Applegate
;		v1.8
;		Made a lot of the command handlers
;		into subroutines and added vectors so
;		external programs can call them.
;		Fixed bugs in Edit mode.
; 01/30/2024    Eduardo Casino
;               CA65 port
;
;*****************************************************
;
; Useful constants
;
false		=	0
true		=	~false
;
; Version number
;
VERSION		=	1
REVISION	=	8
BETA_VER	=	0
;
; Options.  .if RAM_BASED is set then the code is put
; into RAM, else it's in ROM.  Very handy for testing
; new code; load the new code with the EPROM version
; and then test away.
;
.ifndef RAM_BASED
RAM_BASED	=	false
.endif
RAM_DATA_BASE	=	$af80
RAM_CODE_BASE	=	$b000
;
; Set the EPROM base addresses
;
ROM_START	=	$e000
RAM_START	=	$df80
;
; This is something that needs more investigation.
; .if the SD system isn't reset enough then bad stuff
; happens after the RS button is pressed.  Set this to
; true to only reset the SD system on cold starts.
;
SD_ONLY_COLD	=	false
;
; Set this to true to include Bob's Tiny BASIC.  It's
; a minimal (ie, tiny) BASIC interpreter good for
; playing around.
;
TINY_BASIC	=	false
;
; Set this to true to include a command to get/display
; the current time from Corsham Tech SD card.
;
SHOW_RTC	=	true
;
; Non-printable ASCII constants
;
NUL		=	$00
BS		=	$08
LF		=	$0a
CR		=	$0d
ESC		=	$1b
SPC		=	$20
;
; Intel HEX record types
;
DATA_RECORD	=	$00
EOF_RECORD	=	$01
;
; These are various buffer sizes
;
FILENAME_SIZE	=	12
BUFFER_SIZE	=	64
;
; Max number of bytes per line for hex dump
;
BYTESLINE	=	16
;
; Flag values used to detect a cold start vs warm
;
COLD_FLAG_1	=	$19
COLD_FLAG_2	=	$62
;
;=====================================================
; This macro is used to verify that the current address
; meets a required value.  Used mostly to guarantee
; changes don't cause entry points to move.
;
        .macro	VERIFY expected
                exp = expected          ; Force eval of constant expression
                .assert * = exp, error, .concat("Not at requested address (", .string(exp), ")")
        .endmacro
;
;=====================================================
; KIM memory locations
;
        .segment        "kim_zp" : zeropage

PCL:		.res	1
PCH:		.res	1
PREG:		.res	1
SPUSER:		.res	1
ACC:		.res	1
YREG:		.res	1
XREG:		.res	1
CHKHI:		.res	1
CHKSUM:		.res	1
INL:	    	.res	1
INH:		.res	1
POINTL:		.res	1
POINTH:		.res	1
TEMP:		.res	1
TMPX:		.res	1
CHAR:		.res	1
MODE:		.res	1
;
        .segment        "kim_ram"
CHKL:		.res	1
CHKH:		.res	1
SAVX:		.res	3
VEB:	    	.res	6
CNTL30:		.res	1
CNTH30:		.res	1
TIMH:		.res	1
SAL:		.res	1
SAH:	    	.res	1
EAL:		.res	1
EAH:	    	.res	1
ID:  		.res	1
;
;=====================================================
; KIM I/O locations
;
SAD		=	$1740
PADD		=	$1741
;
;=====================================================
; KIM subroutines located in the ROMs
;
NMIT		=	$1c1c	;NMI handler
IRQT		=	$1c1f	;IRQ handler
RST	    	=	$1c22	;RESET handler
TTYKB		=	$1c77	;do keyboard monitor
CRLF		=	$1e2f	;print CR/LF
PRTPNT		=	$1e1e	;print POINT
PRTBYT		=	$1e3b	;print A as two hex digits
GETCH		=	$1e5a	;get a key from tty into A
OUTSP		=	$1e9e	;print a space
OUTCH		=	$1ea0	;print A to TTY
SHOW		=	$1dac
SHOW1		=	$1daf
INCPT		=	$1f63	;inc POINTL/POINTH
;
;=====================================================
; I assume the RAM goes from 2000 to DFFF, so carve out
; a bit for use by the monitor.
;
                                ;uninitialized data area

                .segment        "bss"

LowestAddress	=	*
;
; Storage for registers for some monitor calls.
;
saveA:		.res	1
saveX:		.res	1
saveY:		.res	1
;
; Pointer to the subroutine that gets the next input
; character.  Used for doing disk/console input.
;
inputVector:	.res	2
;
; Same thing for output.
;
outputVector:	.res	2
;
filename:	.res	FILENAME_SIZE+1
buffer:		.res	BUFFER_SIZE
diskBufOffset:	.res	1
diskBufLength:	.res	1
;
Temp16L:	.res	1
Temp16H:	.res	1
byteCount	=	saveX
;
; The clock functions need some storage, but just
; overlay the names onto the buffer.
;
month		=	buffer
day		=	month+1
year_high	=	day+1
year_low	=	year_high+1
hour		=	year_low+1
minute		=	hour+1
second		=	minute+1
day_of_week	=	second+1
clock_end	=	day_of_week+1
;
; The next group of memory are public and can be
; used by user programs, so don't modify where any
; of these are.  .if you want to add new public data,
; put them here, always before existing items.  Be
; sure to adjust the ORG.
;
                .segment	"public_data"

;
; Before loading a hex file, the MSB of this vector
; is set to FF.  After loading the file, .if the MSB
; is no longer FF then the address in this vector is
; jumped to.  Ie, it can auto-run a file.
;
AutoRun:	.res	2
;
; ColdFlag is used to determine .if the extended
; monitoring is doing a warm or cold start.
;
ColdFlag:	.res	2
;
; Address of a command table for user-created
; extensions to the monitor.
;
ExtensionAddr:	.res	2
;
; This is the higest location in RAM usable by user
; programs.  Nobody should go past this address.  If
; you are writing extentions to the monitor, it's
; okay to load before the address and then adjust
; this down to keep others from stomping on your
; extention.
;
; .if your program modifies this value, it needs to
; set it back before terminating.
;
HighestAddress:	.res	2

;=====================================================
; Code starts at E000 and goes until FFFF, except for
; the 6502 vectors at the end of memory.
;
                .segment	"code"
;
; Vector table of useful and fun stuff!  These must
; not change or else existing code won't be calling
; the right functions.
;
BASE		=	*
reentry:	jmp	extKim          ;extended monitor
                jmp	OUTCH           ;output A to console
                jmp	GETCH	        ;get a key and echo
                jmp	GETCH	        ;no echo - KIM can't do it
                jmp	dummyRet	;future - console stat
                jmp	putsil	        ;print string after JSR
                jmp	getHex	        ;get hex value in A
                jmp	PRTBYT	        ;print A as hex
                jmp	getStartAddr
                jmp	getEndAddr
                jmp	getAddrRange
                jmp	doHexDump	;perform a hex dump
                jmp	doEdit		;edit memory
                jmp	loadHexConsole	;load hex file via console
                jmp	loadHexFile	;load hex file from SD
                jmp	doSDDiskDir	;do a disk directory
                jmp	ComputeOffset	;compute relative offset
;
; SD card functions
;
                VERIFY	BASE+$0033
                jmp	xParInit	;initialization
                jmp	xParSetWrite
                jmp	xParSetRead
                jmp	xParWriteByte
                jmp	xParReadByte
                jmp	DiskPing
                jmp	DiskDir
                jmp	DiskDirNext
                jmp	DiskOpenRead
                jmp	DiskRead
                jmp	DiskClose
                jmp	DiskOpenWrite
                jmp	DiskWrite
;
; Even more vectors as I ran out of the reserve area!
;

;
;=====================================================
;=====================================================
; Anything past this point can be moved in future
; releases so none of these functions nor data should
; be directly accessed by user programs!!!
;=====================================================
;=====================================================
; This is a dummy function for unimplemented functions
; that basically just clears carry and returns.
;
dummyRet:	clc
                rts
;
defaultExt:	.byte	0

;=====================================================
; This is the start of the extended KIM monitor.
;
notty:		jmp	TTYKB
extKim:		ldx	#$ff
                txs
                lda	#$01	;see .if in tty mode
                bit	SAD
                bne	notty	;branch .if in keyboard mode

        .if	~SD_ONLY_COLD
                jsr	xParInit
        .endif
;
; Determine .if this is a cold or warm start
;
                lda	ColdFlag
                cmp	#COLD_FLAG_1
                bne	coldStart
                lda	ColdFlag+1
                cmp	#COLD_FLAG_2
                bne	coldStart
                jmp	extKimLoop	;it's a warm start
;
; Cold start
;
coldStart:	lda	#COLD_FLAG_1	;indicate we've done cold
                sta	ColdFlag
                lda	#COLD_FLAG_2
                sta	ColdFlag+1
;
; Point to an empty extension set by default.
;
                lda	#<defaultExt	;set extension pointers
                sta	ExtensionAddr
                lda	#>defaultExt
                sta	ExtensionAddr+1
;
; Set HighestAddress to just before our RAM area.
;
                lda	#<(LowestAddress-1)
                sta	HighestAddress
                lda	#>(LowestAddress-1)
                sta	HighestAddress+1
        .if	SD_ONLY_COLD
;
; Initialize the interface to the SD card.  There seems to
; be a problem .if this is done too often, so do it just once
; and be done.
;
                jsr	xParInit
        .endif
;
; Display our welcome text
;
                jsr	putsil
                .byte	CR,LF,CR,LF
                .byte	"Extended KIM Monitor v"
                .byte	VERSION+'0','.',REVISION+'0',' '
        .if	BETA_VER
                .byte	"BETA "
                .byte	BETA_VER+'0'
                .byte	' '
        .endif
                .byte	"by Corsham Technologies, LLC"
                .byte	CR,LF
                .byte	"www.corshamtech.com"
                .byte	CR,LF
        .if	RAM_BASED
                .byte	CR,LF
                .byte	"*** RAM BASED VERSION ***"
                .byte	CR,LF
        .endif
                .byte	0
;
; Main command loop.  Put out prompt, get command, etc.
; Prints a slightly different prompt for the RAM version.
;
extKimLoop:	cld
                jsr	setInputConsole
                jsr	putsil	;output prompt
                .byte	CR,LF	;feel free to change it
        .if	RAM_BASED
                .byte	"RAM"
        .endif
                .byte	">",0
                jsr	GETCH
                cmp	#CR
                beq	extKimLoop
                cmp	#LF
                beq	extKimLoop
                sta	ACC	;save key
;
; Now cycle through the list of commands looking for
; what the user just pressed.
;
                lda	#<commandTable
                sta	POINTL
                lda	#>commandTable
                sta	POINTH
                jsr	searchCmd	;try to find it
;
; Hmmm... wasn't one of the built in commands, so
; see .if it's an extended command.
;
                lda	ExtensionAddr
                sta	POINTL
                lda	ExtensionAddr+1
                sta	POINTH
                jsr	searchCmd
;
; .if that returns, then the command was not found.
; Print that it's unknown.
;
                jsr	putsil
                .byte	" - Huh?",0
cmdFound:	jmp	extKimLoop
;
;=====================================================
; Vector table of commands.  Each entry consists of a
; single ASCII character (the command), a pointer to
; the function which handles the command, and a pointer
; to a string that describes the command.
;
commandTable:	.byte	'?'
                .word	showHelp
                .word	quesDesc
;
        .if	TINY_BASIC
                .byte	'B'
                .word	TBasicCold
                .word	bDesc
        .endif
;
        .if	SHOW_RTC
                .byte	'C'
                .word	doShowClock
                .word	cDesc
        .endif
                .byte	'D'
                .word	doDiskDir
                .word	dDesc
;
                .byte	'E'	;edit memory
                .word	editMemory
                .word	eDesc
;
                .byte	'H'	;hex dump
                .word	hexDump
                .word	hDesc
;
                .byte	'J'	;jump to address
                .word	jumpAddress
                .word	jDesc
;
                .byte	'K'	;return to KIM monitor
                .word	returnKim
                .word	kDesc
;
                .byte	'L'	;load Intel HEX file
                .word	loadHex
                .word	lDesc
;
                .byte	'M'	;perform memory test
                .word	memTest
                .word	mDesc
;
                .byte	'O'	;branch offset calculator
                .word	offCalc
                .word	oDesc
;
                .byte	'P'	;ping remote disk
                .word	pingDisk
                .word	pDesc
;
                .byte	'S'	;save memory as hex file
                .word	saveHex
                .word	sDesc
;
                .byte	'T'	;type a file on SD
                .word	typeFile
                .word	tDesc
;
                .byte	'X'	;return to KIM monitor
                .word	returnKim
                .word	kDesc
;
                .byte	'!'	;do cold restart
                .word	doCold
                .word	bangDesc
;
                .byte	0	;marks end of table
;
;=====================================================
; Descriptions for each command in the command table.
; This wastes a lot of space... I'm open for any
; suggestions to keep the commands clear but reducing
; the amount of space this table consumes.
;
quesDesc:	.byte	"? ........... Show this help",0
        .if	TINY_BASIC
bDesc:		.byte	"B ........... Bob's Tiny BASIC",0
        .endif
        .if	SHOW_RTC
cDesc:		.byte	"C ........... Show clock",0
        .endif
dDesc:		.byte	"D ........... Disk directory",0
eDesc:		.byte	"E xxxx ...... Edit memory",0
hDesc:		.byte	"H xxxx xxxx . Hex dump memory",0
jDesc:		.byte	"J xxxx ...... Jump to address",0
kDesc:		.byte	"K ........... Go to KIM monitor",0
lDesc:		.byte	"L ........... Load HEX file",0
mDesc:		.byte	"M xxxx xxxx . Memory test",0
oDesc:		.byte	"O xxxx xxxx . Calculate branch offset",0
pDesc:		.byte	"P ........... Ping disk controller",0
sDesc:		.byte	"S xxxx xxxx . Save memory to file",0
tDesc:		.byte	"T ........... Type disk file",0
bangDesc:	.byte	"! ........... Do a cold start",0
;
;=====================================================
; Return to KIM monitor.  Before returning, set the
; "open address" to the start of the extended monitor
; so the KIM monitor is pointing to it by default.
;
returnKim:	jsr	putsil
                .byte	CR,LF
                .byte	"Returning to KIM..."
                .byte	CR,LF,0
                lda	#<reentry
                sta	POINTL	;point back to start...
                lda	#>reentry
                sta	POINTH	;...of this code
                jmp	SHOW1	;return to KIM
;
;=====================================================
; Force a cold start.
;
doCold:		inc	ColdFlag	;foul up flag
                jmp	extKim		;...and restart
;
;=====================================================
; Command handler for the ? command
;
showHelp:	jsr	putsil
                .byte	CR,LF
                .byte	"Available commands:"
                .byte	CR,LF,LF,0
;
; Print help for built-in commands...
;
                lda	#<commandTable
                sta	POINTL
                lda	#>commandTable
                sta	POINTH
                jsr	displayHelp	;display help
;
; Now print help for the extension commands...
;
                lda	ExtensionAddr
                sta	POINTL
                lda	ExtensionAddr+1
                sta	POINTH
                jsr	displayHelp
                jsr	CRLF
                jmp	extKimLoop
;
;=====================================================
; This is a generic "not done yet" holder.  Any
; unimplemented commands should point here.
;
NDY:		jsr	putsil
                .byte	CR,LF
                .byte	"Sorry, not done yet."
                .byte	CR,LF,0
NDYdone:	jmp	extKimLoop
;
;=====================================================
; Do a hex dump of a region of memory.  This code was
; taken from MICRO issue 5, from an article by
; J.C. Williams.  I changed it a bit, but it's still
; basically the same code.
;
; Slight bug: the starting address is rounded down to
; a multiple of 16.  I'll fix it eventually.
;
hexDump:	jsr	getAddrRange
                bcs	NDYdone
                jsr	CRLF
                jsr	doHexDump	;subroutine does it
cmdRet2:	jmp	extKimLoop
;
;=====================================================
; This subroutine does a hex dump from the address in
; SAL/H to EAL/H.
;
; Move start address to POINT but rounded down to the
; 16 byte boundary.
;
doHexDump:	lda	SAH
                sta	POINTH
                lda	SAL
                and	#$f0	;force to 16 byte
                sta	POINTL
;
; This starts each line.  Set flag to indcate we're
; doing the hex portion, print address, etc.
;
hexdump1:	lda	#0	;set flag to hex mode
                sta	ID
                jsr	CRLF
                jsr	PRTPNT	;print the address
hexdump2:	lda	POINTL	;push start of line...
                pha		;...address onto stack
                lda	POINTH
                pha
                jsr	space2
                ldx	#BYTESLINE-1	;number of bytes per line
                jsr	space2	;space before data

hexdump3:	ldy	#0	;get next byte...
                lda	(POINTL),y
                bit	ID	;hex or ASCII mode?
                bpl	hexptbt	;branch .if hex mode
;
; Print char .if printable, else print a dot
;
                cmp	#' '
                bcc	hexdot
                cmp	#'~'
                bcc	hexpr
hexdot:		lda	#'.'
hexpr:		jsr	OUTCH
                jmp	hexend
;
; Print character as hex.  
;
hexptbt: 	jsr	PRTBYT	;print as hex
                jsr	space	;and follow with a space
;
; See .if we just dumped the last address.  .if not, then
; increment to the next address and continue.
;
hexend:  	lda	POINTL	;compare first
                cmp	EAL
                lda	POINTH
                sbc	EAH
;
; Now increment to the next address
;
                php
                jsr	INCPT
                plp
                bcc	hexlntst
;
                bit	ID
                bmi	hexdone
                dex
                bmi	hexdomap
hexdump5:	jsr	space3
                dex
                bpl	hexdump5
hexdomap:	dec	ID
                pla
                sta	POINTH
                pla
                sta	POINTL
                jmp     hexdump2
hexlntst:	dex
                bpl	hexdump3
                bit	ID
                bpl	hexdomap
                pla
                pla
                jmp	hexdump1
;
; Clean up the stack and we're done
;
hexdone:	jsr	CRLF
                pla
                pla
                rts
;
;=====================================================
; This does a memory test of a region of memory.  One
; problem with the KIM is that there is no routine to
; see .if a new character is starting, so this loop
; just runs forever unless the user presses RESET.
;
; Asks for the starting and ending locations.
;
; This cycles a rolling bit, then adds a ninth
; pattern to help detect shorted address bits.
; Ie: 01, 02, 04, 08, 10, 20, 40, 80, BA
;
pattern		=	CHKL		;re-use some KIM locations
original	=	CHKH
;
; Test patterns
;
PATTERN_0	=	$01
PATTERN_9	=	$ba
;
cmdRet5:	jmp	extKimLoop
memTest:	jsr	getAddrRange	;get range
                bcs	cmdRet5		;branch .if abort
;
                jsr	putsil
                .byte	CR,LF
                .byte	"Testing memory.  Press RESET to abort"
                .byte	0
                lda	#PATTERN_0	;only set initial...
                sta	pattern		;..pattern once
;
; Start of loop.  This fills/tests one complete pass
; of memory.
;
memTestMain:	lda	SAL	;reset pointer to start
                sta	POINTL
                lda	SAH
                sta	POINTH
;
; Fill memory with the rolling pattern until the last
; location is filled.
;
                ldy	#0
                lda	pattern
                sta	original
memTestFill:	sta	(POINTL),y
                cmp	#PATTERN_9	;at last pattern?
                bne	memFill3
                lda	#PATTERN_0	;restart pattern
                jmp	memFill4
;
; Rotate pattern left one bit
;
memFill3:	asl	a
                bcc	memFill4	;branch .if not overflow
                lda	#PATTERN_9	;ninth pattern
;
; The new pattern is in A.  Now see .if we've reached
; the end of the area to be tested.
;
memFill4:	pha			;save pattern
                lda	POINTL
                cmp	EAL
                bne	memFill5
                lda	POINTH
                cmp	EAH
                beq	memCheck
;
; Not done, so move to next address and keep going.
;
memFill5:	jsr	INCPT
                pla			;recover pattern
                jmp	memTestFill
;
; Okay, memory is filled, so now go back and test it.
; We kept a backup copy of the initial pattern to
; use, but save the current pattern as the starting
; point for the next pass.
;
memCheck:	pla
                sta	pattern		;for next pass
                lda	SAL		;reset pointer to start
                sta	POINTL
                lda	SAH
                sta	POINTH
                lda	original	;restore initial pattern
                ldy	#0
memTest2:	cmp	(POINTL),y
                bne	memFail
                cmp	#PATTERN_9
                bne	memTest3
;
; Time to reload the pattern
;
                lda	#PATTERN_0
                bne	memTest4
;
; Rotate pattern left one bit
;
memTest3:	asl	a
                bcc	memTest4
                lda	#PATTERN_9
;
; The new pattern is in A.
;
memTest4:	pha			;save pattern
                lda	POINTL
                cmp	EAL
                bne	memTest5	;not at end
                lda	POINTH
                cmp	EAH
                beq	memDone		;at end of pass
;
; Not at end yet, so inc pointer and continue
;
memTest5:	jsr	INCPT
                pla
                jmp	memTest2
;
; Another pass has completed.
;
memDone:		pla
                lda	#'.'
                jsr	OUTCH
                jmp	memTestMain
;
; Failure.  Display the failed address, the expected
; value and what was actually there.
;
memFail:	pha		;save pattern for error report
                jsr	putsil
                .byte	CR,LF
                .byte	"Failure at address ",0
                jsr	PRTPNT
                jsr	putsil
                .byte	".  Expected ",0
                pla
                jsr	PRTBYT
                jsr	putsil
                .byte	" but got ",0
                ldy	#0
                lda	(POINTL),y
                jsr	PRTBYT
                jsr	CRLF
cmdRet4:	jmp	extKimLoop
;
;=====================================================
; Edit memory.  This waits for a starting address to be
; entered.  It will display the current address and its
; contents.  Possible user inputs and actions:
;
;   Two hex digits will place that value in memory
;   RETURN moves to next address
;   BACKSPACE moves back one address
;
editMemory:     jsr	space
                jsr	getStartAddr
                bcs	cmdRet4
                lda	SAL		;move address into...
                sta	POINTL		;...POINT
                lda	SAH
                sta	POINTH
                jsr	CRLF
                jsr	doEdit
                jmp	extKimLoop
;
;=====================================================
; This subroutine edits memory.  On entry, POINT has
; the first address to edit.  Upon exit, POINT will
; have been updated to next address to edit.
;
; Display the current location
;
doEdit:		jsr	PRTPNT		;print address
                jsr	space
                ldy	#0
                lda	(POINTL),y	;get byte
                jsr	PRTBYT		;print it
                jsr	space
;
                jsr	getHex
                bcs	editMem2	;not hex
editMem7:	ldy	#0
                sta	(POINTL),y	;save new value
;
; Bump POINT to next location
;
editMem3:	jsr	CRLF
                jsr	INCPT
                jmp	doEdit
;
; Not hex, so see .if another command.  Valid commands are:
;
;    CR = advance to next memory location
;    BS = move to previous location
;    R  = compute relative offset
;
editMem2:	cmp	#'R'		;compute relative branch
                beq	editMem4
                cmp	#CR
                beq	editMem3	;move to next
                cmp	#BS
                bne     editexit		;else exit
;
; Move back one location
;
                lda	POINTL
                bne	editMem8
                dec	POINTH
editMem8:	dec	POINTL
                jsr	CRLF
                jmp	doEdit
;
editexit:	rts
;
; They want to calculate a relative offset
;
editMem4:	jsr	putsil
                .byte	"elative offset to: ",0
                jsr	getEndAddr
                bcs	doEdit		;bad input
;
; Need to load POINTL/POINTH into SAL/SAH and then
; decrement by one.
;
                lda	POINTH
                sta	SAH
                lda	POINTL
                sta	SAL
                bne	editMem5
                dec	SAH
editMem5:	dec	SAL
;
                jsr	ComputeOffset
                bcc	editMem6	;value good
                jsr	putsil
                .byte	" - out of range",0
                jmp	doEdit
;
; Relative offset is in A.
;
editMem6:	pha
                jsr	space
                pla
                pha
                jsr	PRTBYT		;print it
                pla
                jmp	editMem7	;store it
;
;=====================================================
; This handles the Load hex command.
;
loadHex:	jsr	putsil
                .byte	CR,LF
                .byte	"Enter filename, or Enter to "
                .byte	"load from console: ",0
;
                jsr	getFileName	;get filename
                lda	filename	;null?
                bne	loaddiskfile
                jsr	loadHexConsole	;load from console
                jmp	loadCheckAuto	;check auto-run
;
; Open the file
;
loaddiskfile:	ldy	#<filename
                ldx	#>filename
                lda	#$ff
                sta	ID		;print dots
                jsr	loadHexFile
;
; .if the auto-run vector is no longer $ffff, then jump
; to whatever it points to.
;
loadCheckAuto:	lda	AutoRun+1
                cmp	#$ff		;unchanged?
                beq	lExit11
                jmp	(AutoRun)	;execute!
lExit11:	jmp	extKimLoop
;
;=====================================================
; This subroutine loads a hex file from the SD.  On
; entry the pointer to the filename is in X (MSB) and
; Y (LSB).
;
loadHexFile:	lda	#$ff
                sta	AutoRun+1
                sta	ID		;we want dots
                jsr	DiskOpenRead
                bcc	loadHexOk	;opened ok
;
openfail:	jsr	putsil
                .byte	CR,LF
                .byte	"Failed to open file"
                .byte	CR,LF,0
                rts
;
loadHexOk:	jsr	setInputFile	;redirect input
                jmp	loadStart
;
;=====================================================
; This subroutine is called to load a hex file from
; the console.
;
loadHexConsole:	lda	#$ff
                sta	AutoRun+1
                lda	#0
                sta	ID		;don't print dots
                jsr	putsil
                .byte	CR,LF
                .byte	"Waiting for file, or ESC to"
                .byte	" exit..."
                .byte	CR,LF,0
                jsr	setInputConsole
;
; The start of a line.  First character should be a
; colon, but toss out CRs, LFs, etc.  Anything else
; causes an abort.
;
loadStart:	jsr	redirectedGetch	;get start of line
                cmp	#CR
                beq	loadStart
                cmp	#LF
                beq	loadStart
                cmp	#':'		;what we expect
                bne	loadAbortB
;
; Get the header of the record
;
                lda	#0
                sta	CHKL		;initialize checksum
;
                jsr	getHex		;get byte count
                bcs	loadAbortC
                sta	byteCount	;save byte count
                jsr	updateCrc
                jsr	getHex		;get the MSB of offset
                bcs	loadAbortD
                sta	POINTH
                jsr	updateCrc
                jsr	getHex		;get LSB of offset
                bcs	loadAbortE
                sta	POINTL
                jsr	updateCrc
                jsr	getHex		;get the record type
                bcs	loadAbortF
                jsr	updateCrc
;
; Only handle two record types:
;    00 = data record
;    01 = end of file record
;
                cmp	#DATA_RECORD
                beq	loadDataRec
                cmp	#EOF_RECORD
                beq	loadEof
;
; Unknown record type
;
                lda	#'A'		;reason
;
; This is the common error handler for various reasons.
; On entry A contains an ASCII character which is output
; to indicate the specific error reason.
;
loadAbort:      pha			;save reason
                jsr	putsil
                .byte	CR,LF
                .byte	"Aborting, reason: "
                .byte	0
                pla			;restore and...
                jsr	OUTCH		;...display reason
                jsr	CRLF
loadExit:	jsr	setInputConsole
                rts
;
; Various error reason codes.  This was meant to be
; very temporary as I worked out the real problem, but
; this debug code immediately "solved" the problem so
; I just left these as-is until the root cause is
; discovered.
;
loadAbortB:	lda	#'B'
                bne	loadAbort
;
loadAbortC:	lda	#'C'
                bne	loadAbort
;
loadAbortD:	lda	#'D'
                bne	loadAbort
;
loadAbortE:	lda	#'E'
                bne	loadAbort
;
loadAbortF:	lda	#'F'
                bne	loadAbort
;
loadAbortG:	lda	#'G'
                bne	loadAbort
;
loadAbortH:	lda	#'H'
                bne	loadAbort
;
; EOF is easy
;
loadEof:	jsr	getHex		;get checksum
                jsr	setInputConsole	;reset input vector
                jsr	putsil
                .byte	CR,LF
                .byte	"Success!"
                .byte	CR,LF,0
                rts
;
; Data records have more work.  After processing the
; line, print a dot to indicate progress.  This should
; be re-thought as it could slow down loading a really
; big file .if the console speed is slow.
;
loadDataRec:	ldx	byteCount	;byte count
                ldy	#0		;offset
loadData1:	stx	byteCount
                sty	saveY
                jsr	getHex
                bcs	loadAbortG
                jsr	updateCrc
                ldy	saveY
                ldx	byteCount
                sta	(POINTL),y
                iny
                dex
                bne	loadData1
;
; All the bytes were read so get the checksum and see
; .if it agrees.  The checksum is a twos-complement, so
; just add the checksum into what we've been calculating
; and .if the result is zero then the record is good.
;
                jsr	getHex		;get checksum
                clc
                adc	CHKL
                bne	loadAbortH	;non-zero is error
;
; .if loading from an SD file then print a dot at the
; end of each record.  Doing this for serial input is
; very bad because the terminal program is sending the
; next character while this is sending the dot.  Ie,
; data is lost.
;
                lda	ID
                beq	lrecdone	;jump .if not file
                lda	#'.'		;sanity indicator when
                jsr	OUTCH		;...loading from file
lrecdone:	jmp	loadStart
lExit1:		jmp	extKimLoop
;
;=====================================================
; Handles the command to save a region of memory as a
; file on the SD.
;
saveHex:	jsr	getAddrRange	;get range to dump
                bcs	lExit1	;abort on error
;
; Get the filename to save to
;
                jsr	putsil
                .byte	CR,LF
                .byte	"Enter filename, or Enter to "
                .byte	"display to console: ",0
;
                jsr	getFileName	;get filename
                lda	filename	;null?
                beq	saveHexConsole	;dump to console
;
; They selected a file, so try to open it.
;
                ldx	#>filename
                ldy	#<filename
                jsr	DiskOpenWrite	;attempt to open file
                bcc	sopenok		;branch .if opened ok
                jmp	openfail
;
sopenok:	jsr	setOutputFile
                jmp	savehex2
;
; They are saving to the console.  Set up the output
; vector and do the job.
;
saveHexConsole:	jsr	setOutputConsole
;
; Compute the number of bytes to dump
;
savehex2:	sec
                lda	EAL
                sbc	SAL
                sta	Temp16L
                lda	EAH
                sbc	SAH
                sta	Temp16H
                bcc	SDone	;start > end
                ora	#0
                bmi	SDone	;more than 32K seems wrong
;
; Add one to the count
;
                inc	Temp16L
                bne	slab1
                inc	Temp16H
;
; Move pointer to zero page
;
slab1:		lda	SAL
                sta	POINTL
                lda	SAH
                sta	POINTH
;
; Top of each loop.  Start by seeing .if there are any bytes
; left to dump.
;
Sloop1:		lda	Temp16H
                bne	Sgo	;more to do
                lda	Temp16L
                bne	Sgo	;more to do
;
; At end of the region, so output an end record.  This
; probably looks like overkill but keep in mind this
; might be going to a file so we can't use the normal
; string put functions.
;
                lda	#':'
                jsr	redirectedOutch
                lda	#0
                jsr	HexToOutput
                jsr	HexToOutput
                jsr	HexToOutput
                lda	#1
                jsr	HexToOutput
                lda	#$ff
                jsr	HexToOutput
;
; .if output to file, flush and close the file.
;
                lda	filename
                beq	SDone		;it's going to console
                jsr	CloseOutFile
SDone:		jmp	extKimLoop	;back to the monitor
;
; This dumps the next line.  See how many bytes are left to do
; and .if more than BYTESLINE, then just do BYTESLINE.
;
Sgo:		lda	Temp16H
                bne	Sdef	;do default number of bytes
                lda	Temp16L
                cmp	#BYTESLINE
                bcc	Scnt	;more than max per line
Sdef:		lda	#BYTESLINE
Scnt:		sta	SAVX	;for decrementing
                sta	ID	;for subtracting
;
; Put out the header
;
                lda	#':'
                jsr	redirectedOutch
;
                lda	SAVX
                sta	CHKL	;start checksum
                jsr	HexToOutput
;
                lda	POINTH	;starting address
                jsr	updateCrc
                jsr	HexToOutput
                lda	POINTL
                jsr	updateCrc
                jsr	HexToOutput
;
                lda	#0	;record type - data
                jsr	HexToOutput
;
; Now print the proper number of bytes
;
Sloop2:		ldy	#0
                lda	(POINTL),y	;get byte
                jsr	updateCrc
                jsr	HexToOutput
                jsr	INCPT	;increment pointer
;
sdec:		dec	SAVX
                bne	Sloop2
;
; Now print checksum
;
                lda	CHKL
                eor	#$ff	;one's complement
                clc
                adc	#1	;two's complement
                jsr	HexToOutput
;
; Output a CR/LF
;
                lda	#CR
                jsr	redirectedOutch
                lda	#LF
                jsr	redirectedOutch
;
; .if saving to disk, output a dot to indicate progress.
;
                lda	filename
                beq	shf2
;
                lda	#'.'
                jsr	OUTCH	;goes to console
;
shf2:		sec
                lda	Temp16L
                sbc	ID
                sta	Temp16L
                lda	Temp16H
                sbc	#0
                sta	Temp16H
;
                jmp	Sloop1
;
;=====================================================
; Adds the character in A to the CRC.  Preserves A.
;
updateCrc:	pha
                clc
                adc	CHKL
                sta	CHKL
                pla
                rts
;
;=====================================================
; Handles the command to prompt for an address and then
; jump to it.
;
jumpAddress:    jsr	space
                jsr	getStartAddr
                bcs	cmdRet	;branch on bad address
                jsr	CRLF
                jmp	(SAL)	;else jump to address
;
cmdRet:		jmp	extKimLoop
;
;=====================================================
; Ping the Arduno disk controller.  This just sends the
; PING command gets back one character, then returns.
; Not much of a test but is sufficient to prove the
; link is working.
;
pingDisk:
;		jsr	xParInit	;init interface
                jsr	putsil
                .byte	"ing... ",0
                jsr	DiskPing
                jsr	putsil
                .byte	"success!"
                .byte	CR,LF,0
                jmp	extKimLoop
;
;=====================================================
; Do a disk directory of the SD card.
;
doDiskDir:	jsr	putsil
                .byte	"isk Directory..."
                .byte	CR,LF,0
                jsr	doSDDiskDir
                jmp	extKimLoop
doDiskDirEnd:	rts
;
;=====================================================
; Subroutine to do a disk directory.  Prints filenames
; to the console.
;
doSDDiskDir:	jsr	xParInit
                jsr	DiskDir
;
; Get/Display each entry
;
doDiskDirLoop:	ldx	#>filename	;pointer to buffer
                ldy	#<filename
                stx	INH		;save for puts
                sty	INL
                jsr	DiskDirNext	;get next entry
                bcs	doDiskDirEnd	;carry = end of list
                jsr	space3
                jsr	puts		;else print name
                jsr	CRLF
                jmp	doDiskDirLoop	;do next entry
;
;=====================================================
; Type the contents of an SD file to console.
;
typeFile:	jsr	putsil
                .byte	" - Enter filename: ",0
                jsr	getFileName
                ldy	#<filename
                ldx	#>filename
;		jsr	xParInit
                jsr	DiskOpenRead
                bcc	typeFile1	;opened ok
;
                jsr	putsil
                .byte	CR,LF
                .byte	"Failed to open file"
                .byte	CR,LF,0
                jmp	extKimLoop
;
; Now just keep reading in bytes and displaying them.
;
typeFile1:	jsr	setInputFile	;reading from file
typeFileLoop:	jsr	getNextFileByte
                bcs	typeEof
                jsr	OUTCH	;display character
                jmp	typeFileLoop
;
typeEof:	jsr	DiskClose
                jmp	extKimLoop
;
;=====================================================
; Calculate the offset for a relative branch.  6502
; relative branch calculations are well known.
;
; Offset from branch (BASE) = TARGET - (BASE+2).
; .if the result is positive, upper byte must be
; zero.  .if negative, upper byte must be FF.
;
; BASE	TARGET	Computed	Actual
; 0200	0200	0200-(0200+2)	FFFE
; 0200	020E	020E-(0200+2)	000C
; 0226	0220	0220-(0226+2)	FFF8
; 0156	015A	015A-(0156+2)	0002
; 015C	012D	012D-(015C+2)	FFCF
; 0200	0300	0300-(0200+2)	00FE - out of range
; 0300	0200	0200-(0300+2)	FEFE - out of range
;
offCalc:	jsr	putsil
                .byte	" - Branch instruction address: "
                .byte	0
                jsr	getStartAddr
                bcs	calcExit
                jsr	putsil
                .byte	", branch to: "
                .byte	0
                jsr	getEndAddr
                bcs	calcExit
                jsr	ComputeOffset	;does the work
                bcc	relgood		;if good offset
;
; Branch is out of range.
;
                jsr	putsil
                .byte	" - out of range",CR,LF,0
calcExit:	jmp	extKimLoop
;
; Branch is in range so dislay the value.
;
relgood:	pha			;save offset
                jsr	putsil
                .byte	" Offset: ",0
                pla
                jsr	PRTBYT
                jmp	extKimLoop
;
; Add new commands here...
;

;
;=====================================================
; This subroutine will search for a command in a table
; and call the appropriate handler.  See the command
; table near the start of the code for what the format
; is.  .if a match is found, pop off the return address
; from the stack and jump to the code.  Else, return.
;
searchCmd:	ldy	#0
cmdLoop:	lda	(POINTL),y
                beq	cmdNotFound
                cmp	ACC	;compare to user's input
                beq	cmdMatch
                iny		;start of function ptr
                iny
                iny		;start of help
                iny
                iny		;move to next command
                bne	cmdLoop
;
; It's found!  Load up the address of the code to call,
; pop the return address off the stack and jump to the
; handler.
;
cmdMatch:	iny
                lda	(POINTL),y	;handler LSB
                pha
                iny
                lda	(POINTL),y	;handler MSB
                sta	POINTH
                pla
                sta	POINTL
                pla		;pop return address
                pla
                jmp	(POINTL)
;
; Not found, so just return.
;
cmdNotFound:	rts
;
;=====================================================
; Given a pointer to a command table in POINT, display
; the help text for all commands in the table.
;
displayHelp:	ldy	#0	;index into command table
showHelpLoop:	lda	(POINTL),y	;get command
                beq	showHelpDone	;jump .if at end
;
; Display this entry's descriptive text
;
                iny		;skip over command
                iny		;skip over function ptr
                iny
                lda	(POINTL),y
                sta	INL
                iny
                lda	(POINTL),y
                sta	INH
                tya
                pha
                jsr	OUTSP
                jsr	OUTSP
                jsr	puts	;print description
                jsr	CRLF
                pla
                tay
                iny		;point to next entry
                bne	showHelpLoop
showHelpDone:	rts
;
;=====================================================
; Print some spaces.
;
space3:		jsr	space
space2:		jsr	space
space:   	jmp	OUTSP
;
;=====================================================
; This prints the null-terminated string that
; immediately follows the JSR to this function.  This
; version was written by Ross Archer and is at:
;
;    www.6502.org/source/io/primm.htm
;
putsil:		pla
                sta	INL
                pla
                sta	INH
                ldy	#1
                jsr	putsy
                inc	INL
                bne	puts2
                inc	INH
puts2:		jmp	(INL)
;
;=====================================================
; This prints the null terminated string pointed to by
; INL and INH.  Modifies those locations to point to
; the end of the string.
;
puts:		ldy	#0
putsy:		lda	(INL),y
                inc	INL
                bne	puts1
                inc	INH
puts1:		ora	#0
                beq	putsdone
                sty	saveY
                jsr	OUTCH	;print character
                ldy	saveY
                jmp	putsy
putsdone:	rts
;
;=====================================================
; This gets two hex characters and returns the value
; in A with carry clear.  .if a non-hex digit is
; entered, then A contans the offending character and
; carry is set.
;
getHex:		jsr	getNibble
                bcs	getNibBad
                asl	a
                asl	a
                asl	a
                asl	a
                sta	saveA
                jsr	getNibble
                bcs	getNibBad
                ora	saveA
                clc
                rts
;
; Helper.  Gets next input char and converts to a
; value from 0-F in A and returns C clear.  .if not a
; valid hex character, return C set.
;
getNibble:	jsr	redirectedGetch
                ldx	#nibbleHexEnd-nibbleHex-1
getNibble1:	cmp	nibbleHex,x
                beq	getNibF	;got match
                dex
                bpl	getNibble1
getNibBad:	sec
                rts

getNibF:	txa		;index is value
                clc
                rts
;
nibbleHex:	.byte	"0123456789ABCDEF"
nibbleHexEnd	=	*
;
;=====================================================
; Gets a four digit hex address amd places it in
; SAL and SAH.  Returns C clear .if all is well, or C
; set on error and A contains the character.
;
getStartAddr:	jsr	getHex
                bcs	getDone
                sta	SAH
                jsr	getHex
                bcs	getDone
                sta	SAL
                clc
getDone:	rts
;
;=====================================================
; Gets a four digit hex address amd places it in
; EAL and EAH.  Returns C clear .if all is well, or C
; set on error and A contains the character.
;
getEndAddr:	jsr	getHex
                bcs	getDone
                sta	EAH
                jsr	getHex
                bcs	getDone
                sta	EAL
                clc
                rts
;
;=====================================================
; Get an address range and leave them in SAL and EAL.
;
getAddrRange:   jsr	space
                jsr	getStartAddr
                bcs	getDone
                lda	#'-'
                jsr	OUTCH
                jsr	getEndAddr
                rts
;
;=====================================================
; This computes the relative offset between the
; address in SAL/SAH (address of branch instruction)
; and EAL/EAH (address to jump to).  .if a valid range,
; returns C clear and the offset in A.  .if the branch
; is out of range, C is set and A undefined.  Modifies
; A, SAL and SAH.
;
ComputeOffset:
;
; Add two to the end (BASE) address.  For calculations:
;   BASE = SAL/SAH
;   TARGET = EAL/EAH
;
                clc
                lda	SAL
                adc	#2
                sta	SAL
                bcc	coffsub
                inc	SAH
;
; Subtract the BASE (end) address from the TARGET (start)
;
coffsub:	sec
                lda	EAL
                sbc	SAL
                pha		;save for later
                sta	SAL
                lda	EAH
                sbc	SAH
                sta	SAH	;SAL/SAH contain offset
;
; High part must be either FF for negative branch or
; 00 for a positive branch.  Cheat a bit here by rolling
; the MSBit into C and adding to the MSByte.  .if the
; result is zero then everything is cool.
;
                pla		;restore LSB of offset
                pha
                asl	a	;put sign into C
                lda	SAH
                adc	#0
                beq	cogood	;branch .if in range
;
                pla		;clean up stack
                sec		;error
                rts
;
cogood:		pla		;get back offset
                clc
                rts
;
;=====================================================
; Get a disk filename.  The KIM's behavior of echoing
; every key prevents this from being too fancy, but it's
; good enough.
;
getFileName:	ldx	#0
getFilename1:	jsr	GETCH	;get next key
                cmp	#CR	;end of the input?
                beq	getFnDone
                cmp	#BS	;backspace?
                beq	getFnDel
                cpx	#FILENAME_SIZE	;check size
                beq	getFilename1	;at length limit
                sta	filename,x	;else save it
                inx
                bne	getFilename1
;
getFnDel:	dex		;back up one
                bpl	getFilename1
                inx		;can't go past start
                beq	getFilename1
getFnDone:       lda	#0	;terminate line
                sta	filename,x
                jsr	CRLF
                rts
;
;=====================================================
; This gets the next byte from an open disk file.  If
; there are no more bytes left, this returns C set.
; Else, C is clear and A contains the character.
;
getNextFileByte:
                ldx 	diskBufOffset
                cpx	diskBufLength
                bne	hasdata		;branch .if still data
;
; There is no data left in the buffer, so read a
; block from the SD system.
;
                lda	#BUFFER_SIZE
                ldx	#>buffer
                ldy	#<buffer
                jsr	DiskRead
                bcs	getNextEof
;
; A contains the number of bytes actually read.
;
                sta	diskBufLength	;save length
                cmp	#0		;shouldn't happen
                beq	getNextEof
;
                ldx	#0
hasdata:	lda	buffer,x
                inx
                stx	diskBufOffset
                clc
                rts
;
getNextEof:	lda	#0
                sta	diskBufOffset
                sta	diskBufLength
                sec
                rts

;
;=====================================================
; This is a helper function used for redirected I/O.
; It simply does a jump through the input vector
; pointer to get the next input character.
;
redirectedGetch:
                jmp	(inputVector)
;
;=====================================================
; Set up the input vector to point to the normal
; console input subroutine.
;
setInputConsole:
                lda	#GETCH&$ff
                sta     inputVector
                lda	#GETCH/256
                sta	inputVector+1
                rts
;
;=====================================================
; Set up the input vector to point to a file read
; subroutine.
;
setInputFile:   lda	#<getNextFileByte
                sta     inputVector
                lda	#>getNextFileByte
                sta	inputVector+1
;
; Clear counts and offsets so the next read will
; cause the file to be read.
;
                lda	#0
                sta	diskBufOffset
                sta	diskBufLength
                rts
;
;=====================================================
; Print character in A as two hex digits to the
; current output device (console or file).
;
HexToOutput:	pha		;save return value
                pha
                lsr	a	;move top nibble to bottom
                lsr	a
                lsr	a
                lsr	a
                jsr	hexta	;output nibble
                pla
                jsr	hexta
                pla		;restore
                rts
;
hexta:		and	#%0001111
                cmp	#$0a
                clc
                bmi	hexta1
                adc	#7
hexta1:		adc	#'0'	;then fall into...
;
;=====================================================
; This is a helper function used for redirected I/O.
; It simply does a jump through the output vector
; pointer to send the character in A to the proper
; device.
;
redirectedOutch:
                jmp	(outputVector)
;
;=====================================================
; This flushes any data remaining in the disk buffer
; and then closes the file.
;
CloseOutFile:	lda	diskBufOffset
                beq	closeonly
                ldx	#>buffer
                ldy	#<buffer
                jsr	DiskWrite
;
closeonly:	jsr	DiskClose
;
; Fall through...
;
;=====================================================
; Set up the output vector to point to the normal
; console output subroutine.
;
setOutputConsole:
                lda	#OUTCH&$ff
                sta     outputVector
                lda	#OUTCH/256
                sta	outputVector+1
                rts
;
;=====================================================
; Set up the output vector to point to a file write
; subroutine.
;
setOutputFile:	lda	#<putNextFileByte
                sta     outputVector
                lda	#>putNextFileByte
                sta	outputVector+1
;
; Clear counts and offsets so the next read will
; cause the file to be read.
;
                lda	#0
                sta	diskBufOffset
                rts
;
;=====================================================
; Add the byte in A to the output buffer.  .if the
; buffer is full, flush it to disk.
;
putNextFileByte:
                ldx	diskBufOffset
                cpx	#BUFFER_SIZE	;buffer full?
                bne	pNFB		;no
;
; The buffer is full, so write it out.
;
                pha			;save byte
                lda	#BUFFER_SIZE
                ldx	#>buffer
                ldy	#<buffer
                jsr	DiskWrite
;
                ldx	#0		;reset index
                pla
pNFB:		sta	buffer,x
                inx
                stx	diskBufOffset
                rts
;
                .include	"pario.s"
                .include	"parproto.inc"
                .include	"diskfunc.s"
;
;=====================================================
; Show current clock
;
        .if	SHOW_RTC
doShowClock:	jsr	xParSetWrite
                lda	#PC_GET_CLOCK
                jsr	xParWriteByte
                jsr	xParSetRead	;prepare to read
;
                jsr	xParReadByte
;
; Loop to read the raw data
;
                ldx	#0
clockread:	stx	saveX
                jsr	xParReadByte
                ldx	saveX
                sta	month,x
                inx
                cpx	#clock_end-month
                bne	clockread
;
; Set back to write mode to finish up; all apps are
; supposed to leave the SD interface in write mode.
;
                jsr	xParSetWrite
;
; Now display the data in a user-friendly format.  Each
; numberic value is in binary, so convert to decimal
; for display.
;
                jsr	putsil
                .byte	CR,LF
                .byte	"Date: ",0
;
                lda	month
                jsr	outdec
                lda	#'/'
                jsr	OUTCH
                lda	day
                jsr	outdec
;
; Always force the high part of the year to "/20"
;
                jsr	putsil
                .byte	"/20",0
                lda	year_low
                jsr	outdec
;
; Space over, then do the time
;
                jsr	putsil
                .byte	", ",0
;
                lda	hour
                jsr	outdec
                lda	#':'
                jsr	OUTCH
                lda	minute
                jsr	outdec
                lda	#':'
                jsr	OUTCH
                lda	second
                jsr	outdec
;
                jsr	putsil
                .byte	CR,LF,0
                jmp	extKim	;return to monitor
;
;========================================================
; Given a binary value in A, display it as two decimal
; digits.  The input can't be greater than 99.  Always
; print a leading zero .if less than 10.
;
outdec:		ldy	#0	;counts 10s
out1:		cmp	#10
                bcc	out2	;below 10
                iny		;count 10
                sec
                sbc	#10
                jmp	out1
;
out2:		pha		;save ones
                tya		;get tens
                jsr	out3	;print tens digit
                pla		;restore ones
;
out3:		ora	#'0'
                jsr	OUTCH
                rts

        .endif
;
        .if	TINY_BASIC
                .include "mytb.s"
        .endif

;
;=====================================================
; These are the 6502 vectors.  On the Corsham
; Technologies RAM/ROM board the user can select
; whether or not to use these based on a switch
; setting on the board.
;
        .if	!RAM_BASED
                .segment	"vectors"
NMI:		.word	NMIT	;in KIM
RESET:		.word	RST	;in KIM
IRQ:		.word	IRQT	;in KIM
        .endif
;
                .end

