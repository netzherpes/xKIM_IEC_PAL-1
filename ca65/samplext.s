;=====================================================
; A sample extension for the Extended KIM monitor.
; This is a very simple example of how to write an
; extension (adding a new command) for the 
; Extended KIM monitor.
;
; How can you test this?  Easy.  First, use the "?"
; command in the extended monitor and verify the
; "Z" command is not listed, then load the binary
; version of this file.  Do "?" again and you'll see
; the new command has been added and can be used.
;
; 12/26/2015 - Bob Applegate, bob@corshamtech.com
; 09/29/2021 - Bob Applegate
;		Minor cleanup
; 01/30/2024 - Eduardo Casino
;		CA65 port
;
; Consider buying a KIM-1 expansion board or a 
; KIM Clone computer from us:
;
;    www.corshamtech.com
;
;=====================================================
;
; First, define some common ASCII characters
;
LF		=	$0a
CR		=	$0d
;
		.include	"xkim.inc"
;
; There are more vectors but I didn't need them
;
;=====================================================
; The actual sample
;
                .segment        "ExtensionAddr"

;
; Set up the pointer to our sample extension...
;
                .word	Extension

;
; This is the table of commands being added.  Each
; entry has exactly five bytes:
;
;    Single character command
;    Address of code for this command
;    Descriptive text for this command
;
; After the last entry, the next byte must be zero
; to indicate the end of the table.
;
		.segment	"code"
Extension:
		.byte	'Z'	;adding the 'Z' command
		.word	zCode	;pointer to code
		.word	zHelp	;pointer to help
;
		.byte	0	;END OF EXTENSIONS
;
; The descriptive text...
;
zHelp:		.byte	"Z ........... Describe a zoo",0
;
; And the actual code...
;
zCode:		jsr	putsil	;call display function
		.byte	CR,LF
		.byte	"A Zoo is a place with "
		.byte	"lots of animals."
		.byte	CR,LF,0
		jmp	extKIM	;return to Extended KIM
