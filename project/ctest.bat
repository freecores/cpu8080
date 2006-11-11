rem ****************************************************************************
rem *                                                                          *
rem *                       Assemble the testbench file                        *
rem *                                                                          *
rem ****************************************************************************

rem
rem Assemble source
rem
as8080 test=test/l
rem
rem Create listing
rem
al test > test.lst
rem
rem Locate binary file to $0000
rem
ln testr=test
rem
rem Put into "rom" format suitable for verilog
rem
genrom testr.obj > test.rom
