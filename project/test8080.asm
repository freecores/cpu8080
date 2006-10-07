        mvi a,$fd    ! enable select 1 to $0000, 1kb
        out $02      ! select 1 mask register
        mvi a,$04    ! enable select 2 to $0400, 1kb
        out $05      ! select 2 compare register
        mvi a,$fd
        out $04
        mvi a,$00    ! exit bootstrap mode 
        out $00
        lxi sp,$0800 ! place stack at top of ram
        lxi b,$1234  ! load test value
        push b       ! save on stack
        pop h        ! place in hl
