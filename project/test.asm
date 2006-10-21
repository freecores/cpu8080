!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
! Code for the test bench. This gets dumped and placed into testbench.v as byte
! definitions.
!

!
! Select controller defines
! 
selmain: equ    $00             ! offset of main control register
sel1msk: equ    $02             ! offset of select 1 mask
sel1cmp: equ    $03             ! offset of select 1 compare
sel2msk: equ    $04             ! offset of select 1 mask
sel2cmp: equ    $05             ! offset of select 1 compare
sel3msk: equ    $06             ! offset of select 1 mask
sel3cmp: equ    $07             ! offset of select 1 compare
sel4msk: equ    $08             ! offset of select 1 mask
sel4cmp: equ    $09             ! offset of select 1 compare
!
! bits
!
selenb:	 equ	$01             ! enable select
selio:   equ	$02		        ! I/O address or memory

!
! Note: select 1 is ROM, 2, is RAM, 3 is interrupt controller
!

!
! Where to place ROM and RAM for this test
!
rombas:	equ		$0000
rambas:	equ		rombas+1024
!
! Interrupt controller defines
!
intbas:	equ		$10
intmsk:	equ		intbas+$00	    ! mask
intsts:	equ		intbas+$01	    ! status
intact:	equ		intbas+$02   	! active interrupt
intpol:	equ		intbas+$03		! polarity select
intedg: equ		intbas+$04		! edge/level select
intvec:	equ		intbas+$05		! vector base page	

!
! Set up selectors
!

!
! ROM
!
        mvi		a,rombas shr 8	! enable select 1 to 1kb at base
		out		sel1cmp
        mvi		a,($fc00 shr 8) or selenb
        out 	sel1msk
!
! RAM
!
        mvi 	a,rambas shr 8  ! enable select 2 to 1kb at base
        out 	sel2cmp
        mvi 	a,($fc00 shr 8) or selenb
        out 	sel2msk
!
! ROM and RAM set up, exit bootstrap mode
!
        mvi 	a,$00    		! exit bootstrap mode 
        out 	selmain
!
		lxi		sp,rambas+1024	! set stack to top of ram
!
! Interrupt controller
!
		mvi		a,intbas		! enable interrupt controller for 8 addresses		
		out		sel3cmp
		mvi		a,$f8 or selio or selenb
		out		sel3msk
!
! Set up interrupt controller for test
!
		mvi		a,$0100 shr 8	! vector to page 1
		out		intvec
		mvi		a,$01			! enable interrupt 0
		out		intact
!
! Interrupt here
!
		nop
		nop
		hlt						! and stop
!
! Locate to page 1
!
		alignp	256
		ret						! return from interrupt
