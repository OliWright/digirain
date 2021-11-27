; That 'digital rain' effect from the Matrix.  It's designed to look
; like it's on an old-school green screen monitor, with the trailing
; letters having an afterglow from a high persistence phosphor.
;
; But most modern implementations simulate the afterglow.  Have you
; ever wondered how it would look on an _actual_ green screen monitor
; like an IBM 5151?
;
; Well wonder no more!  Here's a short program that assembles into a
; small .com file that will run on an old PC.  Ideally something like
; a 5150 with a Monochrome Display Adapter connected to a 5151 monitor.
;
; This should 'run' on CGA too, but the trailing effect relies on a high
; persistence phosphor to work properly.

; To assemble using nasm:
;     nasm -f bin -o digirain.com digirain.asm
;
; I provide no warranty etc. for this code.  Feel free to use it
; as you see fit, but please credit me if you do.
;
;   - Oli Wright 2021
;
; oli.wright.github@gmail.com
; 


; We want to make sure we can run on an IBM PC 5150, so....
[CPU 8086]

NUM_SPRITES               EQU 128
SLOWEST_SPEED             EQU 0x0800 ; Speeds in 1:15 fixed-point format
FASTEST_SPEED             EQU 0x2000 ; characters per frame
SPEED_INCREASE_PER_SPRITE EQU (FASTEST_SPEED - SLOWEST_SPEED) / NUM_SPRITES

; Structure of sprite data
BYTES_PER_SPRITE          EQU 8
OFFS_HORIZONTAL_POS       EQU 0
OFFS_VERTICAL_POS         EQU 2
OFFS_ADDRESS              EQU 4
OFFS_CHARACTER            EQU 6

section .text
	; .com files always start 256 bytes into the segment
	org  0x100
	jmp  start

	; Yo!
	db   '>- oli.wright.github@gmail.com -<'

start:
	mov  ax,0x0002        ; 00: Set video mode, 02: 80 column text
	int  0x10

	; Read location 0040:0063 to test if we're on CGA or MDA
	mov  ax,0x0040
	mov  es,ax
	mov  ax,[es:0x0063]
	cmp  ax,0x3b4
	mov  bx,0xb000        ; Segment for MDA text mode
	je   skip_cga
	mov  bh,0xb8          ; Segment for CGA text mode
skip_cga:
	mov  es,bx            ; Video segment into ES

	; Disable the cursor
	mov  ah,0x01
	mov  ch,0x3f
	int  0x10

	; Initialise random number seed from the timer
	xor  ax,ax
	mov  di,ax
	int  0x1a             ; Int 1ah/ah=0 get timer ticks since midnight in CX:DX
	mov  [random_seed],dx ; Use lower 16 bits (in DX) for random value

	; Initialise all the sprite data
	mov  cx,NUM_SPRITES
	mov  di,sprites
	mov  bl,100
	xor  ax,ax
init_sprite_loop:
	; We deliberately leave some fields uninitialised to save code space.
	; Arrange things so that they'll be initialised during the first iteration
	;mov  [di + OFFS_HORIZONTAL_POS],ax   ; Leave uninitialised
	mov  [di + OFFS_VERTICAL_POS + 1],bl  ; Off screen
	mov  [di + OFFS_ADDRESS],ax
	mov  [di + OFFS_CHARACTER],cl
	add  di,BYTES_PER_SPRITE
	loop init_sprite_loop

frame_loop:
	; Check for ESC pressed
	mov  ah,0x0b
	int  0x21
	cmp  al,0
	je   start_frame      ; No STDIN waiting
	mov  ah,0x08
	int  0x21
	cmp  al,27
	jne  start_frame      ; Not ESC

	; Shutdown
	mov  ax,0x0002        ; 00: Set video mode, 02: 80 column text
	int  0x10
	mov  ah,0x4c
	int  0x21             ; Terminate

start_frame:
	xor  ax,ax
	mov  si,sprites
	mov  cx,NUM_SPRITES
	mov  dx,SLOWEST_SPEED

sprite_loop:
	; Erase the old sprite
	mov  di,[si + OFFS_ADDRESS]
	mov  al,' '
	mov  [es:di],al

	; Move sprite downward
	mov  ax,dx            ; Speed in 1:15 format
	push cx               ; Save cx sprite counter
	mov  cl,5
	shr  ax,cl            ; Convert speed to 6:10 format
	or   al,1             ; Make sure the lsbs constantly change
	add  ax,[si + OFFS_VERTICAL_POS]
	cmp  ah,100           ; Off the bottom of the screen?
	jl   skip_reset_sprite

	; Reset sprite
	push dx
	mov  ax,25173           ; LCG Multiplier
	mul  word [random_seed] ; dx:ax = LCG multiplier * seed
	add  ax,13849           ; Add LCG increment value
	; Modulo 65536, ax = (multiplier*seed+increment) mod 65536
	mov  [random_seed],ax   ; Update seed
	xor  dx,dx
	mov  cx,80
	div  cx               ; I should be able to use an 8-bit div here, but it crashes DosBox
	mov  ax,dx            ; Remainder of divide by 80
	shl  ax,1
	pop  dx
	mov  [si + OFFS_HORIZONTAL_POS],ax
	xor  ax,ax
skip_reset_sprite:
	mov  bh,[si + OFFS_VERTICAL_POS + 1] ; Load previous msbs of vertical pos
	mov  [si + OFFS_VERTICAL_POS],ax ; Store the new vertical position
	
	cmp  ah,bh
	je   skip_change_character

	; Change to a new random character
	mov  bh,al            ; Start with the LSBs of the vertical pos
	xor  bh,dl            ; Mix in the LSBs of the vertical speed
	and  bh,0x7f          ; Restrict to a more pleasing
	add  bh,0x21          ; character range
	mov  [si + OFFS_CHARACTER],bh
skip_change_character:

	; Calculate start of row
	mov  cl,10
	shr  ax,cl            ; Get integer part of vertical position
	mov  bl,160
	mul  bl
	; Add the horizontal position
	add  ax,[si + OFFS_HORIZONTAL_POS]
	; Save the final address of the sprite
	mov  di,ax
	mov  [si + OFFS_ADDRESS],ax

	; Write the character and attribute to video memory
	mov  al,[si + OFFS_CHARACTER]
	pop  cx;              ; Restore cx as sprite counter
	mov  ah,cl            ; Use the sprite counter to choose attributes
	and  ah,0x08          ; - Bright for half of them
	or   ah,0x07          ; - All are 'white'
	mov  [es:di],ax

	; Next sprite
	add  si,BYTES_PER_SPRITE
	add  dx,SPEED_INCREASE_PER_SPRITE
	loop sprite_loop

	jmp  frame_loop

section .bss

random_seed: resw 1
sprites:     resb NUM_SPRITES * BYTES_PER_SPRITE
