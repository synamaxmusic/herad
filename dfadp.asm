;
;             H   H  EEEEE  RRRR    AAA   DDDD     V   V   222 
;             H   H  E      R   R  A   A  D   D    V   V  2   2
;             HHHHH  EEEEE  RRRR   AAAAA  D   D    V   V     2 
;             H   H  E      R  R   A   A  D   D     V V    2   
;             H   H  EEEEE  R   R  A   A  DDDD       V    22222
;
;  HERAD Source Code recreated from MegaRace (DOS)'s "DFADP.HSQ" AdLib music driver
;  Original code written by Rémi Herbulot with design notes from Stéphane Picq
;  
;  Reverse-engineered and reconstructed source code by SynaMax
;  RE work started back in 2016, source code rewrite completed April 30th, 2024
;
;  Special thanks to Binarymaster and Jepael for their help
;
;  For more info on HERAD visit: https://www.vgmpf.com/Wiki/index.php/HERAD
;
;  This code targets UASM, you can use the following terminal prompt to build the driver:
;
;; uasm32 -bin -Fl"listing.txt" -Fo "dfadp.bin" dfadp.asm
;
; ---------------------------------------------------------------------------
;
;  HERAD first appeared in the 1992 DOS game, Dune and would be reused in later
;  Cryo titles like KGB/Conspiracy and lastly, MegaRace.  MegaRace's driver differs
;  from the earlier Dune version with the introduction of a drum map mode that makes
;  it much easier to sequence one-shot percussion instruments.  One draw back is that
;  the fade in/out routines from Dune have been disabled here.
;
;  HERAD stands out from other contemporary AdLib music drivers at the time, thanks to
;  the use of instrument macros that give an expressive quality to the OPL2's output.
;
;  By using the velocity of a MIDI note or using a MIDI Aftertouch event, several parameters
;  of the OPL2 can be controlled, creating complex and sophisticated sound design unheard
;  in other PC games at the time.
;
; ---------------------------------------------------------------------------

	.model tiny

	.code
	
; ---------------------------------------------------------------------------
; Constants
TrackNum	equ	9                ; 9 tracks, one for each OPL2 channel
AllTrackPtrs	equ	TrackNum*2       ; 2 bytes for each of the 9 MIDI tracks current pointers
MidiTickValue	equ	96               ; HERAD uses 96 MIDI ticks per second (PPQN)
SlideCenter	equ	64               ; Slide range center, just like the MIDI Standard

; Song Constants

sLoopStart	equ	2Ah
sLoopEnd	equ	2Ch
sLoopCount	equ	2Eh
sSpeed		equ	30h

; Instrument Chunk offsets and constants
InstSize	equ	28h              ; The size of one instrument chunk

;  0x00 is the Instrument "Mode"
iDrumMode	equ	0FFh             ; FF = DrumMap, any other mode value is regular FM instrument
;  0x01 appears to be metadata, possibly an Instrument ID number

iM_KSL		equ	2                ; Modulator Key scaling level
iM_Multiple	equ	3                ; Modulator Frequency multiplier
iFeedback	equ	4                ; Feedback
iM_Attack	equ	5                ; Modulator Attack
iM_Sus		equ	6                ; Modulator Sustain
iM_EG		equ	7                ; Modulator Envelope gain
iM_Decay	equ	8                ; Modulator Decay
iM_Rel		equ	9                ; Modulator Release
iM_Level	equ	0Ah              ; Modulator Output Level
iM_AM		equ	0Bh              ; Modulator Amplitude modulation (Tremolo)
iM_Vib		equ	0Ch              ; Modulator Frequency Vibrato
iM_KSR		equ	0Dh              ; Modulator Key scaling/envelope rate

iConnector	equ	0Eh              ; Connector

iC_KSL		equ	0Fh              ; Carrier Key scaling level
iC_Multiple	equ	10h              ; Carrier Frequency multiplier
iPanning	equ	11h              ; Panning (OPL3)
iC_Attack	equ	12h              ; Carrier Attack
iC_Sus		equ	13h              ; Carrier Sustain
iC_EG		equ	14h              ; Carrier Envelope gain
iC_Decay	equ	15h              ; Carrier Decay
iC_Rel		equ	16h              ; Carrier Release
iC_Level	equ	17h              ; Carrier Output Level
iC_AM		equ	18h              ; Carrier Amplitude modulation (Trem
iC_Vib		equ	19h              ; Carrier Frequency Vibrato
iC_KSR		equ	1Ah              ; Carrier Key scaling/envelope rate

; HERAD Instrument Macros start here
iX_FBScaleAFT	equ	1Bh              ; Feedback Scaling - Aftertouch

iM_Wave		equ	1Ch              ; Modulator Waveform Select
iC_Wave		equ	1Dh              ; Carrier Waveform Select

iX_MLevelScale	equ	1Eh              ; Modulator Output Level Scaling - Velocity
iX_CLevelScale	equ	1Fh              ; Carrier Output Level Scaling - Velocity

iX_FBScaleVEL	equ	20h              ; Feedback Scaling - Velocity
iX_SlideTrans	equ	21h              ; Pitch Slide Range Flag / Transpose bytes

iX_SlideDurRange equ	23h              ; Pitch Slide Duration / Pitch Slide Range bytes

; 25h is unused

iX_MLevelScaleAFT equ	26h              ; Modulator Output Level Scaling - Aftertouch
iX_CLevelScaleAFT equ	27h              ; Carrier Output Level Scaling - Aftertouch 

;; End of Instrument offsets	

; ---------------------------------------------------------------------------
;; For debugging purposes
;; (Adds blank space at the beginning to make the symbol addresses match up with the absolute addresses)

		;org	0
		;db 256 dup(0)

; ---------------------------------------------------------------------------
;; "DFADP.HSQ" HERAD driver starts at address 0x100 and is usually loaded
;; into memory at 3B08:0100
	
		org	100h
	
		jmp	DriverInit      ; 3B08:0100
; ---------------------------------------------------------------------------
		jmp	GetSongData     ; 3B08:0103 (Starts music playback, music data gets loaded before this is called)
; ---------------------------------------------------------------------------
		jmp	ShutUp          ; 3B08:0106 (ShutUp, kills all music playback with NoteOffs)
; ---------------------------------------------------------------------------
		jmp	ChangeSong      ; 3B08:0109 (I don't think this gets called)
; ---------------------------------------------------------------------------
		jmp	StopDriver      ; 3B08:010C (Called when game shuts down)
; ---------------------------------------------------------------------------
		jmp	SongPlay        ; 3B08:010F (This is more like a timer that decreases the byte at 0x11E if the SongFlag at 0x19A is non-zero. The game is constantly spamming this even when music isn't playing)
; ---------------------------------------------------------------------------
		jmp	TimerFF         ; 3B08:0112 (Called at the end of initialization)
; ---------------------------------------------------------------------------

SizeOffset	dw 0                    ;; This is referenced a lot to parse the song file's header (it is always 2)
		
SongSegment	dw 0
SongFileSize	dw 0
SongSegment2	dw 0

SongSpeed	dw 0
MeasureCount	dw 0
MIDITickCount	dw 0
SongPlayCount	dw 0

; ---------------------------------------------------------------------------

EventPointerTable:

; 06CF = NoteOff (80)
; 065D = NoteOn (90)
; 08E5 = Polyphonic Aftertouch (A0)
; 08E5 = Control Mode Change (B0)
; 05D2 = Program Change (C0)
; 072E = Aftertouch (D0)
; 07DD = Pitch Bend (E0)
; 06F5 = End of Track (FF)

		dw	NoteOff_80
		dw	NoteOn_90
		dw	GetChMidiDelay
		dw	GetChMidiDelay
		dw	InstChange_C0
		dw	Aftertouch_D0
		dw	PitchBend_E0
		dw	EndofTrack_FF

; ---------------------------------------------------------------------------

OPLRegTable:
		db	0, 3, 1, 4, 2, 5, 8, 0Bh, 9, 0Ch, 0Ah, 0Dh, 10h, 13h
		db	11h, 14h, 12h, 15h
FreqTable:      
		dw	157h, 16Ch, 181h, 198h, 1B1h, 1CBh, 1E6h, 203h, 222h
                dw	243h, 266h, 28Ah
FNumRegisters:
		dw	9 dup(157h)

OPLPortTable:	
		db	0, 1, 2, 8, 9, 0Ah, 10h, 11h, 12h

FineBendTable:
		db	3, 4, 5, 0Bh, 0Ch, 0Dh, 13h, 14h, 15h, 13h, 15h, 15h, 17h, 19h, 1Ah, 1Bh, 1Dh, 1Fh, 21h, 23h, 24h, 25h
CoarseBendTable:
		db	0, 5, 0Ah, 0Fh, 14h, 0, 6, 0Ch, 12h, 18h

SongFlag        db      0
ChangeSongFlag  db      0
		
EEx19C		db	0EEh
EEx19D		db	0EEh
EEx19E		db	0EEh

BitTimer	dw	1

unk_1A1		db	90h             ;; Possibly a marker to denote the start of the driver internals

; ------------------------ M U S I C  R A M ---------------------------------
;; Underscore in front of label name denotes driver internals
;; The org instructions are not needed unless there's a label that requires it
;; Each of these arrays are 18 bytes in length (2 bytes x 9 tracks)

;Current Midi Event Delay Counter (0x1A2-0x1B3)
;
; counts down until next event 

;		org	1A2h
_MidiEventDelay:

;MIDI Track Position (0x1B4-0x1C5)
;
; counts up until reaching the track end 

;		org	1B4h
_MidiTrackPos	equ	12h

;MIDI Track Start Address (0x1C6-0x1D7)
;
; Absolute address in music file, rather than relative address in music file header 

		org	1C6h
_MidiTrackStart:
_MidiTrackStartPos equ	24h

;List of MIDI tracks using drum keymap instrument (0x1D8-0x1E9)
;
; If MIDI track uses keymap instrument, the absolute offset of the instrument in the music file will be used.
; If the instrument changes back to a normal instrument, the value zeros out. 

;		org	1D8h
_MidiDrumMapPtr equ	36h	

;Current Instrument (first byte) / MIDI Pitch (second byte) (0x1EA-0x1FB)
;
; The pitch here is after any transpose macros have been applied. Also, if the keymap instrument is used,
; the first byte will display the instrument(s) that are actually being played. If no instrument or note data exist,
; the values will be 0xFF/0x00 respectively. NoteOffs are enabled by setting the highest bit to 1 in the pitch byte. 

		org	1EAh
_MidiInstOffset:
_MidiCurInst	equ	48h
_MidiCurPitch	equ	49h

;Pitch Slide Range Flag (first byte) / Root Note Transpose (second byte) for each MIDI track (0x1FC-0x20D)

;		org	1FCh
_XSlideRangeFlag equ	5Ah
_XRootNoteTrans equ	5Bh

;Pitch Slide Duration Counter (first byte) / Pitch Slide Duration (second byte) for each MIDI track (0x20E-0x21F)
;
; The Pitch Slide Counter starts at the value assigned by the second byte. 

		org	20Eh
_XSlideDurOffset:
_XSlideDurCount equ	6Ch
_XSlideDuration equ	6Dh

;Pitch Slide Counter (first byte) / Pitch Slide Range (second byte) for each MIDI track (0x220-0x231)
;
; The Pitch Slide Counter starts at 0x40 (unless it is transposed) and either goes up or down depending on Pitch Slide Range value. 

		org	220h
_XSlideCounter equ	7Eh
_XSlideRange   equ	7Fh

;Modulator Output Level Scaling (first byte) / Carrier Output Level Scaling (Second byte) (0x232-0x243)
;
; These values are taken from the current instrument. 

		org	232h
_FMOutputScaling equ	90h

;Modulator Output Level (first byte) / Carrier Output Level (Second byte) (0x244-0x255)
;
; These values are taken from the current instrument. 

		org	244h
_FMOutputLevel	equ	0A2h

;Modulator Output Level Register (first byte) / Carrier Output Level Register (Second byte) (0x256-0x267)
;
; These are the final register values that are sent to the OPL chip. 

		org	256h
_FMOutputRegister equ	0B4h

;Panning/Feedback/Connector Register Value (0x268-0x279)

		org	268h
_FMFeedbackRegister equ 0C6h

;Loop MIDI Delay Values (0x27A-0x28B)
;
; These are the values that the MIDI delay counters load when the song loops. 

		org	27Ah
_LoopMidiEventDelay equ 0D8h

;Loop Start Absolute Address for each MIDI track (0x28C-0x29D)
;
; Loads after the song passes the loop beginning measure. 
		org	28Ch
_LoopMidiStartPtr:

; ---------------------------------------------------------------------------

                org     2C2h

Terminator	db	0
HSQ             dw	5348h
HSQEND          db	51h
PortNum         dw	220h

; =============== S U B R O U T I N E =======================================

GrabHSQ:           
                push    ss
                pop     es               ; ES is 0FD9
                mov     si, bp           ; SI is 418A

LoadFileName: 
                lods    word ptr es:[si] ; Load the string word at 0FD9:418A.  The value should be 4AFD
                ;add     ax,0x0002       ; Add 2 to 4AFD, which gives us 4AFF
		;;;;;;;;;;;;;;;
		db	05h		 ;; UASM doesn't use the 05 opcode for ADD.  After several tries,
		dw      0002h		 ;; I'm left with no choice but to put this in to match up with the original HERAD driver
		;;;;;;;;;;;;;;;
                mov     di, ax           ; 0FD9:4AFF is the offset for the string "NEWSAN.HSQ"
                push    cx
                mov     cx, 9            ; put 9 in CX
                mov     al, 2Eh ; '.'    ; place a period in the low byte of AX
                repne scasb              ; stop when you encounter the period of the filename.  DI is going to be offset for the "H" in HSQ extension.
                pop     cx
                jnz     short LoadFileLOOP
                mov     ax, word ptr cs:HSQ ; grab the "HSQ" (or in this case 5348) at 3B08:02C3 (0x1C3) and place it in AX
                stosw                   ; go to the end of NEWSAN.HSQ string.
                mov     al, byte ptr cs:HSQEND ; grab "Q" from "HSQ" at 3B08:02C5 and place it in AX's low byte
                stosb

LoadFileLOOP:                         
                loop    LoadFileName
                retn


; ---------------------------------------------------------------------------

DriverInit:
		and	ax, 0FFFh
		jz	short OPLStartUp
		mov	word ptr cs:PortNum, ax	; grab port number 0220	from [02C6]

OPLStartUp:
		call	GrabHSQ
		mov	ax, 2001h	; Enable Waveform Select at OPL	register 01
		call	ChipWrite	; Write	to OPL2
		mov	ax, 0BDh ; '½'  ; Disable Percussion Mode
		call	ChipWrite	; Write	to OPL2
		mov	ax, 4008h	; Enable NOTE-SEL at OPL register 08
		call	ChipWrite	; Write	to OPL2
		push	cs
		call	near ptr ShutUp
		mov	bx, 0F00h
		retf
		

; =============== S U B	R O U T	I N E =======================================


ShutUp:		
		pushf			; clear	eflags
		cli			; clear	IF flag	in EFLAGS
		call	KeyOffAll
		xor	ax, ax		; clear	AX
		mov	cs:SongFlag, al	; write	zero to	SongFlag
		popf
		retf			; And the driver has stopped!

CreateEEE:	
		push	bx
		push	dx
		shr	al, 1		; The value in AX before this starts is	78E6
		shr	al, 1
		shr	al, 1
		mov	dx, ax		; move 781C to DX
		mov	bx, 0F078h	; place	F078 in	BX
		cmp	ah, bl		; compare the low byte of BX with the high byte	of AX.
		jbe	short EEE1
		mov	ah, bl

EEE1:
		xor	al, al		; zero out AX's low byte
		div	bh		; divide AX by BX's high byte.  The answer should be 80
		mul	dl		; AX (80) x DL (1C) = E0
		xchg	ah, dh		; DX:781C and AX:0E00 now become AX:0E1C and DX:7800
		sub	ah, bh		; 0E - F0 = 88
		neg	ah		; two's compliment of 88 = 78
		cmp	ah, bl		; compare the two 78s
		jbe	short EEE2	; if AX	is the incorrect value,	continue, otherwise jump
		mov	ah, bl		; if AX	isn't right, correct it by making it 7800

EEE2:
		xor	al, al		; zero out AX's low byte (it was already zero though)
		div	bh		; divide 7800 with F0 =	80
		mul	dl		; 80 x 1C = E00
		shr	ax, 1
		shr	ax, 1
		shr	ax, 1
		shr	ax, 1		; now AX is E0
		mov	ah, dh		; AX is	now EE0
		and	ax, 0FF0h
		or	al, ah		; AX is	now EEE
		pop	dx
		pop	bx
		retn
		
TimerFF:
		call	CreateEEE
		mov	cs:EEx19E, al	; write	EE at 0x9E
		mov	cs:EEx19D, al	; write	EE at 0x9D
		mov	cs:BitTimer, 0FFFFh ; write FFFF at 0x9F
		retf
		
StopDriver:
		push	ax
		mov	ax, bx
		call	CreateEEE
		mov	cs:EEx19D, al	; Zero out that	middle EE
		pop	ax		; value	is 12C...don't know what this is
		mov	bx, 0FFFFh	; BX = FFFF
		;cmp	ax, 60h	; '`'   ; compare with 60
		;;
		db	3Dh
		dw	60h
		;;
		jb	short StopSongFlag	; jump if below
		mov	bx, 0AAAAh
		cmp	ax, 0C0h ; 'À'
		jb	short StopSongFlag
		mov	bx, 8888h
		cmp	ax, 180h
		jb	short StopSongFlag
		mov	bx, 8080h
		cmp	ax, 300h
		jb	short StopSongFlag
		xor	bl, bl

StopSongFlag:
		mov	cs:BitTimer, bx	; write	either FFFF, AAAA, 8888, or 8080 to the	BitTimer
		mov	al, cs:SongFlag	; move the SongFlag to AX's low byte
		or	al, al
		jns	short StopDriverEnd
		or	al, 40h		; turn that 80 into a C0
		mov	cs:SongFlag, al	; write	C0 to SongFlag!

StopDriverEnd:
		retf
; ---------------------------------------------------------------------------

ChangeSong:
		mov	cs:ChangeSongFlag, 1 ; This byte was left over from the	"CD-Style" playback function from Dune and KGB.	 
					     ; When this byte was enabled, a new song would play after the current song finished
					     ; playing or ran out of loop count.  This feature doesn't work in MegaRace, as the
					     ; songs will just stop playing, except for PAGA, DETRITUS, and LENNY, as those songs
					     ; will play forever.
		mov	al, cs:SongFlag
		retf
; ---------------------------------------------------------------------------
; Temporary RAM used for loading song data
TempRAM:
Temp		dw	0		;;3BAh  
		dw	0		;; combined with Temp to become a 32-bit value	
Temp2		dw	0		;;3BEh
Temp3		db	0		;;3C0h
Temp4		db	0		;;3C1h
Temp5		dw	0		;;3C2h
; ---------------------------------------------------------------------------

GetSongData:
		push	ds
		push	cs
		pop	ds
		mov	ds:ChangeSongFlag, al ;	write the low byte of AX to 0x9B
		mov	ax, es:[si]	; loads	SongSize into AX
		mov	di, TempRAM
		mov	[di], si
		mov	word ptr [di+2], es ; writes SongSegment at 0x2BC
		mov	[di+4],	ax	; writes SongSize at 0x2BE
		mov	ax, es:[si+4000h] ; grabs word at 0x4000 in SongFile, which is 0x3379 in NewSan	(part of a note	on...what the hell?)
		mov	[di+6],	ax	; writes this value at 0x2C0
		mov	ax, es:[si-8000h] ; okay, this is really weird.	 This is suppose to grab ES:[SI-8000], which should be 3BB6:FFFF8000, however, it grabs	DS:[SI-8000], which is 3B08:FFFF8000.  I think this is happens because of how the segment registers/indexes and	pointers work.
		mov	[di+8],	ax	; writes this down at 0x2C2 (for NewSan, it's 0x2790)
		add	si, 2
		mov	ds:SizeOffset, si	; writes 2 at 0x115
		mov	ds:SongSegment,	es ; writes SongSegment	at 0x117
		sub	si, 2
		add	si, es:[si]	; grab SongSize	word at	SongSegment
		mov	ds:SongFileSize, si ; writes SongSize at 0x119
		mov	ds:SongSegment2, es ; writes SongSegment at 0x11B
		call	ClearSusRel
		call	InitTrackPtrs
		mov	al, ds:EEx19E	; grab EE at 0x19E and place in low byte at AX
		mov	ds:EEx19C, al	; write	EE at 0x19C
		call	SoundBlaster
		mov	ds:EEx19D, al	; grab EE from the low byte of AX and write it at 0x19D
		xor	ax, ax		; zero out AX
		mov	ds:SongSpeed, ax ; zero	out timer at 0x1D
		mov	ds:SongPlayCount, ax ; zero out	loop count
		call	PlayTick
		mov	al, 80h	; '€'   ; put 80 in the low byte for AX
		mov	ds:SongFlag, al	; Turn the SongFlag on by placing 80 there
		pop	ds
		retf

InitTrackPtrs:
		push	ds
		push	ds
		pop	es
		lds	si, dword ptr ds:SizeOffset ; load 0002 from 0x15	in SI
		mov	bp, si		; copy 2 from SI to BP
		mov	di, _MidiTrackStart	; get offset for the start of the MIDI tracks
		mov	cx, TrackNum	; load 9 into the CX counter

GetTrackOffset:
		lodsw			; looks	in the music file, skips the first two bytes and loads 32 (first MIDI track offset) into AX, increments	SI, repeat 9 times
		or	ax, ax		; when repeats,	get new	MIDI track offset
		jz	short InitInstPitch ; repeat 9 times until zero
		add	ax, bp		; add 2	to get 34 for absolute address

InitInstPitch:
		stosw			; place	MIDItrack offset in memory and increment DI so it can get ready	to add the next	offset
		loop	GetTrackOffset	; adds all the offsets with loop then jump here	to proceed
		mov	di, _MidiInstOffset ; load Current Instrument offset into DI
		mov	cl, TrackNum	; place	9 in CX
		mov	ax, 0FFh	; place	FF in AX
		rep stosw		; Creates FF for each instrument channel at 0x1EA...it does this by using REP to repeat	the STOSW 9 times (9 in	CX), STOSW increments the DI, so it creates the	bytes in the correct offsets.
		mov	di, _XSlideDurOffset ; load offset for Pitch Slide Duration Counter in DI
		mov	cl, TrackNum	; place	9 in CX
		xor	ax, ax		; when on repeat, get new offset
		rep stosw		; zeros	out counters
		pop	ds		; switch back to driver	segment
		les	si, dword ptr ds:SizeOffset ; load 2 into	SI

SongInitStart:
		mov	ds:MeasureCount, 1 ; Create 1 measure count for	the FourBarCount
		mov	ds:MIDITickCount, MidiTickValue ; Creates the 96 ticks for the MIDITickCount
		mov	cx, TrackNum		; place	9 in CX
		mov	di, _MidiEventDelay	; Enter	in offset for Current Midi Delay Counter

WriteDelay_Pos:
		mov	si, [di+_MidiTrackStartPos]	; add 24 to 1A2	to get 1C6, then grab the 34 that's at 0x1C6 and store it in SI
		mov	[di+_MidiTrackPos], si	; Creates the 34 at offset 0x1B4 to make the MIDI Track	Position
		mov	word ptr [di], 0FFFFh ;	places FFFF inside of DS:[01A2]
		or	si, si
		jz	short WriteDelayLoop ; add 2 to	the DI to get the rest of the offsets
		mov	ax, cx		; places 9 in AX
		call	GetChMidiDelay	; Creates the first Current Event Midi Tick Counter
		inc	word ptr [di]	; add 1	to [DI], which will be the MIDI	track delay
		mov	cx, ax		; places 9 in CX.  This	will count down	as it goes through all 9 tracks

WriteDelayLoop:
		add	di, 2		; add 2	to the DI to get the rest of the offsets
		loop	WriteDelay_Pos	; create the rest of the MIDI track delays
		retn

SongPlay:
		push	ds		; check	if SongFlag is valid
		mov	ax, cs
		mov	ds, ax
		cmp	ds:SongFlag, 0
		jns	short UpdateBitTimer2	; if SongFlag byte is not signed
		dec	byte ptr ds:SongSpeed+1	; decrease second byte of timer
		jns	short UpdateBitTimer ; jump if not signed
		call	CheckSongSize
		jnz	short UpdateBitTimer2
		push	dx
		push	si
		push	di
		push	bp
		push	es
		call	PlayTick
		pop	es
		pop	bp
		pop	di
		pop	si
		pop	dx

UpdateBitTimer:
		rol	ds:BitTimer, 1	; rotate bit to	the left by 1
		jnb	short UpdateBitTimer2	; if bit-shift counter reaches 0001, then jump
		call	sub_831

UpdateBitTimer2:
		mov	al, ds:SongFlag
		mov	bx, ds:MeasureCount
		mov	cx, ds:MIDITickCount
		pop	ds
		retf
		
; =============== S U B	R O U T	I N E =======================================


CheckSongSize:	push	si
		push	es
		les	si, dword ptr ds:Temp
		mov	ax, es:[si]	; move SongSize
		cmp	word ptr ds:Temp2, ax ; SongSize2 is 0x3BE in HERAD	Driver.	Compare	if SongSize is the same	with AX
		jnz	short CheckSongSizeEnd
		mov	ax, es:[si+4000h]
		cmp	word ptr ds:Temp3, ax
		jnz	short CheckSongSizeEnd
		mov	ax, es:[si-8000h]
		cmp	word ptr ds:Temp5, ax

CheckSongSizeEnd:
		pop	es
		pop	si
		retn


PlayTick:
		les	bx, dword ptr ds:SizeOffset ; load 0002 into BX
		mov	ax, es:[bx+sSpeed]	; add 30 to 2 to get 32, which is the offset of	the song speed in the music file!  Place that tempo into AX
		add	ds:SongSpeed, ax ; add the tempo to the	value at 0x1D
		mov	di, _MidiEventDelay	; place	the offset for Current Midi Delay Counter into DI
		call	LoopCheck
		mov	cx, TrackNum		; place	9 in CX

PlayChanLoop:
		dec	word ptr [di]	; decrease tick	count
		jnz	short UpdatePtchSlide

GetMidiEvent:
		mov	si, [di+_MidiTrackPos]	; get offset for MIDI Track Position and place position	in SI
		or	si, si
		jz	short DecreaseTick
		push	cx
		push	di
		lods	word ptr es:[si] ; grab	MIDI Event data, place it in AX	and increment SI by 2
		mov	dx, di		; grab offset from DI and place	in DX
		sub	dx, _MidiEventDelay	; subtract 1A2 from DX
		shr	dx, 1		; shift	right DX by 1
		mov	bx, ax		; copy delay byte from AX into BX
		and	bx, 70h		; AND operation	on BX with 70
		shr	bx, 1		; shift	right BX by 1
		shr	bx, 1		; shift	right BX by 1
		shr	bx, 1		; shift	right BX by 1
		call	ds:EventPointerTable[bx]	; depending on BX, grab	value from MIDI	Event Subroutine Lookup	Table and jump to offset.
		pop	di
		pop	cx
		cmp	word ptr [di], 0 ; compare 0x1A2 with zero
		jz	short GetMidiEvent ; if	zero, go back up to 3FE, otherwise continue to finish up decreasing the	tick.

DecreaseTick:
		add	di, 2		; this increases DI by 2 so that the driver will continue on to	the next channel
		loop	PlayChanLoop	; keep looping until CX	runs out
		dec	byte ptr ds:MIDITickCount ; decrease MIDI tick!
		jnz	short DecreaseTickEnd ;	if not zero, then jump to the end of the subroutine.
		mov	byte ptr ds:MIDITickCount, MidiTickValue ; '`' ; when ticks reach zero, refresh 4Bar counter to 60 (96 midi ticks)
		inc	ds:MeasureCount	; increment the	4Bar count!

DecreaseTickEnd:
		retn
; ---------------------------------------------------------------------------

UpdatePtchSlide:
		cmp	byte ptr [di+_XSlideDurCount], 0 ; compare low byte	at Pitch Slide Duration	Counter	offset with zero.  Little endian means that our	counter	is the low byte.
		jz	short DecreaseTick ; if	zero, just decrease the	tick.  if not zero, then continue
		mov	si, [di+_MidiTrackPos]	; grab MIDI delay offset from 0xB4 and copy to SI
		or	si, si
		jz	short DecreaseTick
		push	cx
		push	di
		dec	byte ptr [di+_XSlideDurCount] ; decrease pitch slide counter
		mov	ax, [di+_XSlideCounter]	; grab data at Pitch Slide Counter offset and copy to AX
		add	al, ah		; add AX's high byte (Pitch Slide Range) to AX's low byte (Pitch Slide Counter)
		mov	[di+_XSlideCounter], al	; write	the new	pitch slide count!
		mov	dx, di		; write	DI to DX
		sub	dx, _MidiEventDelay	; subtract 1A2 from DX
		shr	dx, 1		; shift	bits to	the right by 1
		mov	cl, [di+_MidiCurPitch]	; grab the data	at 0xEB	(MIDI Pitch byte) and write to CX's low byte
		and	cx, 7Fh		; perform AND with 7F and CX
		jz	short UpdatePtchTick	; if zero, jump	to finish decreasing the tick, otherwise continue.
		mov	ds:Terminator, 0FFh ; write FF at 0x1C2	(terminator)
		call	BendSetup	; go to
		mov	ds:Terminator, 0 ; zero	out terminator

UpdatePtchTick:
		pop	di
		pop	cx
		jmp	short DecreaseTick


; =============== S U B	R O U T	I N E =======================================


LoopCheck:
		cmp	ds:SongPlayCount, 0 ; compare the loop count with zero
		jnz	short NextLoop
		mov	ax, es:[bx+sLoopStart]	; add 2A to 2 to get 2C, so 3BB6:002C.	This is	our loop start measure!	 Throw that into AX
		cmp	ax, ds:MeasureCount ; compare the song's loop start measure with the current measure count
		jnz	short LoopCheckEnd ; jump to short if not equal

GrabLoopPtrs:				; compare the current MIDI tick	count with 60
		cmp	ds:MIDITickCount, MidiTickValue 
		jnz	short LoopCheckEnd ; if it's not 60h, skip this
		push	di
		push	es
		mov	si, di		; grab DI (1A2)	and put	it in SI
		add	di, _LoopMidiEventDelay  ; add D8 to 1A2 to get 27A (Loop MIDI Delay Values)
		push	ds
		pop	es
		mov	cx, AllTrackPtrs		; place	12 into	CX
		rep movsw		; write	all the	current	MIDI delay values into the Loop	MIDI Delay Value offsets!
		pop	es
		pop	di
		mov	ax, es:[bx+sLoopCount]	; grab loop count from music file!
		dec	ax		; decrease loop	count!
		mov	ds:SongPlayCount, ax ; write loop count	to memory!

LoopCheckEnd:
		retn

NextLoop:
		mov	ax, es:[bx+sLoopEnd]	; grab loop ending measure
		cmp	ax, ds:MeasureCount ; compare it with the current measure counter
		jnz	short LoopCheckEnd ; if they don't match, then exit
		dec	ds:SongPlayCount
		push	di
		push	es
		lea	si, [di+_LoopMidiEventDelay]
		push	ds
		pop	es
		mov	cx, AllTrackPtrs
		rep movsw
		pop	es
		pop	di
		mov	ax, es:[bx+sLoopStart]
		mov	ds:MeasureCount, ax


NextLoopEnd:
		retn

; ---------------------------------------------------------------------------
; START	OF FUNCTION CHUNK FOR WriteInstrument

GetDrumMap:
		mov	[di+_MidiDrumMapPtr], si	; write	drummap	instrument offset to 0xD8!
		retn
; END OF FUNCTION CHUNK	FOR WriteInstrument

; =============== S U B	R O U T	I N E =======================================


InstChange_C0:
		mov	word ptr [di+_MidiDrumMapPtr], 0 ; zeros out drum instrument offsets when instrument change	occurs
		call	GetChMidiDelay


; =============== S U B	R O U T	I N E =======================================


WriteInstrument:
		cmp	[di+_MidiCurInst], ah	; compare the high byte	of AX with 1EA
		jz	short NextLoopEnd ; jump	if zero
		mov	[di+_MidiCurInst], ah	; write	instrument number to memory!
		mov	al, InstSize	; '('   ; load 28 into low byte of AX
		mul	ah		; multiply high	byte of	AX, which is zero, so the answer is zero
		les	si, dword ptr ds:SongFileSize ;	load SongSize in SI
		add	si, ax		; add AX to SI
		mov	al, es:[si]	; grab low byte	at SongSegment:SongSize
		cmp	al, iDrumMode	; compare low byte if it's an FF (Drummap)
		jz	short GetDrumMap ; If it is, get drum map!
		mov	ax, es:[si+iX_SlideTrans] ; grab instrument's Pitch Slide Range Flag / Transpose bytes
		mov	[di+_XSlideRangeFlag], ax	; write	them to	memory!
		mov	ah, es:[si+iC_Level]	; grab the Carrier Output Level	and place it as	high byte in AX
		mov	al, es:[si+iM_Level]	; grab the Modulator Output Level and copy it as the low byte for AX
		mov	bh, es:[si+iM_KSL]	; grab the Modulator Key scaling level,	copy into high byte for	BX
		mov	bl, es:[si+iC_KSL]	; grab the Carrier Key scaling level, copy into	low byte for BX
		and	bx, 303h
		ror	bx, 1
		ror	bx, 1
		or	ax, bx
		mov	[di+_FMOutputLevel], ax	; write	Modulator Output Level (first byte) / Carrier Output Level (Second byte) into memory!
		mov	ax, es:[si+iX_MLevelScale] ; grab the Modulator and Carrier Output Level Scaling
		mov	[di+_FMOutputScaling], ax	; write	scaling	bytes to memory	at 0x132!
		mov	ah, es:[si+iFeedback]	; grab feedback	and place it in	high byte for AX
		mov	bl, es:[si+iPanning]	; grab panning byte, put it in low byte	for BX
		shl	bl, 1
		shl	bl, 1
		shl	bl, 1
		or	ah, bl		; grab new panning byte	and put	it in high byte	in AX
		mov	al, es:[si+iConnector]	; grab Connector and place it in low byte for AX
		not	al
		ror	al, 1
		shl	ax, 1
		mov	al, es:[si+iX_FBScaleVEL] ; grab Feedback	Scaling	- Velocity byte, place it in low byte for AX
		mov	[di+_FMFeedbackRegister], ax	; write	Panning/Feedback/Connector Register (first byte) / Feedback Scaling (second byte) at 0x168
		mov	ax, es:[si+iX_SlideDurRange]	; grab Pitch Slide Duration / Pitch Slide Range, throw into AX
		mov	[di+_XSlideRange], ah	; grab Pitch Slide Range and place it at 0x121
		mov	ah, al		; change Pitch Slide Duration byte
		xor	al, al		; zero out low byte
		mov	[di+_XSlideDurCount], ax	; write	Pitch Slide Duration at	0x10E
		push	ds
		mov	ax, es		; place	SongSegment in AX
		mov	ds, ax		; place	SongSegment in DS
		add	si, 2		; add 2	to SongSize
		call	LoadInstrument
		pop	ds
		retn

; =============== S U B	R O U T	I N E =======================================


NoteOn_90:
		lods	byte ptr es:[si] ; get MIDI Pitch
		call	GetChMidiDelay	; write	the MIDI delay and track position counts
		mov	si, [di+_MidiDrumMapPtr]	; get drummap instrument offset	at 0xD8
		or	si, si
		jz	short Transpose	; if there's no drummap, jump to 58B
		push	ax
		push	dx
		push	si
		push	di
		push	es
		mov	es, cs:SongSegment2 ; grab SongSegment and put it in ES
		mov	al, ah		; grab MIDI pitch and put it in	AX's low byte
		sub	al, es:[si+2]	; grab the 0x18	transpose byte from the	drum keymap instrument and subtract it from the	MIDI pitch at AX's low byte
		xor	ah, ah		; zero out the MIDI pitch at AX's high byte
		;sub	ax, 14h		; subtract 0x14	from AX's value
		;;;;;;;;;;;;;;;;;;;;;;
		db	2Dh
		dw	14h
		;;;;;;;;;;;;;;;;;;;;;
		add	si, ax		; add the value	from AX	into SI, which is the drum keymap instrument offset.  This will	take us	to the instrument number inside	the keymap array.
		mov	ah, es:[si]	; grab the instrument byte in the keymap array and place it in AX's high byte
		call	WriteInstrument
		pop	es
		pop	di
		pop	si
		pop	dx
		pop	ax

Transpose:
		mov	bh, [di+_XRootNoteTrans]	; grab transpose byte and place	in the high byte of BX
		mov	bl, bh		; copy transpose value to low byte of BX
		sub	bh, 31h	; '1'   ; subtract 31 from the transpose value
		cmp	bh, 60h	; '`'   ; compare the transpose value at BX's high byte to 60.  The result will change the CF flag.
		jnb	short WriteTranspose ; if transpose value is less than 60 (CF flag is 1), DON'T jump
		mov	ah, bh		; copy the subtracted transpose	byte to	replace	the MIDI byte at AX's high byte
		xor	bl, bl		; zero out the original	transpose value
		add	ah, 18h		; add 18 to the	subtracted transpose byte

WriteTranspose:
		add	ah, bl		; add BX's low byte to AX's high byte.  This should change the MIDI pitch to the new transposed pitch.
		push	ax		; place	AX's value in the stack
		call	sub_632
		cmp	byte ptr [di+_MidiCurPitch], 0 ; compare MIDI pitch with zero
		jle	short WriteMidiPitch ; jump if less or equal
		test	byte ptr [di+0FDh], 2
		jnz	short WriteMidiPitch
		xor	ax, ax
		call	NoteWrite

WriteMidiPitch:
		pop	ax		; place	MIDI pitch and velocity	back in	AX
		mov	al, ah		; copy pitch byte to AX's low byte
		xor	ah, ah		; zero out AX's high byte
		mov	[di+_MidiCurPitch], al	; write	the MIDI pitch!
		;sub	ax, 48h	        ; AX - 48 = value
		;;;;;;;;;;;;;;;;;;;;;;;;
		db	2Dh
		dw	48h
		;;;;;;;;;;;;;;;;;;;;;;;;
		mov	cl, [di+_XSlideDuration]	; take the Pitch Slide Duration	byte and place it in CX's low byte
		mov	[di+_XSlideDurCount], cl	; take the Pitch Slide Duration	value in CX and	place it at the	Pitch Slide Duration Counter offset
		mov	byte ptr [di+_XSlideCounter], SlideCenter ; '@' ; resets the pitch slide by writing 40 at 0x10E
		jmp	loc_95C		; jump to 95C


; =============== S U B	R O U T	I N E =======================================


NoteOff_80:
		call	GetChMidiDelay

loc_5D2:
		mov	bh, [di+_XRootNoteTrans]	; grab transpose byte and place	it in BX's high byte
		mov	bl, bh		; copy BX's high byte to BX's low byte
		sub	bh, 31h	; '1'   ; subtract 31 from BX's high byte
		cmp	bh, 60h	; '`'   ; compare the transpose value at BX's high byte to 60.  The result will change the CF flag.
		jnb	short loc_5E6	; if transpose value is	less than 60 (CF flag is 1), DON'T jump
		mov	ah, bh		; copy the subtracted transpose	byte to	replace	the MIDI byte at AX's high byte
		xor	bl, bl		; zero out the original	transpose value
		add	ah, 18h		; add 18 to the	subtracted transpose byte

loc_5E6:
		add	ah, bl		; add zero?  this doesn't do anything
		cmp	[di+_MidiCurPitch], ah	; compare the MIDI pitch byte with AX's high byte
		jnz	short NoteOffEnd ; if the bytes	are not	the same, jump
		or	byte ptr [di+_MidiCurPitch], 80h ; write the NoteOff to memory!
		jmp	KeyOffChan

NoteOffEnd:
		retn


; =============== S U B	R O U T	I N E =======================================


EndofTrack_FF:
		mov	word ptr [di], 0FFFFh ;	write FFFF at the Current Midi Delay Counter offset
		sub	word ptr [di+_MidiTrackPos], 2 ; subtract	2 from the MIDI	Track Position offset
		or	dx, dx		; [dx was zero here]
		jnz	short locret_61C
		dec	ds:ChangeSongFlag ; SongChange is decreased to zero
		jz	short ClearStop	; jump if zero
		jns	short loc_60D
		inc	ds:ChangeSongFlag

loc_60D:
		call	SongInitStart
		les	bx, dword ptr ds:SizeOffset
		mov	di, _MidiEventDelay
		call	LoopCheck
		dec	word ptr [di]

locret_61C:
		retn
; ---------------------------------------------------------------------------

ClearStop:
		mov	ax, 0FFFFh	; put FFFF in AX
		push	es
		push	ds
		pop	es
		mov	cx, TrackNum
		rep stosw		; write	FFFF in	ALL the	MIDI Track Position offsets!
		pop	es
		push	cs
		call	near ptr ShutUp
		retn


; =============== S U B	R O U T	I N E =======================================


Aftertouch_D0:
		call	GetChMidiDelay
		retn


; =============== S U B	R O U T	I N E =======================================


sub_632:
		mov	ah, al		; copy the velocity byte to AX's high byte
		mov	al, 80h	; '€'   ; place 80 in AX's low byte
		sub	al, ah		; subtract 80 from the velocity	byte
		mov	bx, [di+_FMOutputLevel]	; grab the output level	bytes at 0x144 and place them in BX
		mov	cx, [di+_FMOutputScaling]	; grab the output level	scaling	bytes at 0x132 and place them in CX.
		or	cl, cl
		jz	short loc_673	; jump if zero
		push	ax
		jns	short loc_64B
		neg	cl
		mov	al, ah		; change Pitch Slide Range

loc_64B:
		sub	cl, 4
		neg	cl
		shr	al, cl
		mov	ah, bl
		and	ah, 3Fh
		add	ah, al
		cmp	ah, 3Fh	; '?'

loc_65C:	
		jbe	short loc_660
		mov	ah, 3Fh	; '?'

loc_660:
		and	bl, 0C0h
		or	bl, ah
		mov	ah, bl
		mov	si, OPLPortTable
		add	si, dx
		lodsb
		add	al, 40h	; '@'
		call	ChipWrite
		pop	ax

loc_673:
		or	ch, ch
		jz	short loc_6A5	; jump if zero
		push	ax
		jns	short loc_67E
		neg	ch
		mov	al, ah

loc_67E:
		mov	cl, 4
		sub	cl, ch
		shr	al, cl
		mov	ah, bh
		and	ah, 3Fh
		add	ah, al
		cmp	ah, 3Fh	; '?'
		jbe	short loc_692
		mov	ah, 3Fh	; '?'

loc_692:
		and	bh, 0C0h
		or	bh, ah
		mov	ah, bh
		mov	si, FineBendTable
		add	si, dx
		lodsb
		add	al, 40h	; '@'
		call	ChipWrite
		pop	ax

loc_6A5:
		mov	[di+_FMOutputRegister], bx	; grab BX and place it at Output Level Register	value (0x156)
		mov	cx, [di+_FMFeedbackRegister]	; grab the Panning/Feedback/Connector Register Value (0x168) and place in CX
		or	cl, cl
		jnz	short loc_6B2	; jump if not zero (ZF = 0)
		retn
; ---------------------------------------------------------------------------

loc_6B2:
		jns	short loc_6B8
		neg	cl
		mov	al, ah

loc_6B8:
		sub	cl, 6
		neg	cl
		shr	al, cl
		mov	ah, ch
		and	ax, 0FFEh
		add	al, ah
		cmp	al, 0Fh
		jbe	short loc_6CE
		and	al, 0Fh
		or	al, 0Eh

loc_6CE:
		mov	ah, al
		and	ch, 30h
		or	ah, ch
		mov	al, dl
		add	al, 0C0h ; 'À'
		call	ChipWrite


locret_6DC:
		retn

; =============== S U B	R O U T	I N E =======================================


PitchBend_E0:
		mov	al, ah		; copy pitch bend byte from AX's high byte to low byte
		call	GetChMidiDelay


; =============== S U B	R O U T	I N E =======================================


BendSetup:
		mov	cl, [di+_MidiCurPitch]	; grab the data	at 0xEB	(MIDI Pitch byte) and write to CX's low byte
		or	cl, cl
		jle	short locret_6DC ; jump	if less	or equal to
		xor	ch, ch		; clear	CX's high byte
		mov	ah, ch		; copy zero to AX's high byte, this overwrites the Pitch Slide Range byte
		xchg	ax, cx		; switch cx with ax (CX	is now pitch slide count, AX is	now MIDI pitch)
		sub	al, 18h		; subtract 18 from MIDI	pitch
		mov	bl, 0Ch		; write	C to BX's low byte
		div	bl		; divide AX by BX's low byte
		xchg	ax, cx		; switch cx with ax (CX	is now MIDI pitch, AX is now pitch slide count)

loc_6F5:
		mov	bx, [di+10Eh]	; copy data at 0x1B0 (3B08:02B0) and place in BX (the data at this offset should be just zeros)
		or	bh, cs:Terminator ; grab terminator byte at 0x1C2 and perform OR with BX's high byte (BX now becomes FF00)
		cmp	byte ptr [di+_XSlideRangeFlag], 0 ; compare Pitch Slide Range Flag to zero
		jnz	short BendFlagOn ; if Pitch Slide Range	Flag is	zero, continue;	otherwise, jump
		;sub	ax, 40h		; subtract 40 from pitch slide count
		;;;;;;;;;;;;;;;;;;;;;;;;
		db	2Dh
		dw	40h
		;;;;;;;;;;;;;;;;;;;;;;;;
		jnb	short BendUp	; Jump short if	not below (jump	if the pitch bend goes up)
		neg	ax		; get the two's compliment from AX
		ror	ax, 1		; rotate bits to the right
		ror	ax, 1
		ror	ax, 1
		ror	ax, 1
		ror	ax, 1
		sub	ch, al		; subtract CX's high byte (modified MIDI pitch) with AX's low byte (modified pitch bend)
		jnb	short loc_722
		add	ch, 0Ch		; add C	to CX's high byte
		dec	cl		; decrease CX's low byte
		jns	short loc_722
		xor	cx, cx

loc_722:
		mov	al, ch		; copy CX's high byte to AX's low byte
		mov	bx, 183h	; place	183 into BX
		xlat			; grab byte from table 0x83 (DS:BX), using AX's low byte as a table index!
		mul	ah		; multiply AX's low byte and high byte together
		mov	al, ah		; copy AX's high byte to the low byte
		xchg	al, ch		; switch CX's high byte with AX's low byte

GetFreq:
		xor	ah, ah		; zero out AX's high byte
		add	ax, ax		; AX + AX (this	value is now our table index for our note's frequency!)
		mov	si, ax		; place	AX into	SI
		mov	ax, [si+FreqTable]	; look up freq table and grab correct note frequency!
		sub	al, ch		; subtract the low byte	of the frequency with the value	in CX's high byte
		sbb	ah, 0		; Adds 0 and the carry (CF) flag, and subtracts	the result from	AX's high byte. The result of the subtraction is stored in AX's high byte.
		jmp	NoteKeyOn
; ---------------------------------------------------------------------------

BendUp:
		inc	ax		; increase AX by 1
		ror	ax, 1		; rotate bits to the right, 5 times
		ror	ax, 1
		ror	ax, 1
		ror	ax, 1
		ror	ax, 1
		add	ch, al		; add the low byte of AX to the	high byte of CX
		cmp	ch, 0Ch		; compare C to the high	byte of	CX
		jb	short loc_757	; jump if below	C
		sub	ch, 0Ch
		inc	cl

loc_757:
		mov	al, ch		; copy CX's high byte to AX's low byte
		mov	bx, 184h	; place	184 in BX
		xlat			; using	AX's low byte as a table index, grab a byte starting from the table at 0x84 and place that byte as the low byte for AX.
		mul	ah		; multiply the high byte and low byte of AX
		mov	al, ah		; copy AX's high byte to AX's low byte
		jmp	short GetFrequency ; switch CX's high byte with AX's low byte
; ---------------------------------------------------------------------------

BendFlagOn:
		;sub	ax, 40h		; take the pitch slide counter value and subtract it by 40
		;;;;;;;;;;;;;;;;;;;;;;;;
		db	2Dh
		dw	40h
		;;;;;;;;;;;;;;;;;;;;;;;;
		jnb	short CoarseBendUp ; if	signed,	continue
		neg	ax		; two's compliment
		mov	bh, 5
		div	bh		; divide that value by 5
		sub	ch, al
		jnb	short GrabCoarseTable
		add	ch, 0Ch
		dec	cl
		jns	short GrabCoarseTable
		xor	cx, cx

GrabCoarseTable:
		mov	al, ah
		mov	bx, 190h
		cmp	ch, 6
		jb	short GrabFreqTable
		add	bx, 5

GrabFreqTable:
		xlat			; Using	the table at 0x90 (3B08:0190), use AX's low byte to index the table and place the value in AX
		xchg	al, ch
		xor	ah, ah
		add	ax, ax
		mov	si, ax
		mov	ax, [si+FreqTable]
		sub	al, ch
		sbb	ah, 0
		jmp	short NoteKeyOn
; ---------------------------------------------------------------------------

CoarseBendUp:
		mov	bh, 5
		div	bh
		add	ch, al
		cmp	ch, 0Ch
		jb	short loc_7AC
		sub	ch, 0Ch
		inc	cl

loc_7AC:
		mov	al, ah
		mov	bx, 190h
		cmp	ch, 6
		jb	short loc_7B9
		add	bx, 5

loc_7B9:
		xlat

GetFrequency:
		xchg	al, ch		; switch CX's high byte with AX's low byte
		xor	ah, ah		; zero out AX's high byte
		add	ax, ax		; add AX with AX
		mov	si, ax		; copy AX to SI
		mov	ax, [si+FreqTable]	; grab the value at 0x47 (Frequency Table) and copy to AX
		add	al, ch		; add CX's high byte to AX's low byte
		adc	ah, 0		; add with carry flag to AX's high byte

NoteKeyOn:
		shl	cl, 1		; shift	CX's low byte bits to the left, two times
		shl	cl, 1
		or	ah, cl		; perform OR on	CX's low byte and AX's high byte and write it to AX's high byte
		mov	si, dx		; copy DX to SI
		add	si, si		; add SI with itself
		mov	[si+FNumRegisters], ax	; write	new FNUM register value!
		cmp	byte ptr [di+_MidiCurPitch], 0 ; compare zero with 0xEB (MIDI pitch)

loc_7DD:
		jz	short loc_7E2	; jump if zero,	otherwise continue
		or	ah, 20h		; perform OR with 20 and AX's high byte

loc_7E2:
		jmp	NoteWrite


; =============== S U B	R O U T	I N E =======================================


GetChMidiDelay:
		push	ax
		xor	ax, ax		; zero out AX
		lods	byte ptr es:[si] ; grab	MIDI delay byte	at ES (SongSegment):[SI] (TrackPosition).   Increment SI by 1
		or	al, al
		jns	short UpdateTrackPos	; Jump if the delay byte not signed.  If the byte is 80	or above, we got more work to do.
		xor	cx, cx		; zero out CX

GrabMidiDelay:
		mov	ch, cl		; take the low byte of CX and copy it to the high byte of CX
		mov	cl, ah		; take the high	byte of	AX and copy it to the low byte of CX
		mov	ah, al		; take the low byte of AX and copy it to the high byte of AX
		lods	byte ptr es:[si] ; grab	MIDI delay byte	at ES (SongSegment):[SI] (TrackPosition) again.	  Increment SI by 1 again.  If the previous delay byte is larger than 7F, this is where	the second delay byte will go.
		or	al, al
		js	short GrabMidiDelay	; take the low byte of CX and copy it to the high byte of CX
		and	ax, 7F7Fh	; perform AND on AX with 7F7F.	 Each bit of the result	of the AND instruction is a 1 if both corresponding bits of the	operands are 1;	otherwise, it becomes a	0.
		and	cx, 7F7Fh	; perform AND on CX with 7F7F
		shl	cl, 1		; shift	logical	left 1 bit at low byte of CX, ZF flag changes
		shr	cx, 1		; shift	logical	right 1	bit for	CX
		shl	al, 1		; shift	logical	left 1 bit at low byte of AX, ZF flag changes
		shl	ax, 1		; shift	logical	left 1 bit at AX (basically slide everything to	the left, add a	zero at	the end	and disregard MS Bit)
		shr	cx, 1		; shift	logical	right 1	bit for	CX
		rcr	ax, 1		; RCR instruction shifts the CF	flag into the most-significant bit and shifts the least-significant bit	into the CF flag
		shr	cx, 1		; getting repetitive, ain't it?
		rcr	ax, 1		; THIS is your delay!!
		jcxz	short UpdateTrackPos	; Jump short if	CX register is 0
		mov	ax, 0FFFFh	; if no	track exists, put FFFF in AX

UpdateTrackPos:
		mov	[di], ax	; take your delay word and place it in memory!
		mov	[di+_MidiTrackPos], si	; update Current Track Position
		pop	ax		; pop AX to get	original value again
		retn


; =============== S U B	R O U T	I N E =======================================


KeyOffAll:
		push	ds
		push	cs
		pop	ds
		mov	cx, TrackNum	; place	9 in CX

KeyOffLoop:
		push	cx
		mov	dx, cx		; copy CX into DX
		dec	dx		; decrease DX
		call	KeyOffChan
		pop	cx
		loop	KeyOffLoop	; repeat until CX is depleted
		pop	ds
		retn


; =============== S U B	R O U T	I N E =======================================


sub_831:
		mov	al, ds:EEx19C	; copy EE byte at 0x9C into the	low byte of AX
		cmp	al, ds:EEx19D	; compare this byte with the byte at 0x9D
		jnz	short loc_846	; if not zero, jump to 846
		mov	ds:BitTimer, 1	; copy 1 to 0x9F
		and	ds:SongFlag, 0BFh ; check if SongFlag is above CO
		retn
; ---------------------------------------------------------------------------

loc_846:
		mov	ah, al
		mov	bl, ds:EEx19D
		mov	bh, bl
		and	al, 0Fh
		and	bl, 0Fh
		cmp	al, bl
		jz	short loc_85F
		inc	ah
		jb	short loc_85F
		dec	ah
		dec	ah

loc_85F:
		mov	al, ah
		and	ah, 0F0h
		and	bh, 0F0h
		cmp	ah, bh
		jz	short loc_873
		add	al, 10h
		cmp	ah, bh
		jb	short loc_873
		sub	al, 20h	; ' '

loc_873:
		mov	ds:EEx19C, al
		or	al, al
		jnz	short loc_88A
		push	dx
		push	si
		call	KeyOffAll
		pop	si
		pop	dx
		mov	ds:SongFlag, 0


; =============== S U B	R O U T	I N E =======================================


SoundBlaster:	
		mov	al, cs:EEx19C	; grab EE at 0x9C and place in low byte	at AX

loc_88A:
		mov	ah, 26h	        ; place 26 at high byte in AX.  Now we have 26EE
		push	dx
		mov	dx, word ptr cs:PortNum	; grab 0220 at 0x1C6, put it in	DX
		add	dl, 4		; make it 224
		xchg	al, ah		; exchange the low byte	with the high byte at AX. Now we have EE26
		out	dx, al		; send the low byte of AX (26) to I/O port 224
		inc	dx		; increment DX,	now it's 225
		xchg	al, ah		; exchange the low byte	with the high byte at AX. Now we have 26EE again.
		out	dx, al		; send the low byte of AX (EE) to I/O port 225
		pop	dx
		retn



; =============== S U B	R O U T	I N E =======================================


ClearSusRel:
		mov	si, OPLPortTable	; places 171 in	SI
		mov	cx, AllTrackPtrs	; places 12 in CX
		mov	ah, 0FFh	; places 0xFF at high byte in AX

ClearSusLoop:
		lodsb			; grabs	the byte at 0x71, which	is 00, and places it in	the low	byte of	AX, which gives	us FF00.  SI increments	to 172.
		add	al, 80h	; '€'   ; add 80, which gives us FF80.  The lookup table at 0x71 is for cycling through all the OPL registers and adding each byte, one at a time to 80, thus giving us OPL registers 80-95.
		call	ChipWrite	; writes FF at OPL register 80
		loop	ClearSusLoop		; do this 18 times, for	OPL registers 80-95.
		retn


; =============== S U B	R O U T	I N E =======================================


LoadInstrument:
		add	dx, dx
		mov	bx, dx
		mov	dx, cs:[bx+OPLRegTable] ; Table at 0x35
		shr	bx, 1
		call	LoadChanSlot
		xchg	dh, dl
		mov	ah, [si+1Bh]	; after	loading	the instrument,	get ready to grab stuff	from the next instrument
		add	si, 0Dh		; after	the first pass of grabbing the mod stuff, now get the carrier stuff
		jmp	short LoadSlotOnly


; =============== S U B	R O U T	I N E =======================================


LoadChanSlot:	
		mov	ah, [si+0Ch]	; grab connector byte
		shr	ax, 1
		mov	ah, [si+2]	; grab feedback
		not	al
		shl	ax, 1
		and	ah, 0Fh
		mov	al, 0C0h
		add	al, bl
		call	ChipWrite
		mov	ah, [si+1Ah]	; grab modulator waveform

LoadSlotOnly:
		and	ah, 3
		mov	al, 0E0h

loc_8E5:
		add	al, dl
		call	ChipWrite
		mov	ah, [si+8]	; Modulator Output Level
		mov	al, [si]	; Modulator Key	scaling	level
		shl	ah, 1
		shl	ah, 1
		ror	ax, 1
		ror	ax, 1
		mov	al, 40h	; '@'
		add	al, dl
		call	ChipWrite
		mov	ah, [si+3]	; Modulator Attack
		mov	al, [si+6]	; Modulator Delay
		shl	al, 1
		shl	al, 1
		shl	al, 1
		shl	al, 1
		shl	ax, 1
		shl	ax, 1
		shl	ax, 1
		shl	ax, 1
		mov	al, 60h	; '`'
		add	al, dl
		call	ChipWrite
		mov	ah, [si+4]	; Modulator Sustain
		mov	al, [si+7]	; Modulator Release
		shl	al, 1
		shl	al, 1
		shl	al, 1
		shl	al, 1
		shl	ax, 1
		shl	ax, 1
		shl	ax, 1
		shl	ax, 1
		mov	al, 80h	; '€'
		add	al, dl
		call	ChipWrite
		mov	al, [si+0Bh]	; Modulator Key	scaling/envelope rate
		ror	ax, 1
		mov	al, [si+5]	; Modulator Envelope gain
		ror	ax, 1
		mov	al, [si+0Ah]	; Modulator Frequency Vibrato
		ror	ax, 1
		mov	al, [si+9]	; Modulator Amplitude modulation (Tremolo)
		ror	ax, 1
		mov	al, [si+1]	; Modulator Frequency multiplier
		and	ax, 0F00Fh
		or	ah, al
		mov	al, 20h	; ' '
		add	al, dl
		call	ChipWrite
		retn

loc_95C:
		;add	ax, 30h	; '0'   ; take subtracted pitch value and add 30
		;cmp	ax, 60h	; '`'   ; compare 60 to AX (AX - 60)
		;;;;;;;;;;;;;;;;;;;;;;;;;;
		db	05
		dw	30h		; add	ax, 30h
		
		db	3Dh
		dw	60h		; cmp	ax, 60h
		;;;;;;;;;;;;;;;;;;;;;;;;;;
		jb	short KeyOnChan	; If AX	< 60 then jump (CF=1)
		xor	ax, ax		; zero out AX

KeyOnChan:
		mov	bl, 0Ch		; place	C in low byte of BX
		div	bl		; divide AX by BX's low byte
		mov	cl, al		; copy low byte	of AX into low byte of CX
		xchg	ah, al		; exchange low byte of AX with high byte of AX
		xor	ah, ah		; zero out high	byte of	AX
		add	ax, ax		; AX + AX
		mov	si, ax		; copy AX into SI
		mov	ax, [si+FreqTable]	; grab frequency number	from table and copy into AX
		shl	cl, 1		; shift	bit to the left	by 1 in	low byte of CX
		shl	cl, 1		; shift	bit to the left	by 1 in	low byte of CX
		or	ah, cl		; OR low byte of CX with high byte of AX
		mov	si, dx		; copy DX into SI
		add	si, si		; SI + SI
		mov	[si+FNumRegisters], ax	; write	the FNUM register value!!
		or	ah, 20h		; write	KEY-ON register	bit
		jmp	short NoteWrite

; =============== S U B	R O U T	I N E =======================================


KeyOffChan:
		mov	si, dx		; copy DX into SI
		add	si, si		; add SI + SI
		mov	ax, [si+FNumRegisters]	; grab FNUM register and copy to AX

NoteWrite:
		mov	cx, ax		; copy the register value into CX
		mov	al, dl		; then copy the	low byte of DX,	replacing the low byte of AX
		add	al, 0A0h ; ' '  ; add A0 to the low byte of AX (this is the write register for  FNUM (Lower 8 bits))
		mov	ah, cl		; copy the low byte of CX to the high byte of AX
		mov	si, ax		; copy AX to SI
		call	ChipWrite
		mov	ax, si		; copy SI to AX
		add	al, 10h		; add 10 to the	low byte of AX (A0 becomes BO, which is	the write register for KEY-ON, Block Number, FNUM (high	bits))


		mov	ah, ch		; copy the high	byte of	CX to the high byte of AX

; =============== S U B	R O U T	I N E =======================================



ChipWrite:
		push	dx
		mov	dx, 388h
		out	dx, al
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		inc	dx
		mov	al, ah
		out	dx, al
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		in	al, dx
		pop	dx
		retn