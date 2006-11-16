`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    12:02:03 10/22/2006 
// Design Name: 
// Module Name:    vgachr 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
// Simulation plugs exist in this code. Look for "????? SIMULATION PLUG"
//
// Debug plugs exist in this code. Look for "????? DEBUG PLUG"
//
//////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
//
// TERMINAL EMULATOR
//
// Emulates an ADM 3A dumb terminal, with a MITS serial I/O board interface.
// Two ports are emulated:
//
// 0: Control
// 1: Data
//
// The MITS serial card has all of its configuration performed by jumpers on the
// card, which means there is no programming configuration required. The data
// to the terminal is sent out of the data port, while the data from the 
// keyboard, which is not yet implemented, is read from the same data port.
// The parity is ignored on output, and set to 0 on input.
//
// The control register ignores all writes, and returns $80 if the terminal is
// busy, otherwise $00. This is the output ready to send bit. The busy bit
// reflects if the state machine is processing an operation. This is a cheat
// that only works with our emulated terminal/serial board pair, because 
// normally there is no way for the local CPU to know that the remote terminal
// is busy. This can lead to problems in the real world, and it's why Unix
// "termcap" terminal descriptions commonly have waiting periods perscribed
// time consuming operations like screen clear. This emulated terminal is
// "ideal" in that it accounts for all of this automatically, but it does not
// hurt the realisim of the emulation. An application that performs delays based
// on real terminal operations won't be incorrect because it performs a delay,
// but a stupid application that relies on this "smart" implementation might
// fail to run on the real thing.
//
// The ADM 3A terminal emulation is based on "ADM-3A Operators manual" of 1979,
// and "ADM 3A Dumb Terminal Users Reference Manual" of April, 1986, and the
// Unix termcap definition of the terminal.
//
// Several actions of terminals are typically not listed in the documentation,
// and the ADM 3A is no different. That's why termcap exists. The following
// actions were derived from the termcap definition:
//
// 1. The screen clear command also homes the cursor.
// 2. Giving the terminal a right cursor command while at the right side of the
// 3. Screen wraps the cursor around to the right, one line down. If the cursor
//    is at the 80th collumn of the 24th line, it will then scroll.
// 4. Down cursor (line feed) on the 24th line scrolls the screen.
//
// Note that rule (3) causes the terminal to be unable to ever write a character
// to the collumn 80 character of line 24, which is interesting if you are
// writing a full screen editor. The ADM 3A had a switch for this behavior, but
// the user could hardly be expected to open the side panel and flip this switch
// to be able to edit.
//
// The following actions are unknown:
//
// 1. A cursor left command given when the cursor is at the left side of the 
//    screen has unknown effect. According to termcap, it is not to go to the
//    end of the next line up. I have guessed here that it is to simply
//    refuse to move.
// 2. A cursor up command given when the cursor is at the top of the screen
//    has unknown effect. I have guessed here that is is to simply refuse to
//    move.
//
// These are terminal features there are no plans to implement:
//
// 1. ENQ or answerback mode. This appears to require operator setup, the manual
// does not specify any useful default value for the 32 byte answerback, 
// otherwise it might serve as sort of an early plug and play. If there is an
// application out there that uses this, I would put it in.
// 2. Bell (where would it go?).
// 3. Ctrl-N and Ctrl-O keyboard locking and extention port. I'm not sure 
// locking has a good use, nor is all that great an idea.
// 4. Any of the setup modes or features, as operated by the keyboard.
//
// Not implemented in this version:
//
// 1. Reduced intensity mode.
// 2. Graphics mode.
//
// The ADM 3A terminal will pretty much serve as an upward compatible version
// of the ASR-33 teletypes (Western Union Surplus) that were also commonly used
// in the time of the Altair. The ADM 3A was a common replacement for such
// units.
//
// Bugs/problems/issues:
//
// 1. The emulation was occasionally observed to hang. The CPU was still running
// and polling the keyboard, but no reply is received when keys are hit. The rdy
// signal is not coming from the low level keyboard logic.
// 2. Cursor left at left hand side does not refuse to move (see above).
// 3. moving to the 80th collum on line 24 and typing a character does not cause
// the screen to scroll.
// 4. On sign-on, the first two characters are missing the top row. I suspect
// this is due to the start of frame character preloading that is done.
// 5. \ESCGc or set attributes does not work from the keyboard unless you hit
// caps lock or hold the shift key down before and after the escape. It should
// work anytime the upper case G is hit.
//

//
// Terminal height and width
//
`define scnchrs 80 // width
`define scnlins 24 // height

//
// Terminal states
//
`define term_idle    5'h00 // idle
`define term_wrtstd2 5'h01 // write standard character #2
`define term_wrtstd3 5'h02 // write standard character #3
`define term_wrtstd4 5'h03 // write standard character #4
`define term_clear   5'h04 // clear screen and home cursor
`define term_clear2  5'h05 // clear screen and home cursor #2
`define term_clear3  5'h06 // clear screen and home cursor #3
`define term_clear4  5'h07 // clear screen and home cursor #4
`define term_fndstr  5'h08 // find start of current line
`define term_scroll  5'h09 // scroll screen
`define term_scroll1 5'h0a // scroll screen #1
`define term_scroll2 5'h0b // scroll screen #2
`define term_scroll3 5'h0c // scroll screen #3
`define term_scroll4 5'h0d // scroll screen #4
`define term_scroll5 5'h0e // scroll screen #5
`define term_scroll6 5'h0f // scroll screen #6
`define term_esc     5'h10 // escape
`define term_poscur  5'h11 // position cursor
`define term_poscur2 5'h12 // position cursor #2
`define term_attset  5'h13 // set screen attributes

//
// Terminal attribute bits
//
`define attr_blank   5'b00001 // blank
`define attr_blink   5'b00010 // blink
`define attr_reverse 5'b00100 // reverse
`define attr_under   5'b01000 // underline
`define attr_rinten  5'b10000 // reduced intensity

module terminal(addr, data, write, read, select, r, g, b, hsync_n, vsync_n,
                ps2_clk, ps2_data, reset, clock, diag);

   input        addr;     // control reg/data reg address
   inout [7:0]  data;     // CPU data
   input        write;    // CPU write
   input        read;     // CPU read
   input        select;   // controller select
   input        reset;    // CPU reset
   input        clock;    // CPU clock
   output [2:0] r, g, b;  // R,G,B color output buses
   output       hsync_n;  // horizontal sync pulse
   output       vsync_n;  // vertical sync pulse
   input        ps2_clk;  // clock from keyboard
   input        ps2_data; // data from keyboard
   output [7:0] diag;     // diagnostic 8 bit port

   // internal definitions
   reg [4:0]   state;   // terminal state machine
   reg [10:0]  cursor;  // cursor address
   reg [10:0]  tcursor; // cursor temp address
   reg [7:0]   chrdatw; // character write data
   reg         outrdy;  // output ready to send
   reg         wrtchr;  // character ready to write
   reg  [7:0]  datao;   // intermediate for data output
   reg  [7:0]  rowchr;  // row holding character
   reg  [4:0]  curatr;  // current attribute set

   // character map communication bus
   reg  [10:0] cmaddr;  // character map address to read or write
   reg         cmread;  // character map read from address
   reg         cmwrite; // character map write from address
   wire  [7:0] cmdata;  // character map data to be written/read
   wire  [4:0] cmattr;  // character map attributes to be written/read
   reg   [7:0] cmdatai; // character map data to be written
   reg         cmdatae; // character map data enable
   reg   [7:0] cmattri; // character map attribute to be written
   reg         cmattre; // character map attribute enable

   // keyboard communication
   wire   [7:0] scancode;   // key scancode
   wire         parity;     // keyboard parity
   wire         busy;       // busy scanning code
   wire         rdy;        // ready with code
   wire         error;      // scancode error
   reg          scnrdy;     // scancode 
   reg          extkey;     // is extended key
   reg          capslock;   // caps lock toggle
   reg          leftshift;  // state of left shift key
   reg          rightshift; // state of right shift key
   reg          leftctrl;   // state of left control key
   reg          rightctrl;  // state of right control key
   reg          relcod;     // release code active
   reg          extcod;     // extention code active
   wire   [7:0] asciidata;  // output of lookup rom
   wire   [7:0] asciidatau; // output of lookup rom
   reg          clrrdy;     // clear input ready

   // here we put signals out the diagnostic port if required.
   assign diag[0] = busy;
   assign diag[1] = rdy;
   assign diag[2] = scnrdy;
   assign diag[3] = ps2_clk;
   assign diag[4] = ps2_data;
   assign diag[5] = relcod;
   assign diag[6] = leftctrl;
   assign diag[7] = rightctrl;

   // instantiate memory mapped character display
   chrmemmap display(!reset, clock, r, g, b, hsync_n, vsync_n, cmaddr, cmread,
                     cmwrite, cmdata, cmattr, cursor);

   // instantiate ps/2 keyboard. Note that the keyboard decoder only generates
   // codes on release, which has to be changed, since we need both asserts and
   // deasserts.
   ps2_kbd vgai(.clk(clock), .rst(reset), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
                .scancode(scancode), .parity(parity), .busy(busy), .rdy(rdy),
                .error(error));

   // instantiate keyboard scan lookup roms
   scnrom kbdtbl(scancode, asciidata); // lower case
   scnromu kbdtblu(scancode, asciidatau); // lower case

   // process keyboard input state
   always @(posedge clock)
      if (reset) begin // perform reset actions
   
         leftshift <= 0; // clear left shift key state
         rightshift <= 0; // clear right shift key state
         leftctrl <= 0; // clear left control key state
         rightctrl <= 0; // clear right control key state
         capslock <= 0; // clear caps lock state
         relcod <= 0; // clear release status
         scnrdy <= 0; // clear key ready
         extkey <= 0; // is an extended key

   end else begin

      if (rdy) begin

          // if the release code $f0 occurs, set release until the next key occurs
          if (scancode == 8'hf0) relcod <= 1;
          // if the extention code $e0 occurs, set the extention flag
          else if (scancode == 8'he0) extcod <= 1;
          else if (relcod) begin // release

             relcod <= 0; // reset release code
             // reset any extention code
             if (scancode != 8'hf0 && scancode != 8'he0) extcod <= 0;
             // if caps lock is hit, toggle caps lock status
             if (scancode == 8'h58) capslock <= !capslock;
             // process left and right shift key up
             if (scancode == 8'h12) leftshift <= 0; // left up
             if (scancode == 8'h59) rightshift <= 0; // right up
             // process control key up
             if (scancode == 8'h14) begin

                if (extcod) rightctrl <= 0; // right up
                else leftctrl <= 0; // left up

             end

          end else begin // assert

             scnrdy <= 1; // set key is ready
             extkey <= extcod; // set extended status of key
             // reset any extention code
             if (scancode != 8'hf0 && scancode != 8'he0) extcod <= 0;
             // process left and right shift key down
             if (scancode == 8'h12) leftshift <= 1; // left down
             if (scancode == 8'h59) rightshift <= 1; // right down
             // process control key down
             if (scancode == 8'h14) begin

                if (extcod) rightctrl <= 1; // right down
                else leftctrl <= 1; // left down

             end

          end

      end else if (clrrdy) scnrdy <= 0; // clear key ready

   end

   // process terminal emulation
   always @(posedge clock)
      if (reset) begin // reset

         // on reset, we set the state machine to perform a screen clear and
         // home cursor
         // ????? SIMULATION PLUG
         // Don't clear screen, this takes too long in simulation
         state <= `term_clear; // set to clear screen
         // state <= `term_idle; // continue
         cursor <= 0; // set cursor to home
         outrdy <= 0; // set not ready to send
         wrtchr <= 0; // set no character to write
         cmread <= 0; // clear read character
         cmwrite <= 0; // clear write character
         cmdatae <= 0; // no enable character map data
         cmattre <= 0; // no enable character map attributes
         clrrdy <= 0; // set clear ready off
         curatr <= 5'b0; // set no attributes active
                      
   end else begin

      if (write&select) begin // CPU write

         if (addr) begin
      
            chrdatw <= data & 8'h7f; // set character write data without parity
            wrtchr <= 1; // character ready to write
            outrdy <= 0; // remove ready to send
      
         end
      
      end else if (read&select) begin // CPU read
      
         if (addr) begin
      
            // Return decoded keyboard, with shifting. The letter keys, 'a'-'z',
            // can be shifted by the shift keys, but not by caps lock state.
            // The other keys can be shifted by either. This matches PC 
            // behavior, which lets you have cap locks on without shifting the
            // letter keys. The control codes are shifted as a block from `($60)
            // to ~($7e) down to $00. This leaves out \US and \DEL, but these
            // codes get generated by the DEL key.
            if (extkey) begin // its an extended key

               if (scancode == 8'h75) datao <= 8'h0b; // up
               else if (scancode == 8'h6b) datao <= 8'h08; // left
               else if (scancode == 8'h72) datao <= 8'h0a; // down
               else if (scancode == 8'h74) datao <= 8'h0c; // right
               else if (scancode == 8'h6c) datao <= 8'h1e; // home
               else if (scancode == 8'h71) datao <= 8'h1f; // delete (rub out)
    
            end else if (asciidata >= 8'h60 && asciidata <= 8'h7e && 
                         (leftctrl || rightctrl))
               datao <= asciidata & 8'h1f;
            else if (asciidata >= 8'h61 && asciidata <= 8'h7a)
               datao <= leftshift||rightshift||capslock ? asciidatau: asciidata;
            else 
               datao <= leftshift||rightshift ? asciidatau: asciidata;
            clrrdy <= 1; // clear scancode ready f/f
      
         end else 
            datao <= (!outrdy << 7) | (scnrdy << 5); // return ready statuses
      
      end else clrrdy <= 0; // clear keyboard ready signal

      case (state) // run output state
      
         `term_idle: begin // idle waiting for character
      
            // We wait for the cpu cycle to end before running the state machine
            // write procedure. This allows this module to run at full speed, 
            // while the rest of the CPU logic runs slow. The vga logic must run
            // at a fixed speed because it has the display to run, but the rest
            // can be slow to allow debugging.
            if (wrtchr&!(select&read|select&write)) begin 

               // process character after CPU goes away
               if (chrdatw >= 8'h20 && chrdatw != 8'h7f) begin
      
                  // write standard (non-control) character
                  cmaddr <= cursor; // set address at cursor
                  cmdatai <= chrdatw; // place character data to write
                  cmattri <= curatr; // set with current attributes
                  cmdatae <= 1; // enable data to memory
                  cmattre <= 1; // enable attributes to memory
                  state <= `term_wrtstd2; // continue
      
               end else begin // control character
      
                  if (chrdatw == 8'h0a) begin // line down (line feed)
                  
                     if (cursor < 23*80) begin // not at screen end

                        cursor <= cursor+80;
                        wrtchr <= 0; // remove ready to write
                        outrdy <= 1; // set ready to send

                     end else begin

                        tcursor <= 0; // set temp cursor to screen start
                        state <= `term_scroll; // go to scroll screen

                      end
                  
                  end else if (chrdatw == 8'h0b) begin // line up
                  
                     if (cursor >= 80) cursor <= cursor-80;
                     wrtchr <= 0; // remove ready to write
                     outrdy <= 1; // set ready to send
                  
                  end else if (chrdatw == 8'h0d) begin // carriage return
                  
                     tcursor <= 0; // set start of line cursor
                     state <= `term_fndstr; // go to find start of line

                  end else if (chrdatw == 8'h08) begin // character left
                  
                     // if not at home position, back up
                     if (cursor > 0) cursor <= cursor-1;
                     wrtchr <= 0; // remove ready to write
                     outrdy <= 1; // set ready to send

                  end else if (chrdatw == 8'h0c) begin // character right
                  
                     // if not at screen end, go forward
                     if (cursor < 80*24-1) cursor <= cursor+1;
                     wrtchr <= 0; // remove ready to write
                     outrdy <= 1; // set ready to send

                  end else if (chrdatw == 8'h1e) begin // home
                  
                     cursor <= 0; // set to home position
                     wrtchr <= 0; // remove ready to write
                     outrdy <= 1; // set ready to send
                  
                  end else if (chrdatw == 8'h1a) begin // clear screen

                     state <= `term_clear; // go to screen clear
                     wrtchr <= 0; // remove ready to write
                     outrdy <= 1; // set ready to send

                  end else if (chrdatw == 8'h1b) begin // escape

                     wrtchr <= 0; // remove ready to write
                     outrdy <= 1; // set ready to send
                     state <= `term_esc; // go escape handler

                  end else begin // unsupported control character

                     wrtchr <= 0; // remove ready to write
                     outrdy <= 1; // set ready to send

                  end
      
               end
                  
            end
      
         end
      
         `term_wrtstd2: begin // write standard character #2
      
            cmwrite <= 1; // set write to memory
            state <= `term_wrtstd3; // continue
      
         end
      
         `term_wrtstd3: begin // write standard character #3
      
            cmwrite <= 0; // remove write to memory
            state <= `term_wrtstd4; // continue
           
         end

         `term_wrtstd4: begin // write standard character #3
      
            cmdatae <= 0; // release data enable to memory
            cmattre <= 0; // release attribute enable to memory
            outrdy <= 1; // set ready to send
            cursor <= cursor+1; // advance cursor
            wrtchr <= 0; // remove ready to write
            state <= `term_idle; // continue
           
         end
      
         `term_clear: begin // clear screen and home cursor
      
            cmaddr <= 0; // clear buffer address
            cmdatai <= 8'h20; // clear to spaces
            cmattri <= 5'b0; // clear attributes
            cmdatae <= 1; // enable data to memory
            cmattre <= 1; // enable attributes to memory
            state <= `term_clear2; // continue
       
         end
      
         `term_clear2: begin // clear screen and home cursor #2
      
            cmwrite <= 1; // set write to memory
            state <= `term_clear3; // continue
      
         end
      
         `term_clear3: begin // clear screen and home cursor #2
      
            cmwrite <= 0; // reset write to memory
            state <= `term_clear4; // continue
      
         end
      
         `term_clear4: begin // clear screen and home cursor #4
      
            if (cmaddr < `scnchrs*`scnlins) begin
      
               cmaddr <= cmaddr+1; // next character
               // Uncomment the next to put an incrementing pattern instead of
               // spaces.
               //cmdatai <= cmdatai+1;
               state <= `term_clear2; // continue
      
            end else begin // done
      
               outrdy <= 1; // set ready to send
               cursor <= 0; // set cursor to home position
               cmdatae <= 0; // release data enable to memory
               cmattre <= 0; // release attribute enable to memory
               state <= `term_idle; // continue
               
            end
      
         end

         `term_fndstr: begin // find start of current line

            if (tcursor+80 > cursor) begin // found

               cursor <= tcursor; // set cursor to line start
               wrtchr <= 0; // remove ready to write
               outrdy <= 1; // set ready to send
               state <= `term_idle; // continue

            end else tcursor <= tcursor+80; // advance to next line

         end

         `term_scroll: begin // scroll screen up

            // move all data up a line
            if (tcursor < 80*23) begin // scroll up

               cmread <= 1; // set read display
               cmaddr <= tcursor+80; // set address to read
               state <= `term_scroll1; // continue
               
            end else state <= `term_scroll5; // go blank last line

         end

         `term_scroll1: begin // scroll screen up #1

            state <= `term_scroll2; // hold read

         end

         `term_scroll2: begin // scroll screen up #2

            cmdatai <= cmdata; // get data at address
            cmattri <= cmattr; // get attribute at address
            cmread <= 0; // turn off read
            state <= `term_scroll3; // continue

         end

         `term_scroll3: begin // scroll screen up #3

            cmdatae <= 1; // enable data to write
            cmattre <= 1; // enable attribute to write
            cmwrite <= 1; // set to write
            cmaddr <= tcursor;
            state <= `term_scroll4; // continue

         end

         `term_scroll4: begin // scroll screen up #4

            cmwrite <= 0; // turn off write
            cmdatae <= 0; // turn off data enable
            cmattre <= 0; // turn off attribute enable
            tcursor <= tcursor+1; // next address
            state <= `term_scroll; // repeat character move

         end

         `term_scroll5: begin // scroll screen up #5

            // blank out last line
            if (tcursor < 80*24) begin // blank out

               cmdatai <= 8'h20; // set to write spaces
               cmattri <= 0; // set no attribute
               cmdatae <= 1; // enable data to write
               cmattre <= 1; // enable attribute to write
               cmwrite <= 1; // set to write
               cmaddr <= tcursor;
               state <= `term_scroll6; // continue

            end else begin // terminate

               wrtchr <= 0; // remove ready to write
               outrdy <= 1; // set ready to send
               state <= `term_idle; // continue

            end

         end

         `term_scroll6: begin // scroll screen up #6

            cmwrite <= 0; // turn off write
            cmdatae <= 0; // turn off data enable
            cmattre <= 0; // turn off attribute enable
            tcursor <= tcursor+1; // next address
            state <= `term_scroll5; // repeat blank out

         end

         `term_esc: begin // handle escape codes

            // wait for next character
            if (wrtchr&!(select&read|select&write)) begin

               // check its a cursor position, or "\esc="
               if (chrdatw == 8'h3d) begin

                  wrtchr <= 0; // remove ready to write
                  outrdy <= 1; // set ready to send
                  state <= `term_poscur;

               // check its a attribute set, or "\escG"
               end else if (chrdatw == 8'h47) begin

                  wrtchr <= 0; // remove ready to write
                  outrdy <= 1; // set ready to send
                  state <= `term_attset;

               end else begin // invalid sequence, abort

                  wrtchr <= 0; // remove ready to write
                  outrdy <= 1; // set ready to send
                  state <= `term_idle;

               end
    

            end

         end

         `term_poscur: begin // handle cursor direct position

            // wait for next character
            if (wrtchr&!(select&read|select&write)) begin

               rowchr <= chrdatw; // save row character
               wrtchr <= 0; // remove ready to write
               outrdy <= 1; // set ready to send
               state <= `term_poscur2;

            end

         end

         `term_poscur2: begin // handle cursor direct position #2

            // wait for next character
            if (wrtchr&!(select&read|select&write)) begin

               // check row and collumn are valid
               if (rowchr >= 8'h20 && rowchr <= 8'h37 && 
                   chrdatw >= 8'h20 && chrdatw <= 8'h6f)
                  // perform position
                  cursor <= (rowchr-8'h20)*80+(chrdatw-8'h20);
               wrtchr <= 0; // remove ready to write
               outrdy <= 1; // set ready to send
               state <= `term_idle;

            end

         end

         `term_attset: begin // handle attribute set

            // wait for next character
            if (wrtchr&!(select&read|select&write)) begin

               // Process attribute set code. The ADM 3A attributes are arranged
               // so that the bits in characters '0'-'N' correspond to attribute
               // bits. Some of the combinations are "invalid", but these are
               // ones that override each other. For example, blank overrides
               // all others.
               if (chrdatw >= 8'h30 && chrdatw <= 8'h4e) // its '0'-'N'
                  curatr <= chrdatw-8'h30 & 5'b11111;
               wrtchr <= 0; // remove ready to write
               outrdy <= 1; // set ready to send
               state <= `term_idle;

            end

         end
      
         default: state <= 6'bx;
      
      endcase

   end
      
   // Enable drive to character memory
   assign cmdata = cmdatae ? cmdatai: 8'bz;

   // Enable drive to character attributes
   assign cmattr = cmattre ? cmattri: 8'bz;

   // Enable drive for data output
   assign data = read&select ? datao: 8'bz;

endmodule

////////////////////////////////////////////////////////////////////////////////
//
// MEMORY MAPPED CHARACTER DISPLAY
//
// Contains the 20x8 characters used in a 640x480, 24 lines of 80 characters
// display. This display is accessed vi a 1920 character memory, which can be 
// written and read. It is dual port, so has no restrictions on read and write.
//
// This block can either be directly mapped to CPU main memory, or can be run
// via a terminal emulator.
//
// Note there wasn't a mode for 24 lines, or for 640x480 pixels for alpha mode
// on the PC. Instead, 640x480 was a standard VGA mode for graphics. I like it
// because it unifies graphics and alpha modes, and has even divisions to
// character cells. Its a bit difficult to fit characters into a 8x20 cell,
// but the modes used for alpha, like 640x400 or 640x300 are not 4:3 aspect
// ratios, and really work by stretching the pixels vertically. We just do
// the same thing by explicit mapping.
//

`define clkfreq   50000000              // input clock frequency
`define blinkfreq 1                     // blink cycle in seconds
`define blinkmax  (`clkfreq*`blinkfreq) // total blink cycle

module chrmemmap(rst_n, clk, r, g, b, hsync_n, vsync_n, addr, read, write, 
                 data, attr, cursor);

      input         rst_n;   // reset
      input         clk;     // master clock
      output [2:0]  r, g, b; // R,G,B color output buses
      output        hsync_n; // horizontal sync pulse
      output        vsync_n; // vertical sync pulse
      input  [10:0] addr;    // address to read or write
      input         read;    // read from address
      input         write;   // write from address
      inout  [7:0]  data;    // data to be written/read
      inout  [4:0]  attr;    // attributes to be written/read
      input [10:0]  cursor;  // cursor address

   reg [15:0] pixeldata; // 16 bit pixel feed

   reg  [6:0]  chrcnt;   // character counter
   reg  [4:0]  rowcnt;   // character row counter
   reg  [4:0]  lincnt;   // line counter
   reg  [10:0] scnadr;   // screen character buffer address
   reg  [7:0]  curchr;   // current character indexed by scnadr
   reg  [4:0]  curatr;   // current attribute indexed by scnadr
   reg  [1:0]  fchsta;   // character fetch state, 0 = load high, 1 = load low
   wire [10:0] chradr;   // character generator address
   wire [7:0]  chrdata;  // character generator data
   reg  [7:0]  datao;    // intermediate for data output
   reg  [4:0]  attro;    // intermediate for attribute output
   reg  [7:0]  pixdatl;  // pixel data low holding
   reg  [31:0] blinkcnt; // blink cycle counter
   reg         blon;     // blink on/off

   // storage for character based screen

   reg [7:0] scnbuf[1919:0]; // screen
   reg [4:0] atrbuf[1919:0]; // attributes

   assign rst = ~rst_n; // change reset polarity

   vga vgai(.rst(rst), .clk(clk), .pixel_data_in(pixeldata), .rd(rd), .eof(eof),
            .r(r), .g(g), .b(b), .hsync_n(hsync_n), .vsync_n(vsync_n), 
            .blank(blank));

   chrrom crom(chradr, chrdata); // place character generator

   // run the blink cycle counter
   always @(posedge clk)
      if (rst) begin

      blinkcnt <= 0; // clear blink cycle
      blon <= 0; // clear cursor blink on

   end else begin

      blinkcnt <= blinkcnt+1; // count blink cycle
      // check blink cycle maxed, recycle if so
      if (blinkcnt >= `blinkmax) begin

         blinkcnt <= 0; // clear blink count
         blon <= ~blon; // flip blink state

      end

   end

   // run the character to screen scan
   always @(posedge clk)
      if (rst) begin // if reset

      // ????? SIMULATION PLUG
      // starting the character counter at the end of the line allows the scan
      // to cross the area the CPU is filling, and is ok at hardware time.
      // chrcnt <= 7'h0; // clear counters
      chrcnt <= 80-20; // clear counters
      // ????? SIMULATION PLUG
      // Starting the row count at 1 allows pixels to appear on the simulation,
      // and produces only a single bad line in real hardware
      rowcnt <= 5'h0;
      // rowcnt <= 5'h1;
      lincnt <= 5'h0;
      scnadr <= 11'h0;
      fchsta <= 0;

   end else if (eof) begin // if end of frame

      chrcnt <= 7'h0; // clear counters
      rowcnt <= 5'h0;
      lincnt <= 5'h0;
      scnadr <= 11'h0;
      fchsta <= 1; // set to fetch first set of characters

   end else if (rd || fchsta) begin

      if (fchsta == 1 || fchsta == 3) begin

         // advance counters
         if (chrcnt < 79) chrcnt <= chrcnt+1; // next character count
         else begin // next row
      
            chrcnt <= 0; // reset character
            if (rowcnt < 19) rowcnt <= rowcnt+1; // next character row
            else begin // next line
      
               rowcnt <= 0; // reset row
               lincnt <= lincnt+1; // next line
               scnadr <= scnadr+80; // advance character fetch
      
            end
      
         end

      end

      // Choose high or low character, and next state. Note we have to flip the
      // characters left to right to be correct.
      case (fchsta)

         0: fchsta <= 1; // delay until rd cycle is over

         1: begin
   
            // Set low bits of pixel register, and reverse if cursor matches the
            // current position, or if reverse attribute is on. Turn it all off
            // if blank is on.
            if ((scnadr+chrcnt == cursor)^curatr[2])
               pixdatl <= ~(curatr[0]|(curatr[1]&blon)? 8'h00: // blink and blank
                             (curatr[3]&rowcnt == 14? 8'hff: // underline 
                              { chrdata[0], chrdata[1], chrdata[2], chrdata[3],
                                chrdata[4], chrdata[5], chrdata[6], chrdata[7] }));
            else 
               pixdatl <= curatr[0]|(curatr[1]&blon)? 8'h00: // blink and blank
                             (curatr[3]&rowcnt == 14? 8'hff: // underline 
                              { chrdata[0], chrdata[1], chrdata[2], chrdata[3],
                                chrdata[4], chrdata[5], chrdata[6], chrdata[7] });
            fchsta <= 2; // next state
   
         end

         2: fchsta <= 3; // delay a cycle for ROM read time

         3: begin
   
            // Set low bits of pixel register, and reverse if cursor matches the
            // current position, or if reverse attribute is on. Turn it all off
            // if blank is on.
            if ((scnadr+chrcnt == cursor)^curatr[2]) 
               pixeldata <= pixdatl |
                 (~(curatr[0]|(curatr[1]&blon)? 8'h00: // blink and blank
                    (curatr[3]&rowcnt == 14? 8'hff: // underline 
                     { chrdata[0], chrdata[1], chrdata[2], chrdata[3],
                       chrdata[4], chrdata[5], chrdata[6], chrdata[7] })) & 
                  8'hff) << 8;
            else 
               pixeldata <= pixdatl |
                 (curatr[0]|(curatr[1]&blon)? 8'h00: // blink and blank
                    (curatr[3]&rowcnt == 14? 8'hff: // underline 
                     { chrdata[0], chrdata[1], chrdata[2], chrdata[3],
                       chrdata[4], chrdata[5], chrdata[6], chrdata[7] })) << 8;
            fchsta <= 0; // back to start
            
         end
   
      endcase

   end

   // operate dual port screen character RAM
   always @(posedge clk) begin

      // set current indexed character without parity
      curchr <= scnbuf[scnadr+chrcnt] & 8'h7f;
      if (write) scnbuf[addr] <= data;
      datao <= scnbuf[addr];

   end

   // operate dual port screen attribute RAM
   always @(posedge clk) begin

      // set current indexed character without parity
      curatr <= atrbuf[scnadr+chrcnt];
      if (write) atrbuf[addr] <= attr;
      attro <= atrbuf[addr];

   end

   // create character address from character in buffer and current row
   assign chradr =
      (curchr < 8'h20 || curchr == 8'h7f) ? 11'h0: (curchr-8'h20)*20+rowcnt;

   // Enable drive for data output
   assign data = read ? datao: 8'bz;
   assign attr = read ? attro: 8'bz;

endmodule

////////////////////////////////////////////////////////////////////////////////
//
// CHARACTER ROM
//
// Contains the 20x8 characters used in a 640x480, 25 lines of 80 characters
// display.
//

module chrrom(addr, data);

   input  [10:0] addr;
   output [7:0]  data;

   reg [7:0]  data;

   always @(addr) case (addr)

      // Character set starting with space, and ending with '~'

      // The design of characters is such that they are embedded into an odd
      // number of pixels, 7x19, with one space pixel to the right and bottom
      // of each cell. The character layout works best on an odd cell width
      // and height, because this gives a clear center to the character.
      // Each characters baseline is marked. The baseline is where the capital
      // characters sit, and only the descenders go below this position.

      11'h000: data = 8'b00000000; // ' '
      11'h001: data = 8'b00000000;
      11'h002: data = 8'b00000000;
      11'h003: data = 8'b00000000;
      11'h004: data = 8'b00000000;
      11'h005: data = 8'b00000000;
      11'h006: data = 8'b00000000;
      11'h007: data = 8'b00000000;
      11'h008: data = 8'b00000000;
      11'h009: data = 8'b00000000;
      11'h00A: data = 8'b00000000;
      11'h00B: data = 8'b00000000;
      11'h00C: data = 8'b00000000; // B
      11'h00D: data = 8'b00000000;
      11'h00E: data = 8'b00000000;
      11'h00F: data = 8'b00000000;
      11'h010: data = 8'b00000000;
      11'h011: data = 8'b00000000;
      11'h012: data = 8'b00000000;
      11'h013: data = 8'b00000000;

      11'h014: data = 8'b00010000; // '!'
      11'h015: data = 8'b00010000;
      11'h016: data = 8'b00010000;
      11'h017: data = 8'b00010000;
      11'h018: data = 8'b00010000;
      11'h019: data = 8'b00010000;
      11'h01A: data = 8'b00010000;
      11'h01B: data = 8'b00010000;
      11'h01C: data = 8'b00010000;
      11'h01D: data = 8'b00010000;
      11'h01E: data = 8'b00000000;
      11'h01F: data = 8'b00010000;
      11'h020: data = 8'b00010000; // B
      11'h021: data = 8'b00000000;     
      11'h022: data = 8'b00000000;
      11'h023: data = 8'b00000000;  
      11'h024: data = 8'b00000000;
      11'h025: data = 8'b00000000;
      11'h026: data = 8'b00000000;
      11'h027: data = 8'b00000000;

      11'h028: data = 8'b00000000; // '"'
      11'h029: data = 8'b00101000;
      11'h02A: data = 8'b00101000;
      11'h02B: data = 8'b00000000;
      11'h02C: data = 8'b00000000;
      11'h02D: data = 8'b00000000;
      11'h02E: data = 8'b00000000;
      11'h02F: data = 8'b00000000;
      11'h030: data = 8'b00000000;
      11'h031: data = 8'b00000000;
      11'h032: data = 8'b00000000;
      11'h033: data = 8'b00000000;
      11'h034: data = 8'b00000000; // B
      11'h035: data = 8'b00000000;     
      11'h036: data = 8'b00000000;
      11'h037: data = 8'b00000000;
      11'h038: data = 8'b00000000;
      11'h039: data = 8'b00000000;
      11'h03A: data = 8'b00000000;
      11'h03B: data = 8'b00000000;

      11'h03C: data = 8'b01000100; // '#'
      11'h03D: data = 8'b01000100;
      11'h03E: data = 8'b01000100;
      11'h03F: data = 8'b01000100;
      11'h040: data = 8'b11111110;
      11'h041: data = 8'b01000100;
      11'h042: data = 8'b01000100;
      11'h043: data = 8'b01000100;
      11'h044: data = 8'b11111110;
      11'h045: data = 8'b01000100;
      11'h046: data = 8'b01000100;
      11'h047: data = 8'b01000100;
      11'h048: data = 8'b01000100; // B
      11'h049: data = 8'b00000000;     
      11'h04A: data = 8'b00000000;
      11'h04B: data = 8'b00000000;
      11'h04C: data = 8'b00000000;
      11'h04D: data = 8'b00000000;
      11'h04E: data = 8'b00000000;
      11'h04F: data = 8'b00000000;

      11'h050: data = 8'b00010000; // '$'
      11'h051: data = 8'b01111100;
      11'h052: data = 8'b10010010;
      11'h053: data = 8'b10010000;
      11'h054: data = 8'b10010000;
      11'h055: data = 8'b10010000;
      11'h056: data = 8'b01111100;
      11'h057: data = 8'b00010010;
      11'h058: data = 8'b00010010;
      11'h059: data = 8'b00010010;
      11'h05A: data = 8'b10010010;
      11'h05B: data = 8'b01111100;
      11'h05C: data = 8'b00010000; // B
      11'h05D: data = 8'b00000000;     
      11'h05E: data = 8'b00000000;
      11'h05F: data = 8'b00000000;
      11'h060: data = 8'b00000000;
      11'h061: data = 8'b00000000;
      11'h062: data = 8'b00000000;
      11'h063: data = 8'b00000000;

      11'h064: data = 8'b11100000; // '%'
      11'h065: data = 8'b10100010;
      11'h066: data = 8'b11100100;
      11'h067: data = 8'b00000100;
      11'h068: data = 8'b00001000;
      11'h069: data = 8'b00001000;
      11'h06A: data = 8'b00010000;
      11'h06B: data = 8'b00010000;
      11'h06C: data = 8'b00100000;
      11'h06D: data = 8'b00100000;
      11'h06E: data = 8'b01001110;
      11'h06F: data = 8'b01001010;
      11'h070: data = 8'b10001110; // B
      11'h071: data = 8'b00000000;     
      11'h072: data = 8'b00000000;
      11'h073: data = 8'b00000000;
      11'h074: data = 8'b00000000;
      11'h075: data = 8'b00000000;
      11'h076: data = 8'b00000000;
      11'h077: data = 8'b00000000;

      11'h078: data = 8'b00000000; // '&'
      11'h079: data = 8'b00000000;
      11'h07A: data = 8'b00110000;
      11'h07B: data = 8'b01001000;
      11'h07C: data = 8'b10001000;
      11'h07D: data = 8'b10010000;
      11'h07E: data = 8'b01100000;
      11'h07F: data = 8'b00100000;
      11'h080: data = 8'b01010000;
      11'h081: data = 8'b10001010;
      11'h082: data = 8'b10000100;
      11'h083: data = 8'b10001010;
      11'h084: data = 8'b01110000; // B
      11'h085: data = 8'b00000000;     
      11'h086: data = 8'b00000000;
      11'h087: data = 8'b00000000;
      11'h088: data = 8'b00000000;
      11'h089: data = 8'b00000000;
      11'h08A: data = 8'b00000000;
      11'h08B: data = 8'b00000000;

      11'h08C: data = 8'b00010000; // '''
      11'h08D: data = 8'b00010000;
      11'h08E: data = 8'b00000000;
      11'h08F: data = 8'b00000000;
      11'h090: data = 8'b00000000;
      11'h091: data = 8'b00000000;
      11'h092: data = 8'b00000000;
      11'h093: data = 8'b00000000;
      11'h094: data = 8'b00000000;
      11'h095: data = 8'b00000000;
      11'h096: data = 8'b00000000;
      11'h097: data = 8'b00000000;
      11'h098: data = 8'b00000000; // B
      11'h099: data = 8'b00000000;     
      11'h09A: data = 8'b00000000;
      11'h09B: data = 8'b00000000;
      11'h09C: data = 8'b00000000;
      11'h09D: data = 8'b00000000;
      11'h09E: data = 8'b00000000;
      11'h09F: data = 8'b00000000;

      11'h0A0: data = 8'b00000100; // '('
      11'h0A1: data = 8'b00001000;
      11'h0A2: data = 8'b00010000;
      11'h0A3: data = 8'b00100000;
      11'h0A4: data = 8'b00100000;
      11'h0A5: data = 8'b01000000;
      11'h0A6: data = 8'b01000000;  
      11'h0A7: data = 8'b01000000;
      11'h0A8: data = 8'b00100000;
      11'h0A9: data = 8'b00100000;
      11'h0AA: data = 8'b00010000;
      11'h0AB: data = 8'b00001000;
      11'h0AC: data = 8'b00000100; // B
      11'h0AD: data = 8'b00000000;     
      11'h0AE: data = 8'b00000000;
      11'h0AF: data = 8'b00000000;
      11'h0B0: data = 8'b00000000;
      11'h0B1: data = 8'b00000000;
      11'h0B2: data = 8'b00000000;
      11'h0B3: data = 8'b00000000;

      11'h0B4: data = 8'b01000000; // ')'
      11'h0B5: data = 8'b00100000;
      11'h0B6: data = 8'b00010000;
      11'h0B7: data = 8'b00001000;
      11'h0B8: data = 8'b00001000;
      11'h0B9: data = 8'b00000100;  
      11'h0BA: data = 8'b00000100;   
      11'h0BB: data = 8'b00000100;
      11'h0BC: data = 8'b00001000;
      11'h0BD: data = 8'b00001000;
      11'h0BE: data = 8'b00010000;
      11'h0BF: data = 8'b00100000;
      11'h0C0: data = 8'b01000000; // B
      11'h0C1: data = 8'b00000000;     
      11'h0C2: data = 8'b00000000;
      11'h0C3: data = 8'b00000000;
      11'h0C4: data = 8'b00000000;
      11'h0C5: data = 8'b00000000;
      11'h0C6: data = 8'b00000000;
      11'h0C7: data = 8'b00000000;

      11'h0C8: data = 8'b00000000; // '*'
      11'h0C9: data = 8'b00000000;
      11'h0CA: data = 8'b00000000;
      11'h0CB: data = 8'b00000000;
      11'h0CC: data = 8'b01000100;
      11'h0CD: data = 8'b00101000;
      11'h0CE: data = 8'b01111100;
      11'h0CF: data = 8'b00101000;
      11'h0D0: data = 8'b01000100;
      11'h0D1: data = 8'b00000000;
      11'h0D2: data = 8'b00000000;
      11'h0D3: data = 8'b00000000;
      11'h0D4: data = 8'b00000000; // B
      11'h0D5: data = 8'b00000000;     
      11'h0D6: data = 8'b00000000;
      11'h0D7: data = 8'b00000000;
      11'h0D8: data = 8'b00000000;
      11'h0D9: data = 8'b00000000;
      11'h0DA: data = 8'b00000000;
      11'h0DB: data = 8'b00000000;

      11'h0DC: data = 8'b00000000; // '+'
      11'h0DD: data = 8'b00000000;
      11'h0DE: data = 8'b00000000;
      11'h0DF: data = 8'b00010000;
      11'h0E0: data = 8'b00010000;
      11'h0E1: data = 8'b00010000;
      11'h0E2: data = 8'b11111110;
      11'h0E3: data = 8'b00010000;
      11'h0E4: data = 8'b00010000;
      11'h0E5: data = 8'b00010000;
      11'h0E6: data = 8'b00000000;
      11'h0E7: data = 8'b00000000;
      11'h0E8: data = 8'b00000000; // B
      11'h0E9: data = 8'b00000000;     
      11'h0EA: data = 8'b00000000;
      11'h0EB: data = 8'b00000000;
      11'h0EC: data = 8'b00000000;
      11'h0ED: data = 8'b00000000;
      11'h0EE: data = 8'b00000000;
      11'h0EF: data = 8'b00000000;

      11'h0F0: data = 8'b00000000; // ','
      11'h0F1: data = 8'b00000000;
      11'h0F2: data = 8'b00000000;
      11'h0F3: data = 8'b00000000;
      11'h0F4: data = 8'b00000000;
      11'h0F5: data = 8'b00000000;
      11'h0F6: data = 8'b00000000;
      11'h0F7: data = 8'b00000000;
      11'h0F8: data = 8'b00000000;
      11'h0F9: data = 8'b00000000;
      11'h0FA: data = 8'b00000000;
      11'h0FB: data = 8'b00000000;
      11'h0FC: data = 8'b00010000; // B
      11'h0FD: data = 8'b00010000;     
      11'h0FE: data = 8'b00100000;
      11'h0FF: data = 8'b00000000;
      11'h100: data = 8'b00000000;
      11'h101: data = 8'b00000000;
      11'h102: data = 8'b00000000;
      11'h103: data = 8'b00000000;

      11'h104: data = 8'b00000000; // '-'
      11'h105: data = 8'b00000000;
      11'h106: data = 8'b00000000;
      11'h107: data = 8'b00000000;
      11'h108: data = 8'b00000000;
      11'h109: data = 8'b00000000;
      11'h10A: data = 8'b01111100;
      11'h10B: data = 8'b00000000;
      11'h10C: data = 8'b00000000;
      11'h10D: data = 8'b00000000;
      11'h10E: data = 8'b00000000;
      11'h10F: data = 8'b00000000;
      11'h110: data = 8'b00000000; // B
      11'h111: data = 8'b00000000;     
      11'h112: data = 8'b00000000;
      11'h113: data = 8'b00000000;
      11'h114: data = 8'b00000000;
      11'h115: data = 8'b00000000;
      11'h116: data = 8'b00000000;
      11'h117: data = 8'b00000000;

      11'h118: data = 8'b00000000; // '.'
      11'h119: data = 8'b00000000;
      11'h11A: data = 8'b00000000;
      11'h11B: data = 8'b00000000;
      11'h11C: data = 8'b00000000;
      11'h11D: data = 8'b00000000;
      11'h11E: data = 8'b00000000;
      11'h11F: data = 8'b00000000;
      11'h120: data = 8'b00000000;
      11'h121: data = 8'b00000000;
      11'h122: data = 8'b00000000;
      11'h123: data = 8'b00000000;
      11'h124: data = 8'b00010000; // B
      11'h125: data = 8'b00000000;     
      11'h126: data = 8'b00000000;
      11'h127: data = 8'b00000000;
      11'h128: data = 8'b00000000;
      11'h129: data = 8'b00000000;
      11'h12A: data = 8'b00000000;
      11'h12B: data = 8'b00000000;

      11'h12C: data = 8'b00000000; // '/'
      11'h12D: data = 8'b00000010;
      11'h12E: data = 8'b00000100;
      11'h12F: data = 8'b00000100;
      11'h130: data = 8'b00001000;
      11'h131: data = 8'b00001000;
      11'h132: data = 8'b00010000;
      11'h133: data = 8'b00010000;
      11'h134: data = 8'b00100000;
      11'h135: data = 8'b00100000;
      11'h136: data = 8'b01000000;
      11'h137: data = 8'b01000000;
      11'h138: data = 8'b10000000; // B
      11'h139: data = 8'b00000000;     
      11'h13A: data = 8'b00000000;
      11'h13B: data = 8'b00000000;
      11'h13C: data = 8'b00000000;
      11'h13D: data = 8'b00000000;
      11'h13E: data = 8'b00000000;
      11'h13F: data = 8'b00000000;

      11'h140: data = 8'b01111100; // '0'
      11'h141: data = 8'b10000010;
      11'h142: data = 8'b10000110;
      11'h143: data = 8'b10001110;
      11'h144: data = 8'b10001010;
      11'h145: data = 8'b10011010;
      11'h146: data = 8'b10010010;
      11'h147: data = 8'b10110010;
      11'h148: data = 8'b10100010;
      11'h149: data = 8'b11100010;
      11'h14A: data = 8'b11000010;
      11'h14B: data = 8'b10000010;
      11'h14C: data = 8'b01111100; // B
      11'h14D: data = 8'b00000000;     
      11'h14E: data = 8'b00000000;
      11'h14F: data = 8'b00000000;
      11'h150: data = 8'b00000000;
      11'h151: data = 8'b00000000;
      11'h152: data = 8'b00000000;
      11'h153: data = 8'b00000000;

      11'h154: data = 8'b00010000; // '1'
      11'h155: data = 8'b00110000;
      11'h156: data = 8'b01010000;
      11'h157: data = 8'b00010000;
      11'h158: data = 8'b00010000;
      11'h159: data = 8'b00010000;
      11'h15A: data = 8'b00010000;
      11'h15B: data = 8'b00010000;
      11'h15C: data = 8'b00010000;
      11'h15D: data = 8'b00010000;
      11'h15E: data = 8'b00010000;
      11'h15F: data = 8'b00010000;
      11'h160: data = 8'b11111110; // B
      11'h161: data = 8'b00000000;     
      11'h162: data = 8'b00000000;
      11'h163: data = 8'b00000000;
      11'h164: data = 8'b00000000;
      11'h165: data = 8'b00000000;
      11'h166: data = 8'b00000000;
      11'h167: data = 8'b00000000;

      11'h168: data = 8'b01111100; // '2'
      11'h169: data = 8'b10000010;
      11'h16A: data = 8'b00000010;
      11'h16B: data = 8'b00000010;
      11'h16C: data = 8'b00000010;
      11'h16D: data = 8'b00000010;
      11'h16E: data = 8'b00000010;
      11'h16F: data = 8'b00000100;
      11'h170: data = 8'b00001000;
      11'h171: data = 8'b00010000;
      11'h172: data = 8'b00100000;
      11'h173: data = 8'b01000000;
      11'h174: data = 8'b11111110; // B
      11'h175: data = 8'b00000000;     
      11'h176: data = 8'b00000000;
      11'h177: data = 8'b00000000;
      11'h178: data = 8'b00000000;
      11'h179: data = 8'b00000000;
      11'h17A: data = 8'b00000000;
      11'h17B: data = 8'b00000000;

      11'h17C: data = 8'b01111100; // '3'
      11'h17D: data = 8'b10000010;
      11'h17E: data = 8'b00000010;
      11'h17F: data = 8'b00000010;
      11'h180: data = 8'b00000010;
      11'h181: data = 8'b00000010;
      11'h182: data = 8'b01111100;
      11'h183: data = 8'b00000010;
      11'h184: data = 8'b00000010;
      11'h185: data = 8'b00000010;
      11'h186: data = 8'b00000010;
      11'h187: data = 8'b10000010;
      11'h188: data = 8'b01111100; // B
      11'h189: data = 8'b00000000;     
      11'h18A: data = 8'b00000000;
      11'h18B: data = 8'b00000000;
      11'h18C: data = 8'b00000000;
      11'h18D: data = 8'b00000000;
      11'h18E: data = 8'b00000000;
      11'h18F: data = 8'b00000000;

      11'h190: data = 8'b10000010; // '4'
      11'h191: data = 8'b10000010;
      11'h192: data = 8'b10000010;
      11'h193: data = 8'b10000010;
      11'h194: data = 8'b10000010;
      11'h195: data = 8'b10000010;
      11'h196: data = 8'b11111110;
      11'h197: data = 8'b00000010;
      11'h198: data = 8'b00000010;
      11'h199: data = 8'b00000010;
      11'h19A: data = 8'b00000010;
      11'h19B: data = 8'b00000010;
      11'h19C: data = 8'b00000010; // B
      11'h19D: data = 8'b00000000;     
      11'h19E: data = 8'b00000000;
      11'h19F: data = 8'b00000000;
      11'h1A0: data = 8'b00000000;
      11'h1A1: data = 8'b00000000;
      11'h1A2: data = 8'b00000000;
      11'h1A3: data = 8'b00000000;

      11'h1A4: data = 8'b11111110; // '5'
      11'h1A5: data = 8'b10000000;
      11'h1A6: data = 8'b10000000;
      11'h1A7: data = 8'b10000000;
      11'h1A8: data = 8'b10000000;
      11'h1A9: data = 8'b10000000;
      11'h1AA: data = 8'b11111100;
      11'h1AB: data = 8'b00000010;
      11'h1AC: data = 8'b00000010;
      11'h1AD: data = 8'b00000010;
      11'h1AE: data = 8'b00000010;
      11'h1AF: data = 8'b10000010;
      11'h1B0: data = 8'b01111100; // B
      11'h1B1: data = 8'b00000000;     
      11'h1B2: data = 8'b00000000;
      11'h1B3: data = 8'b00000000;
      11'h1B4: data = 8'b00000000;
      11'h1B5: data = 8'b00000000;
      11'h1B6: data = 8'b00000000;
      11'h1B7: data = 8'b00000000;

      11'h1B8: data = 8'b01111100; // '6'
      11'h1B9: data = 8'b10000010;
      11'h1BA: data = 8'b10000000;
      11'h1BB: data = 8'b10000000;
      11'h1BC: data = 8'b10000000;
      11'h1BD: data = 8'b10000000;
      11'h1BE: data = 8'b01111100;
      11'h1BF: data = 8'b10000010;
      11'h1C0: data = 8'b10000010;
      11'h1C1: data = 8'b10000010;
      11'h1C2: data = 8'b10000010;
      11'h1C3: data = 8'b10000010;
      11'h1C4: data = 8'b01111110; // B
      11'h1C5: data = 8'b00000000;     
      11'h1C6: data = 8'b00000000;
      11'h1C7: data = 8'b00000000;
      11'h1C8: data = 8'b00000000;
      11'h1C9: data = 8'b00000000;
      11'h1CA: data = 8'b00000000;
      11'h1CB: data = 8'b00000000;

      11'h1CC: data = 8'b11111110; // '7'
      11'h1CD: data = 8'b00000110;
      11'h1CE: data = 8'b00000100;
      11'h1CF: data = 8'b00001000;
      11'h1D0: data = 8'b00001000;
      11'h1D1: data = 8'b00010000;
      11'h1D2: data = 8'b00010000;
      11'h1D3: data = 8'b00100000;
      11'h1D4: data = 8'b00100000;
      11'h1D5: data = 8'b01000000;
      11'h1D6: data = 8'b01000000;
      11'h1D7: data = 8'b10000000;
      11'h1D8: data = 8'b10000000; // B
      11'h1D9: data = 8'b00000000;     
      11'h1DA: data = 8'b00000000;
      11'h1DB: data = 8'b00000000;
      11'h1DC: data = 8'b00000000;
      11'h1DD: data = 8'b00000000;
      11'h1DE: data = 8'b00000000;
      11'h1DF: data = 8'b00000000;

      11'h1E0: data = 8'b01111100; // '8'
      11'h1E1: data = 8'b10000010;
      11'h1E2: data = 8'b10000010;
      11'h1E3: data = 8'b10000010;
      11'h1E4: data = 8'b10000010;
      11'h1E5: data = 8'b10000010;
      11'h1E6: data = 8'b01111100;
      11'h1E7: data = 8'b10000010;
      11'h1E8: data = 8'b10000010;
      11'h1E9: data = 8'b10000010;
      11'h1EA: data = 8'b10000010;
      11'h1EB: data = 8'b10000010;
      11'h1EC: data = 8'b01111100; // B
      11'h1ED: data = 8'b00000000;     
      11'h1EE: data = 8'b00000000;
      11'h1EF: data = 8'b00000000;
      11'h1F0: data = 8'b00000000;
      11'h1F1: data = 8'b00000000;
      11'h1F2: data = 8'b00000000;
      11'h1F3: data = 8'b00000000;

      11'h1F4: data = 8'b01111100; // '9'
      11'h1F5: data = 8'b10000010;
      11'h1F6: data = 8'b10000010;
      11'h1F7: data = 8'b10000010;
      11'h1F8: data = 8'b10000010;
      11'h1F9: data = 8'b10000010;
      11'h1FA: data = 8'b01111100;
      11'h1FB: data = 8'b00000010;
      11'h1FC: data = 8'b00000010;
      11'h1FD: data = 8'b00000010;
      11'h1FE: data = 8'b00000010;
      11'h1FF: data = 8'b10000010;
      11'h200: data = 8'b01111100; // B
      11'h201: data = 8'b00000000;     
      11'h202: data = 8'b00000000;
      11'h203: data = 8'b00000000;
      11'h204: data = 8'b00000000;
      11'h205: data = 8'b00000000;
      11'h206: data = 8'b00000000;
      11'h207: data = 8'b00000000;

      11'h208: data = 8'b00000000; // ':'
      11'h209: data = 8'b00000000;
      11'h20A: data = 8'b00000000;
      11'h20B: data = 8'b00000000;
      11'h20C: data = 8'b00010000;
      11'h20D: data = 8'b00000000;
      11'h20E: data = 8'b00000000;
      11'h20F: data = 8'b00000000;
      11'h210: data = 8'b00010000;
      11'h211: data = 8'b00000000;
      11'h212: data = 8'b00000000;
      11'h213: data = 8'b00000000;
      11'h214: data = 8'b00000000; // B
      11'h215: data = 8'b00000000;     
      11'h216: data = 8'b00000000;
      11'h217: data = 8'b00000000;
      11'h218: data = 8'b00000000;
      11'h219: data = 8'b00000000;
      11'h21A: data = 8'b00000000;
      11'h21B: data = 8'b00000000;

      11'h21C: data = 8'b00000000; // ';'
      11'h21D: data = 8'b00000000;
      11'h21E: data = 8'b00000000;
      11'h21F: data = 8'b00000000;
      11'h220: data = 8'b00000000;
      11'h221: data = 8'b00000000;
      11'h222: data = 8'b00000000;
      11'h223: data = 8'b00000000;
      11'h224: data = 8'b00000000;
      11'h225: data = 8'b00010000;
      11'h226: data = 8'b00000000;
      11'h227: data = 8'b00000000;
      11'h228: data = 8'b00010000; // B
      11'h229: data = 8'b00010000;     
      11'h22A: data = 8'b00100000;
      11'h22B: data = 8'b00000000;
      11'h22C: data = 8'b00000000;
      11'h22D: data = 8'b00000000;
      11'h22E: data = 8'b00000000;
      11'h22F: data = 8'b00000000;

      11'h230: data = 8'b00000010; // '<'
      11'h231: data = 8'b00000100;
      11'h232: data = 8'b00001000;
      11'h233: data = 8'b00010000;
      11'h234: data = 8'b00100000;
      11'h235: data = 8'b01000000;
      11'h236: data = 8'b10000000;
      11'h237: data = 8'b01000000;
      11'h238: data = 8'b00100000;
      11'h239: data = 8'b00010000;
      11'h23A: data = 8'b00001000;
      11'h23B: data = 8'b00000100;
      11'h23C: data = 8'b00000010; // B
      11'h23D: data = 8'b00000000;     
      11'h23E: data = 8'b00000000;
      11'h23F: data = 8'b00000000;
      11'h240: data = 8'b00000000;
      11'h241: data = 8'b00000000;
      11'h242: data = 8'b00000000;
      11'h243: data = 8'b00000000;

      11'h244: data = 8'b00000000; // '='
      11'h245: data = 8'b00000000;
      11'h246: data = 8'b00000000;
      11'h247: data = 8'b00000000;
      11'h248: data = 8'b00000000;
      11'h249: data = 8'b01111100;
      11'h24A: data = 8'b00000000;
      11'h24B: data = 8'b01111100;
      11'h24C: data = 8'b00000000;
      11'h24D: data = 8'b00000000;
      11'h24E: data = 8'b00000000;
      11'h24F: data = 8'b00000000;
      11'h250: data = 8'b00000000; // B
      11'h251: data = 8'b00000000;     
      11'h252: data = 8'b00000000;
      11'h253: data = 8'b00000000;
      11'h254: data = 8'b00000000;
      11'h255: data = 8'b00000000;
      11'h256: data = 8'b00000000;
      11'h257: data = 8'b00000000;

      11'h258: data = 8'b10000000; // '>'
      11'h259: data = 8'b01000000;
      11'h25A: data = 8'b00100000;
      11'h25B: data = 8'b00010000;
      11'h25C: data = 8'b00001000;
      11'h25D: data = 8'b00000100;
      11'h25E: data = 8'b00000010;
      11'h25F: data = 8'b00000100;
      11'h260: data = 8'b00001000;
      11'h261: data = 8'b00010000;
      11'h262: data = 8'b00100000;
      11'h263: data = 8'b01000000;
      11'h264: data = 8'b10000000; // B
      11'h265: data = 8'b00000000;     
      11'h266: data = 8'b00000000;
      11'h267: data = 8'b00000000;
      11'h268: data = 8'b00000000;
      11'h269: data = 8'b00000000;
      11'h26A: data = 8'b00000000;
      11'h26B: data = 8'b00000000;

      11'h26C: data = 8'b01111100; // '?'
      11'h26D: data = 8'b10000010;
      11'h26E: data = 8'b00000010;
      11'h26F: data = 8'b00000010;
      11'h270: data = 8'b00000010;
      11'h271: data = 8'b00000010;
      11'h272: data = 8'b00011100;
      11'h273: data = 8'b00010000;
      11'h274: data = 8'b00010000;
      11'h275: data = 8'b00010000;
      11'h276: data = 8'b00010000;
      11'h277: data = 8'b00000000;
      11'h278: data = 8'b00010000; // B
      11'h279: data = 8'b00000000;     
      11'h27A: data = 8'b00000000;
      11'h27B: data = 8'b00000000;
      11'h27C: data = 8'b00000000;
      11'h27D: data = 8'b00000000;
      11'h27E: data = 8'b00000000;
      11'h27F: data = 8'b00000000;

      11'h280: data = 8'b01111100; // '@'
      11'h281: data = 8'b10000010;
      11'h282: data = 8'b10000010;
      11'h283: data = 8'b10000010;
      11'h284: data = 8'b10011110;
      11'h285: data = 8'b10010010;
      11'h286: data = 8'b10010010;
      11'h287: data = 8'b10011110;
      11'h288: data = 8'b10000000;
      11'h289: data = 8'b10000000;
      11'h28A: data = 8'b10000000;
      11'h28B: data = 8'b10000000;
      11'h28C: data = 8'b01111110; // B
      11'h28D: data = 8'b00000000;     
      11'h28E: data = 8'b00000000;
      11'h28F: data = 8'b00000000;
      11'h290: data = 8'b00000000;
      11'h291: data = 8'b00000000;
      11'h292: data = 8'b00000000;
      11'h293: data = 8'b00000000;

      11'h294: data = 8'b01111100; // 'A'
      11'h295: data = 8'b10000010;
      11'h296: data = 8'b10000010;
      11'h297: data = 8'b10000010;
      11'h298: data = 8'b10000010;
      11'h299: data = 8'b10000010;
      11'h29A: data = 8'b11111110;
      11'h29B: data = 8'b10000010;
      11'h29C: data = 8'b10000010;
      11'h29D: data = 8'b10000010;
      11'h29E: data = 8'b10000010;
      11'h29F: data = 8'b10000010;
      11'h2A0: data = 8'b10000010; // B
      11'h2A1: data = 8'b00000000;     
      11'h2A2: data = 8'b00000000;
      11'h2A3: data = 8'b00000000;
      11'h2A4: data = 8'b00000000;
      11'h2A5: data = 8'b00000000;
      11'h2A6: data = 8'b00000000;
      11'h2A7: data = 8'b00000000;

      11'h2A8: data = 8'b11111100; // 'B'
      11'h2A9: data = 8'b10000010;
      11'h2AA: data = 8'b10000010;
      11'h2AB: data = 8'b10000010;
      11'h2AC: data = 8'b10000010;
      11'h2AD: data = 8'b10000010;
      11'h2AE: data = 8'b11111100;
      11'h2AF: data = 8'b10000010;
      11'h2B0: data = 8'b10000010;
      11'h2B1: data = 8'b10000010;
      11'h2B2: data = 8'b10000010;
      11'h2B3: data = 8'b10000010;
      11'h2B4: data = 8'b11111100; // B
      11'h2B5: data = 8'b00000000;     
      11'h2B6: data = 8'b00000000;
      11'h2B7: data = 8'b00000000;
      11'h2B8: data = 8'b00000000;
      11'h2B9: data = 8'b00000000;
      11'h2BA: data = 8'b00000000;
      11'h2BB: data = 8'b00000000;

      11'h2BC: data = 8'b01111100; // 'C'
      11'h2BD: data = 8'b10000010;
      11'h2BE: data = 8'b10000000;
      11'h2BF: data = 8'b10000000;
      11'h2C0: data = 8'b10000000;
      11'h2C1: data = 8'b10000000;
      11'h2C2: data = 8'b10000000;
      11'h2C3: data = 8'b10000000;
      11'h2C4: data = 8'b10000000;
      11'h2C5: data = 8'b10000000;
      11'h2C6: data = 8'b10000000;
      11'h2C7: data = 8'b10000010;
      11'h2C8: data = 8'b01111100; // B
      11'h2C9: data = 8'b00000000;     
      11'h2CA: data = 8'b00000000;
      11'h2CB: data = 8'b00000000;
      11'h2CC: data = 8'b00000000;
      11'h2CD: data = 8'b00000000;
      11'h2CE: data = 8'b00000000;
      11'h2CF: data = 8'b00000000;

      11'h2D0: data = 8'b11111100; // 'D'
      11'h2D1: data = 8'b10000010;
      11'h2D2: data = 8'b10000010;
      11'h2D3: data = 8'b10000010;
      11'h2D4: data = 8'b10000010;
      11'h2D5: data = 8'b10000010;
      11'h2D6: data = 8'b10000010;
      11'h2D7: data = 8'b10000010;
      11'h2D8: data = 8'b10000010;
      11'h2D9: data = 8'b10000010;
      11'h2DA: data = 8'b10000010;
      11'h2DB: data = 8'b10000010;
      11'h2DC: data = 8'b11111100; // B
      11'h2DD: data = 8'b00000000;     
      11'h2DE: data = 8'b00000000;
      11'h2DF: data = 8'b00000000;
      11'h2E0: data = 8'b00000000;
      11'h2E1: data = 8'b00000000;
      11'h2E2: data = 8'b00000000;
      11'h2E3: data = 8'b00000000;

      11'h2E4: data = 8'b11111110; // 'E'
      11'h2E5: data = 8'b10000000;
      11'h2E6: data = 8'b10000000;
      11'h2E7: data = 8'b10000000;
      11'h2E8: data = 8'b10000000;
      11'h2E9: data = 8'b10000000;
      11'h2EA: data = 8'b11111000;
      11'h2EB: data = 8'b10000000;
      11'h2EC: data = 8'b10000000;
      11'h2ED: data = 8'b10000000;
      11'h2EE: data = 8'b10000000;
      11'h2EF: data = 8'b10000000;
      11'h2F0: data = 8'b11111110; // B
      11'h2F1: data = 8'b00000000;     
      11'h2F2: data = 8'b00000000;
      11'h2F3: data = 8'b00000000;
      11'h2F4: data = 8'b00000000;
      11'h2F5: data = 8'b00000000;
      11'h2F6: data = 8'b00000000;
      11'h2F7: data = 8'b00000000;

      11'h2F8: data = 8'b11111110; // 'F'
      11'h2F9: data = 8'b10000000;
      11'h2FA: data = 8'b10000000;
      11'h2FB: data = 8'b10000000;
      11'h2FC: data = 8'b10000000;
      11'h2FD: data = 8'b10000000;
      11'h2FE: data = 8'b11111000;
      11'h2FF: data = 8'b10000000;
      11'h300: data = 8'b10000000;
      11'h301: data = 8'b10000000;
      11'h302: data = 8'b10000000;
      11'h303: data = 8'b10000000;
      11'h304: data = 8'b10000000; // B
      11'h305: data = 8'b00000000;     
      11'h306: data = 8'b00000000;
      11'h307: data = 8'b00000000;
      11'h308: data = 8'b00000000;
      11'h309: data = 8'b00000000;
      11'h30A: data = 8'b00000000;
      11'h30B: data = 8'b00000000;

      11'h30C: data = 8'b01111100; // 'G'
      11'h30D: data = 8'b10000010;
      11'h30E: data = 8'b10000000;
      11'h30F: data = 8'b10000000;
      11'h310: data = 8'b10000000;
      11'h311: data = 8'b10000000;
      11'h312: data = 8'b10011100;
      11'h313: data = 8'b10000010;
      11'h314: data = 8'b10000010;
      11'h315: data = 8'b10000010;
      11'h316: data = 8'b10000010;
      11'h317: data = 8'b10000010;
      11'h318: data = 8'b01111100; // B
      11'h319: data = 8'b00000000;     
      11'h31A: data = 8'b00000000;
      11'h31B: data = 8'b00000000;
      11'h31C: data = 8'b00000000;
      11'h31D: data = 8'b00000000;
      11'h31E: data = 8'b00000000;
      11'h31F: data = 8'b00000000;

      11'h320: data = 8'b10000010; // 'H'
      11'h321: data = 8'b10000010;
      11'h322: data = 8'b10000010;
      11'h323: data = 8'b10000010;
      11'h324: data = 8'b10000010;
      11'h325: data = 8'b10000010;
      11'h326: data = 8'b11111110;
      11'h327: data = 8'b10000010;
      11'h328: data = 8'b10000010;
      11'h329: data = 8'b10000010;
      11'h32A: data = 8'b10000010;
      11'h32B: data = 8'b10000010;
      11'h32C: data = 8'b10000010; // B
      11'h32D: data = 8'b00000000;     
      11'h32E: data = 8'b00000000;
      11'h32F: data = 8'b00000000;
      11'h330: data = 8'b00000000;
      11'h331: data = 8'b00000000;
      11'h332: data = 8'b00000000;
      11'h333: data = 8'b00000000;

      11'h334: data = 8'b11111110; // 'I'
      11'h335: data = 8'b00010000;
      11'h336: data = 8'b00010000;
      11'h337: data = 8'b00010000;
      11'h338: data = 8'b00010000;
      11'h339: data = 8'b00010000;
      11'h33A: data = 8'b00010000;
      11'h33B: data = 8'b00010000;
      11'h33C: data = 8'b00010000;
      11'h33D: data = 8'b00010000;
      11'h33E: data = 8'b00010000;
      11'h33F: data = 8'b00010000;
      11'h340: data = 8'b11111110; // B
      11'h341: data = 8'b00000000;     
      11'h342: data = 8'b00000000;
      11'h343: data = 8'b00000000;
      11'h344: data = 8'b00000000;
      11'h345: data = 8'b00000000;
      11'h346: data = 8'b00000000;
      11'h347: data = 8'b00000000;

      11'h348: data = 8'b00000010; // 'J'
      11'h349: data = 8'b00000010;
      11'h34A: data = 8'b00000010;
      11'h34B: data = 8'b00000010;
      11'h34C: data = 8'b00000010;
      11'h34D: data = 8'b00000010;
      11'h34E: data = 8'b00000010;
      11'h34F: data = 8'b00000010;
      11'h350: data = 8'b00000010;
      11'h351: data = 8'b00000010;
      11'h352: data = 8'b00000010;
      11'h353: data = 8'b10000010;
      11'h354: data = 8'b01111100; // B
      11'h355: data = 8'b00000000;     
      11'h356: data = 8'b00000000;
      11'h357: data = 8'b00000000;
      11'h358: data = 8'b00000000;
      11'h359: data = 8'b00000000;
      11'h35A: data = 8'b00000000;
      11'h35B: data = 8'b00000000;

      11'h35C: data = 8'b10000010; // 'K'
      11'h35D: data = 8'b10000100;
      11'h35E: data = 8'b10001000;
      11'h35F: data = 8'b10010000;
      11'h360: data = 8'b10100000;
      11'h361: data = 8'b11000000;
      11'h362: data = 8'b10000000;
      11'h363: data = 8'b11000000;
      11'h364: data = 8'b10100000;
      11'h365: data = 8'b10010000;
      11'h366: data = 8'b10001000;
      11'h367: data = 8'b10000100;
      11'h368: data = 8'b10000010; // B
      11'h369: data = 8'b00000000;     
      11'h36A: data = 8'b00000000;
      11'h36B: data = 8'b00000000;
      11'h36C: data = 8'b00000000;
      11'h36D: data = 8'b00000000;
      11'h36E: data = 8'b00000000;
      11'h36F: data = 8'b00000000;

      11'h370: data = 8'b10000000; // 'L'
      11'h371: data = 8'b10000000;
      11'h372: data = 8'b10000000;
      11'h373: data = 8'b10000000;
      11'h374: data = 8'b10000000;
      11'h375: data = 8'b10000000;
      11'h376: data = 8'b10000000;
      11'h377: data = 8'b10000000;
      11'h378: data = 8'b10000000;
      11'h379: data = 8'b10000000;
      11'h37A: data = 8'b10000000;
      11'h37B: data = 8'b10000000;
      11'h37C: data = 8'b11111110; // B
      11'h37D: data = 8'b00000000;     
      11'h37E: data = 8'b00000000;
      11'h37F: data = 8'b00000000;
      11'h380: data = 8'b00000000;
      11'h381: data = 8'b00000000;
      11'h382: data = 8'b00000000;
      11'h383: data = 8'b00000000;

      11'h384: data = 8'b10000010; // 'M'
      11'h385: data = 8'b11000110;
      11'h386: data = 8'b10101010;
      11'h387: data = 8'b10010010;
      11'h388: data = 8'b10000010;
      11'h389: data = 8'b10000010;
      11'h38A: data = 8'b10000010;
      11'h38B: data = 8'b10000010;
      11'h38C: data = 8'b10000010;
      11'h38D: data = 8'b10000010;
      11'h38E: data = 8'b10000010;
      11'h38F: data = 8'b10000010;
      11'h390: data = 8'b10000010; // B
      11'h391: data = 8'b00000000;     
      11'h392: data = 8'b00000000;
      11'h393: data = 8'b00000000;
      11'h394: data = 8'b00000000;
      11'h395: data = 8'b00000000;
      11'h396: data = 8'b00000000;
      11'h397: data = 8'b00000000;

      11'h398: data = 8'b10000010; // 'N'
      11'h399: data = 8'b11000010;
      11'h39A: data = 8'b10100010;
      11'h39B: data = 8'b10010010;
      11'h39C: data = 8'b10001010;
      11'h39D: data = 8'b10000110;
      11'h39E: data = 8'b10000010;
      11'h39F: data = 8'b10000010;
      11'h3A0: data = 8'b10000010;
      11'h3A1: data = 8'b10000010;
      11'h3A2: data = 8'b10000010;
      11'h3A3: data = 8'b10000010;
      11'h3A4: data = 8'b10000010; // B
      11'h3A5: data = 8'b00000000;     
      11'h3A6: data = 8'b00000000;
      11'h3A7: data = 8'b00000000;
      11'h3A8: data = 8'b00000000;
      11'h3A9: data = 8'b00000000;
      11'h3AA: data = 8'b00000000;
      11'h3AB: data = 8'b00000000;

      11'h3AC: data = 8'b01111100; // 'O'
      11'h3AD: data = 8'b10000010;
      11'h3AE: data = 8'b10000010;
      11'h3AF: data = 8'b10000010;
      11'h3B0: data = 8'b10000010;
      11'h3B1: data = 8'b10000010;
      11'h3B2: data = 8'b10000010;
      11'h3B3: data = 8'b10000010;
      11'h3B4: data = 8'b10000010;
      11'h3B5: data = 8'b10000010;
      11'h3B6: data = 8'b10000010;
      11'h3B7: data = 8'b10000010;
      11'h3B8: data = 8'b01111100; // B
      11'h3B9: data = 8'b00000000;     
      11'h3BA: data = 8'b00000000;
      11'h3BB: data = 8'b00000000;
      11'h3BC: data = 8'b00000000;
      11'h3BD: data = 8'b00000000;
      11'h3BE: data = 8'b00000000;
      11'h3BF: data = 8'b00000000;

      11'h3C0: data = 8'b11111100; // 'P'
      11'h3C1: data = 8'b10000010;
      11'h3C2: data = 8'b10000010;
      11'h3C3: data = 8'b10000010;
      11'h3C4: data = 8'b10000010;
      11'h3C5: data = 8'b10000010;
      11'h3C6: data = 8'b11111100;
      11'h3C7: data = 8'b10000000;
      11'h3C8: data = 8'b10000000;
      11'h3C9: data = 8'b10000000;
      11'h3CA: data = 8'b10000000;
      11'h3CB: data = 8'b10000000;
      11'h3CC: data = 8'b10000000; // B
      11'h3CD: data = 8'b00000000;     
      11'h3CE: data = 8'b00000000;
      11'h3CF: data = 8'b00000000;
      11'h3D0: data = 8'b00000000;
      11'h3D1: data = 8'b00000000;
      11'h3D2: data = 8'b00000000;
      11'h3D3: data = 8'b00000000;

      11'h3D4: data = 8'b01111100; // 'Q'
      11'h3D5: data = 8'b10000010;
      11'h3D6: data = 8'b10000010;
      11'h3D7: data = 8'b10000010;
      11'h3D8: data = 8'b10000010;
      11'h3D9: data = 8'b10000010;
      11'h3DA: data = 8'b10000010;
      11'h3DB: data = 8'b10000010;
      11'h3DC: data = 8'b10000010;
      11'h3DD: data = 8'b10000010;
      11'h3DE: data = 8'b10001010;
      11'h3DF: data = 8'b10000110;
      11'h3E0: data = 8'b01111110; // B
      11'h3E1: data = 8'b00000000;     
      11'h3E2: data = 8'b00000000;
      11'h3E3: data = 8'b00000000;
      11'h3E4: data = 8'b00000000;
      11'h3E5: data = 8'b00000000;
      11'h3E6: data = 8'b00000000;
      11'h3E7: data = 8'b00000000;

      11'h3E8: data = 8'b11111100; // 'R'
      11'h3E9: data = 8'b10000010;
      11'h3EA: data = 8'b10000010;
      11'h3EB: data = 8'b10000010;
      11'h3EC: data = 8'b10000010;
      11'h3ED: data = 8'b10000010;
      11'h3EE: data = 8'b11111100;
      11'h3EF: data = 8'b11000000;
      11'h3F0: data = 8'b10100000;
      11'h3F1: data = 8'b10010000;
      11'h3F2: data = 8'b10001000;
      11'h3F3: data = 8'b10000100;
      11'h3F4: data = 8'b10000010; // B
      11'h3F5: data = 8'b00000000;     
      11'h3F6: data = 8'b00000000;
      11'h3F7: data = 8'b00000000;
      11'h3F8: data = 8'b00000000;
      11'h3F9: data = 8'b00000000;
      11'h3FA: data = 8'b00000000;
      11'h3FB: data = 8'b00000000;

      11'h3FC: data = 8'b01111100; // 'S'
      11'h3FD: data = 8'b10000010;
      11'h3FE: data = 8'b10000000;
      11'h3FF: data = 8'b10000000;
      11'h400: data = 8'b10000000;
      11'h401: data = 8'b10000000;
      11'h402: data = 8'b01111100;
      11'h403: data = 8'b00000010;
      11'h404: data = 8'b00000010;
      11'h405: data = 8'b00000010;
      11'h406: data = 8'b00000010;
      11'h407: data = 8'b10000010;
      11'h408: data = 8'b01111100; // B
      11'h409: data = 8'b00000000;     
      11'h40A: data = 8'b00000000;
      11'h40B: data = 8'b00000000;
      11'h40C: data = 8'b00000000;
      11'h40D: data = 8'b00000000;
      11'h40E: data = 8'b00000000;
      11'h40F: data = 8'b00000000;

      11'h410: data = 8'b11111110; // 'T'
      11'h411: data = 8'b00010000;
      11'h412: data = 8'b00010000;
      11'h413: data = 8'b00010000;
      11'h414: data = 8'b00010000;
      11'h415: data = 8'b00010000;
      11'h416: data = 8'b00010000;
      11'h417: data = 8'b00010000;
      11'h418: data = 8'b00010000;
      11'h419: data = 8'b00010000;
      11'h41A: data = 8'b00010000;
      11'h41B: data = 8'b00010000;
      11'h41C: data = 8'b00010000; // B
      11'h41D: data = 8'b00000000;     
      11'h41E: data = 8'b00000000;
      11'h41F: data = 8'b00000000;
      11'h420: data = 8'b00000000;
      11'h421: data = 8'b00000000;
      11'h422: data = 8'b00000000;
      11'h423: data = 8'b00000000;

      11'h424: data = 8'b10000010; // 'U'
      11'h425: data = 8'b10000010;
      11'h426: data = 8'b10000010;
      11'h427: data = 8'b10000010;
      11'h428: data = 8'b10000010;
      11'h429: data = 8'b10000010;
      11'h42A: data = 8'b10000010;
      11'h42B: data = 8'b10000010;
      11'h42C: data = 8'b10000010;
      11'h42D: data = 8'b10000010;
      11'h42E: data = 8'b10000010;
      11'h42F: data = 8'b10000010;
      11'h430: data = 8'b01111100; // B
      11'h431: data = 8'b00000000;     
      11'h432: data = 8'b00000000;
      11'h433: data = 8'b00000000;
      11'h434: data = 8'b00000000;
      11'h435: data = 8'b00000000;
      11'h436: data = 8'b00000000;
      11'h437: data = 8'b00000000;

      11'h438: data = 8'b10000010; // 'V'
      11'h439: data = 8'b10000010;
      11'h43A: data = 8'b10000010;
      11'h43B: data = 8'b10000010;
      11'h43C: data = 8'b10000010;
      11'h43D: data = 8'b10000010;
      11'h43E: data = 8'b10000010;
      11'h43F: data = 8'b10000010;
      11'h440: data = 8'b10000010;
      11'h441: data = 8'b10000010;
      11'h442: data = 8'b01000100;
      11'h443: data = 8'b00101000;
      11'h444: data = 8'b00010000; // B
      11'h445: data = 8'b00000000;     
      11'h446: data = 8'b00000000;
      11'h447: data = 8'b00000000;
      11'h448: data = 8'b00000000;
      11'h449: data = 8'b00000000;
      11'h44A: data = 8'b00000000;
      11'h44B: data = 8'b00000000;

      11'h44C: data = 8'b10000010; // 'W'
      11'h44D: data = 8'b10000010;
      11'h44E: data = 8'b10000010;
      11'h44F: data = 8'b10000010;
      11'h450: data = 8'b10000010;
      11'h451: data = 8'b10000010;
      11'h452: data = 8'b10000010;
      11'h453: data = 8'b10000010;
      11'h454: data = 8'b10000010;
      11'h455: data = 8'b10010010;
      11'h456: data = 8'b10101010;
      11'h457: data = 8'b11000110;
      11'h458: data = 8'b10000010; // B
      11'h459: data = 8'b00000000;     
      11'h45A: data = 8'b00000000;
      11'h45B: data = 8'b00000000;
      11'h45C: data = 8'b00000000;
      11'h45D: data = 8'b00000000;
      11'h45E: data = 8'b00000000;
      11'h45F: data = 8'b00000000;

      11'h460: data = 8'b10000010; // 'X'
      11'h461: data = 8'b10000010;
      11'h462: data = 8'b10000010;
      11'h463: data = 8'b10000010;
      11'h464: data = 8'b01000100;
      11'h465: data = 8'b00101000;
      11'h466: data = 8'b00010000;
      11'h467: data = 8'b00101000;
      11'h468: data = 8'b01000100;
      11'h469: data = 8'b10000010;
      11'h46A: data = 8'b10000010;
      11'h46B: data = 8'b10000010;
      11'h46C: data = 8'b10000010; // B
      11'h46D: data = 8'b00000000;
      11'h46E: data = 8'b00000000;
      11'h46F: data = 8'b00000000;
      11'h470: data = 8'b00000000;
      11'h471: data = 8'b00000000;
      11'h472: data = 8'b00000000;
      11'h473: data = 8'b00000000;

      11'h474: data = 8'b10000010; // 'Y'
      11'h475: data = 8'b10000010;
      11'h476: data = 8'b10000010;
      11'h477: data = 8'b10000010;
      11'h478: data = 8'b01000100;
      11'h479: data = 8'b00101000;
      11'h47A: data = 8'b00010000;
      11'h47B: data = 8'b00010000;
      11'h47C: data = 8'b00010000;
      11'h47D: data = 8'b00010000;
      11'h47E: data = 8'b00010000;
      11'h47F: data = 8'b00010000;
      11'h480: data = 8'b00010000; // B
      11'h481: data = 8'b00000000;
      11'h482: data = 8'b00000000;
      11'h483: data = 8'b00000000;
      11'h484: data = 8'b00000000;
      11'h485: data = 8'b00000000;
      11'h486: data = 8'b00000000;
      11'h487: data = 8'b00000000;

      11'h488: data = 8'b11111110; // 'Z'
      11'h489: data = 8'b00000010;
      11'h48A: data = 8'b00000010;
      11'h48B: data = 8'b00000010;
      11'h48C: data = 8'b00000100;
      11'h48D: data = 8'b00001000;
      11'h48E: data = 8'b00010000;
      11'h48F: data = 8'b00100000;
      11'h490: data = 8'b01000000;
      11'h491: data = 8'b10000000;
      11'h492: data = 8'b10000000;
      11'h493: data = 8'b10000000;
      11'h494: data = 8'b11111110; // B
      11'h495: data = 8'b00000000;
      11'h496: data = 8'b00000000;
      11'h497: data = 8'b00000000;
      11'h498: data = 8'b00000000;
      11'h499: data = 8'b00000000;
      11'h49A: data = 8'b00000000;
      11'h49B: data = 8'b00000000;

      11'h49C: data = 8'b00111000; // '['
      11'h49D: data = 8'b00100000;
      11'h49E: data = 8'b00100000;
      11'h49F: data = 8'b00100000;
      11'h4A0: data = 8'b00100000;
      11'h4A1: data = 8'b00100000;
      11'h4A2: data = 8'b00100000;
      11'h4A3: data = 8'b00100000;
      11'h4A4: data = 8'b00100000;
      11'h4A5: data = 8'b00100000;
      11'h4A6: data = 8'b00100000;
      11'h4A7: data = 8'b00100000;
      11'h4A8: data = 8'b00111000; // B
      11'h4A9: data = 8'b00000000;
      11'h4AA: data = 8'b00000000;
      11'h4AB: data = 8'b00000000;
      11'h4AC: data = 8'b00000000;
      11'h4AD: data = 8'b00000000;
      11'h4AE: data = 8'b00000000;
      11'h4AF: data = 8'b00000000;

      11'h4B0: data = 8'b00000000; // '\'
      11'h4B1: data = 8'b10000000;
      11'h4B2: data = 8'b01000000;
      11'h4B3: data = 8'b01000000;
      11'h4B4: data = 8'b00100000;
      11'h4B5: data = 8'b00100000;
      11'h4B6: data = 8'b00010000;
      11'h4B7: data = 8'b00010000;
      11'h4B8: data = 8'b00001000;
      11'h4B9: data = 8'b00001000;
      11'h4BA: data = 8'b00000100;
      11'h4BB: data = 8'b00000100;
      11'h4BC: data = 8'b00000010; // B
      11'h4BD: data = 8'b00000000;
      11'h4BE: data = 8'b00000000;
      11'h4BF: data = 8'b00000000;
      11'h4C0: data = 8'b00000000;
      11'h4C1: data = 8'b00000000;
      11'h4C2: data = 8'b00000000;
      11'h4C3: data = 8'b00000000;

      11'h4C4: data = 8'b00111000; // ']'
      11'h4C5: data = 8'b00001000;
      11'h4C6: data = 8'b00001000;
      11'h4C7: data = 8'b00001000;
      11'h4C8: data = 8'b00001000;
      11'h4C9: data = 8'b00001000;
      11'h4CA: data = 8'b00001000;
      11'h4CB: data = 8'b00001000;
      11'h4CC: data = 8'b00001000;
      11'h4CD: data = 8'b00001000;
      11'h4CE: data = 8'b00001000;
      11'h4CF: data = 8'b00001000;
      11'h4D0: data = 8'b00111000; // B
      11'h4D1: data = 8'b00000000;
      11'h4D2: data = 8'b00000000;
      11'h4D3: data = 8'b00000000;
      11'h4D4: data = 8'b00000000;
      11'h4D5: data = 8'b00000000;
      11'h4D6: data = 8'b00000000;
      11'h4D7: data = 8'b00000000;

      11'h4D8: data = 8'b00010000; // '^'
      11'h4D9: data = 8'b00101000;
      11'h4DA: data = 8'b01000100;
      11'h4DB: data = 8'b00000000;
      11'h4DC: data = 8'b00000000;
      11'h4DD: data = 8'b00000000;
      11'h4DE: data = 8'b00000000;
      11'h4DF: data = 8'b00000000;
      11'h4E0: data = 8'b00000000;
      11'h4E1: data = 8'b00000000;
      11'h4E2: data = 8'b00000000;
      11'h4E3: data = 8'b00000000;
      11'h4E4: data = 8'b00000000; // B
      11'h4E5: data = 8'b00000000;
      11'h4E6: data = 8'b00000000;
      11'h4E7: data = 8'b00000000;
      11'h4E8: data = 8'b00000000;
      11'h4E9: data = 8'b00000000;
      11'h4EA: data = 8'b00000000;
      11'h4EB: data = 8'b00000000;

      11'h4EC: data = 8'b00000000; // '_'
      11'h4ED: data = 8'b00000000;
      11'h4EE: data = 8'b00000000;
      11'h4EF: data = 8'b00000000;
      11'h4F0: data = 8'b00000000;
      11'h4F1: data = 8'b00000000;
      11'h4F2: data = 8'b00000000;
      11'h4F3: data = 8'b00000000;
      11'h4F4: data = 8'b00000000;
      11'h4F5: data = 8'b00000000;
      11'h4F6: data = 8'b00000000;
      11'h4F7: data = 8'b00000000;
      11'h4F8: data = 8'b11111110; // B
      11'h4F9: data = 8'b00000000;
      11'h4FA: data = 8'b00000000;
      11'h4FB: data = 8'b00000000;
      11'h4FC: data = 8'b00000000;
      11'h4FD: data = 8'b00000000;
      11'h4FE: data = 8'b00000000;
      11'h4FF: data = 8'b00000000;

      11'h500: data = 8'b00100000; // '`'
      11'h501: data = 8'b00010000;
      11'h502: data = 8'b00000000;
      11'h503: data = 8'b00000000;
      11'h504: data = 8'b00000000;
      11'h505: data = 8'b00000000;
      11'h506: data = 8'b00000000;
      11'h507: data = 8'b00000000;
      11'h508: data = 8'b00000000;
      11'h509: data = 8'b00000000;
      11'h50A: data = 8'b00000000;
      11'h50B: data = 8'b00000000;
      11'h50C: data = 8'b00000000; // B
      11'h50D: data = 8'b00000000;
      11'h50E: data = 8'b00000000;
      11'h50F: data = 8'b00000000;
      11'h510: data = 8'b00000000;
      11'h511: data = 8'b00000000;
      11'h512: data = 8'b00000000;
      11'h513: data = 8'b00000000;

      11'h514: data = 8'b00000000; // 'a'
      11'h515: data = 8'b00000000;
      11'h516: data = 8'b00000000;
      11'h517: data = 8'b00000000;
      11'h518: data = 8'b00000000;
      11'h519: data = 8'b00000000;
      11'h51A: data = 8'b01111000;
      11'h51B: data = 8'b00000100;
      11'h51C: data = 8'b00111100;
      11'h51D: data = 8'b01000100;
      11'h51E: data = 8'b01000100;
      11'h51F: data = 8'b01000100;
      11'h520: data = 8'b00111100; // B
      11'h521: data = 8'b00000000;
      11'h522: data = 8'b00000000;
      11'h523: data = 8'b00000000;
      11'h524: data = 8'b00000000;
      11'h525: data = 8'b00000000;
      11'h526: data = 8'b00000000;
      11'h527: data = 8'b00000000;

      11'h528: data = 8'b01000000; // 'b'
      11'h529: data = 8'b01000000;
      11'h52A: data = 8'b01000000;
      11'h52B: data = 8'b01000000;
      11'h52C: data = 8'b01000000;
      11'h52D: data = 8'b01000000;
      11'h52E: data = 8'b01111000;
      11'h52F: data = 8'b01000100;
      11'h530: data = 8'b01000100;
      11'h531: data = 8'b01000100;
      11'h532: data = 8'b01000100;
      11'h533: data = 8'b01000100;
      11'h534: data = 8'b01111000; // B
      11'h535: data = 8'b00000000;
      11'h536: data = 8'b00000000;
      11'h537: data = 8'b00000000;
      11'h538: data = 8'b00000000;
      11'h539: data = 8'b00000000;
      11'h53A: data = 8'b00000000;
      11'h53B: data = 8'b00000000;

      11'h53C: data = 8'b00000000; // 'c'
      11'h53D: data = 8'b00000000;
      11'h53E: data = 8'b00000000;
      11'h53F: data = 8'b00000000;
      11'h540: data = 8'b00000000;
      11'h541: data = 8'b00000000;
      11'h542: data = 8'b00111000;
      11'h543: data = 8'b01000100;
      11'h544: data = 8'b01000000;
      11'h545: data = 8'b01000000;
      11'h546: data = 8'b01000000;
      11'h547: data = 8'b01000100;
      11'h548: data = 8'b00111000; // B
      11'h549: data = 8'b00000000;
      11'h54A: data = 8'b00000000;
      11'h54B: data = 8'b00000000;
      11'h54C: data = 8'b00000000;
      11'h54D: data = 8'b00000000;
      11'h54E: data = 8'b00000000;
      11'h54F: data = 8'b00000000;

      11'h550: data = 8'b00000100; // 'd'
      11'h551: data = 8'b00000100;
      11'h552: data = 8'b00000100;
      11'h553: data = 8'b00000100;
      11'h554: data = 8'b00000100;
      11'h555: data = 8'b00000100;
      11'h556: data = 8'b00111100;
      11'h557: data = 8'b01000100;
      11'h558: data = 8'b01000100;
      11'h559: data = 8'b01000100;
      11'h55A: data = 8'b01000100;
      11'h55B: data = 8'b01000100;
      11'h55C: data = 8'b00111100; // B
      11'h55D: data = 8'b00000000;
      11'h55E: data = 8'b00000000;
      11'h55F: data = 8'b00000000;
      11'h560: data = 8'b00000000;
      11'h561: data = 8'b00000000;
      11'h562: data = 8'b00000000;
      11'h563: data = 8'b00000000;

      11'h564: data = 8'b00000000; // 'e'
      11'h565: data = 8'b00000000;
      11'h566: data = 8'b00000000;
      11'h567: data = 8'b00000000;
      11'h568: data = 8'b00000000;
      11'h569: data = 8'b00000000;
      11'h56A: data = 8'b00111000;
      11'h56B: data = 8'b01000100;
      11'h56C: data = 8'b01000100;
      11'h56D: data = 8'b01111100;
      11'h56E: data = 8'b01000000;
      11'h56F: data = 8'b01000000;
      11'h570: data = 8'b00111100; // B
      11'h571: data = 8'b00000000;
      11'h572: data = 8'b00000000;
      11'h573: data = 8'b00000000;
      11'h574: data = 8'b00000000;
      11'h575: data = 8'b00000000;
      11'h576: data = 8'b00000000;
      11'h577: data = 8'b00000000;

      11'h578: data = 8'b00001100; // 'f'
      11'h579: data = 8'b00010000;
      11'h57A: data = 8'b00010000;
      11'h57B: data = 8'b00010000;
      11'h57C: data = 8'b00010000;
      11'h57D: data = 8'b00010000;
      11'h57E: data = 8'b01111100;
      11'h57F: data = 8'b00010000;
      11'h580: data = 8'b00010000;
      11'h581: data = 8'b00010000;
      11'h582: data = 8'b00010000;
      11'h583: data = 8'b00010000;
      11'h584: data = 8'b00010000; // B
      11'h585: data = 8'b00000000;
      11'h586: data = 8'b00000000;
      11'h587: data = 8'b00000000;
      11'h588: data = 8'b00000000;
      11'h589: data = 8'b00000000;
      11'h58A: data = 8'b00000000;
      11'h58B: data = 8'b00000000;

      11'h58C: data = 8'b00000000; // 'g'
      11'h58D: data = 8'b00000000;
      11'h58E: data = 8'b00000000;
      11'h58F: data = 8'b00000000;
      11'h590: data = 8'b00000000;
      11'h591: data = 8'b00000000;
      11'h592: data = 8'b00111000;
      11'h593: data = 8'b01000100;
      11'h594: data = 8'b01000100;
      11'h595: data = 8'b01000100;
      11'h596: data = 8'b01000100;
      11'h597: data = 8'b01000100;
      11'h598: data = 8'b00111100; // B
      11'h599: data = 8'b00000100;
      11'h59A: data = 8'b00000100;
      11'h59B: data = 8'b00000100;
      11'h59C: data = 8'b00000100;
      11'h59D: data = 8'b01000100;
      11'h59E: data = 8'b00111000;
      11'h59F: data = 8'b00000000;

      11'h5A0: data = 8'b01000000; // 'h'
      11'h5A1: data = 8'b01000000;
      11'h5A2: data = 8'b01000000;
      11'h5A3: data = 8'b01000000;
      11'h5A4: data = 8'b01000000;
      11'h5A5: data = 8'b01000000;
      11'h5A6: data = 8'b01111000;
      11'h5A7: data = 8'b01000100;
      11'h5A8: data = 8'b01000100;
      11'h5A9: data = 8'b01000100;
      11'h5AA: data = 8'b01000100;
      11'h5AB: data = 8'b01000100;
      11'h5AC: data = 8'b01000100; // B
      11'h5AD: data = 8'b00000000;
      11'h5AE: data = 8'b00000000;
      11'h5AF: data = 8'b00000000;
      11'h5B0: data = 8'b00000000;
      11'h5B1: data = 8'b00000000;
      11'h5B2: data = 8'b00000000;
      11'h5B3: data = 8'b00000000;

      11'h5B4: data = 8'b00000000; // 'i'
      11'h5B5: data = 8'b00000000;
      11'h5B6: data = 8'b00000000;
      11'h5B7: data = 8'b00000000;
      11'h5B8: data = 8'b00010000;
      11'h5B9: data = 8'b00000000;
      11'h5BA: data = 8'b00110000;
      11'h5BB: data = 8'b00010000;
      11'h5BC: data = 8'b00010000;
      11'h5BD: data = 8'b00010000;
      11'h5BE: data = 8'b00010000;
      11'h5BF: data = 8'b00010000;
      11'h5C0: data = 8'b00111000; // B
      11'h5C1: data = 8'b00000000;
      11'h5C2: data = 8'b00000000;
      11'h5C3: data = 8'b00000000;
      11'h5C4: data = 8'b00000000;
      11'h5C5: data = 8'b00000000;
      11'h5C6: data = 8'b00000000;
      11'h5C7: data = 8'b00000000;

      11'h5C8: data = 8'b00000000; // 'j'
      11'h5C9: data = 8'b00000000;
      11'h5CA: data = 8'b00000000;
      11'h5CB: data = 8'b00000000;
      11'h5CC: data = 8'b00001000;
      11'h5CD: data = 8'b00000000;
      11'h5CE: data = 8'b00011000;
      11'h5CF: data = 8'b00001000;
      11'h5D0: data = 8'b00001000;
      11'h5D1: data = 8'b00001000;
      11'h5D2: data = 8'b00001000;
      11'h5D3: data = 8'b00001000;
      11'h5D4: data = 8'b00001000; // B
      11'h5D5: data = 8'b00001000;
      11'h5D6: data = 8'b00001000;
      11'h5D7: data = 8'b00001000;
      11'h5D8: data = 8'b00001000;
      11'h5D9: data = 8'b01001000;
      11'h5DA: data = 8'b00110000;
      11'h5DB: data = 8'b00000000;

      11'h5DC: data = 8'b01000000; // 'k'
      11'h5DD: data = 8'b01000000;
      11'h5DE: data = 8'b01000000;
      11'h5DF: data = 8'b01000000;
      11'h5E0: data = 8'b01000000;
      11'h5E1: data = 8'b01000000;
      11'h5E2: data = 8'b01000100;
      11'h5E3: data = 8'b01001000;
      11'h5E4: data = 8'b01010000;
      11'h5E5: data = 8'b01100000;
      11'h5E6: data = 8'b01010000;
      11'h5E7: data = 8'b01001000;
      11'h5E8: data = 8'b01000100; // B
      11'h5E9: data = 8'b00000000;
      11'h5EA: data = 8'b00000000;
      11'h5EB: data = 8'b00000000;
      11'h5EC: data = 8'b00000000;
      11'h5ED: data = 8'b00000000;
      11'h5EE: data = 8'b00000000;
      11'h5EF: data = 8'b00000000;

      11'h5F0: data = 8'b00110000; // 'l'
      11'h5F1: data = 8'b00010000;
      11'h5F2: data = 8'b00010000;
      11'h5F3: data = 8'b00010000;
      11'h5F4: data = 8'b00010000;
      11'h5F5: data = 8'b00010000;
      11'h5F6: data = 8'b00010000;
      11'h5F7: data = 8'b00010000;
      11'h5F8: data = 8'b00010000;
      11'h5F9: data = 8'b00010000;
      11'h5FA: data = 8'b00010000;
      11'h5FB: data = 8'b00010000;
      11'h5FC: data = 8'b01111100; // B
      11'h5FD: data = 8'b00000000;
      11'h5FE: data = 8'b00000000;
      11'h5FF: data = 8'b00000000;
      11'h600: data = 8'b00000000;
      11'h601: data = 8'b00000000;
      11'h602: data = 8'b00000000;
      11'h603: data = 8'b00000000;

      11'h604: data = 8'b00000000; // 'm'
      11'h605: data = 8'b00000000;
      11'h606: data = 8'b00000000;
      11'h607: data = 8'b00000000;
      11'h608: data = 8'b00000000;
      11'h609: data = 8'b00000000;
      11'h60A: data = 8'b01101100;
      11'h60B: data = 8'b01010100;
      11'h60C: data = 8'b01010100;
      11'h60D: data = 8'b01010100;
      11'h60E: data = 8'b01010100;
      11'h60F: data = 8'b01010100;
      11'h610: data = 8'b01000100; // B
      11'h611: data = 8'b00000000;
      11'h612: data = 8'b00000000;
      11'h613: data = 8'b00000000;
      11'h614: data = 8'b00000000;
      11'h615: data = 8'b00000000;
      11'h616: data = 8'b00000000;
      11'h617: data = 8'b00000000;

      11'h618: data = 8'b00000000; // 'n'
      11'h619: data = 8'b00000000;
      11'h61A: data = 8'b00000000;
      11'h61B: data = 8'b00000000;
      11'h61C: data = 8'b00000000;
      11'h61D: data = 8'b00000000;
      11'h61E: data = 8'b00111000;
      11'h61F: data = 8'b01000100;
      11'h620: data = 8'b01000100;
      11'h621: data = 8'b01000100;
      11'h622: data = 8'b01000100;
      11'h623: data = 8'b01000100;
      11'h624: data = 8'b01000100; // B
      11'h625: data = 8'b00000000;
      11'h626: data = 8'b00000000;
      11'h627: data = 8'b00000000;
      11'h628: data = 8'b00000000;
      11'h629: data = 8'b00000000;
      11'h62A: data = 8'b00000000;
      11'h62B: data = 8'b00000000;

      11'h62C: data = 8'b00000000; // 'o'
      11'h62D: data = 8'b00000000;
      11'h62E: data = 8'b00000000;
      11'h62F: data = 8'b00000000;
      11'h630: data = 8'b00000000;
      11'h631: data = 8'b00000000;
      11'h632: data = 8'b00111000;
      11'h633: data = 8'b01000100;
      11'h634: data = 8'b01000100;
      11'h635: data = 8'b01000100;
      11'h636: data = 8'b01000100;
      11'h637: data = 8'b01000100;
      11'h638: data = 8'b00111000; // B
      11'h639: data = 8'b00000000;
      11'h63A: data = 8'b00000000;
      11'h63B: data = 8'b00000000;
      11'h63C: data = 8'b00000000;
      11'h63D: data = 8'b00000000;
      11'h63E: data = 8'b00000000;
      11'h63F: data = 8'b00000000;

      11'h640: data = 8'b00000000; // 'p'
      11'h641: data = 8'b00000000;
      11'h642: data = 8'b00000000;
      11'h643: data = 8'b00000000;
      11'h644: data = 8'b00000000;
      11'h645: data = 8'b00000000;
      11'h646: data = 8'b01111000;
      11'h647: data = 8'b01000100;
      11'h648: data = 8'b01000100;
      11'h649: data = 8'b01000100;
      11'h64A: data = 8'b01000100;
      11'h64B: data = 8'b01000100;
      11'h64C: data = 8'b01111000; // B
      11'h64D: data = 8'b01000000;
      11'h64E: data = 8'b01000000;
      11'h64F: data = 8'b01000000;
      11'h650: data = 8'b01000000;
      11'h651: data = 8'b01000000;
      11'h652: data = 8'b01000000;
      11'h653: data = 8'b00000000;

      11'h654: data = 8'b00000000; // 'q'
      11'h655: data = 8'b00000000;
      11'h656: data = 8'b00000000;
      11'h657: data = 8'b00000000;
      11'h658: data = 8'b00000000;
      11'h659: data = 8'b00000000;
      11'h65A: data = 8'b00111100;
      11'h65B: data = 8'b01000100;
      11'h65C: data = 8'b01000100;
      11'h65D: data = 8'b01000100;
      11'h65E: data = 8'b01000100;
      11'h65F: data = 8'b01000100;
      11'h660: data = 8'b00111100; // B
      11'h661: data = 8'b00000100;
      11'h662: data = 8'b00000100;
      11'h663: data = 8'b00000100;
      11'h664: data = 8'b00000100;
      11'h665: data = 8'b00000100;
      11'h666: data = 8'b00000100;
      11'h667: data = 8'b00000000;

      11'h668: data = 8'b00000000; // 'r'
      11'h669: data = 8'b00000000;
      11'h66A: data = 8'b00000000;
      11'h66B: data = 8'b00000000;
      11'h66C: data = 8'b00000000;
      11'h66D: data = 8'b00000000;
      11'h66E: data = 8'b00111100;
      11'h66F: data = 8'b01000000;
      11'h670: data = 8'b01000000;
      11'h671: data = 8'b01000000;
      11'h672: data = 8'b01000000;
      11'h673: data = 8'b01000000;
      11'h674: data = 8'b01000000; // B
      11'h675: data = 8'b00000000;
      11'h676: data = 8'b00000000;
      11'h677: data = 8'b00000000;
      11'h678: data = 8'b00000000;
      11'h679: data = 8'b00000000;
      11'h67A: data = 8'b00000000;
      11'h67B: data = 8'b00000000;

      11'h67C: data = 8'b00000000; // 's'
      11'h67D: data = 8'b00000000;
      11'h67E: data = 8'b00000000;
      11'h67F: data = 8'b00000000;
      11'h680: data = 8'b00000000;
      11'h681: data = 8'b00000000;
      11'h682: data = 8'b00111100;
      11'h683: data = 8'b01000000;
      11'h684: data = 8'b01000000;
      11'h685: data = 8'b00111000;
      11'h686: data = 8'b00000100;
      11'h687: data = 8'b00000100;
      11'h688: data = 8'b01111000; // B
      11'h689: data = 8'b00000000;
      11'h68A: data = 8'b00000000;
      11'h68B: data = 8'b00000000;
      11'h68C: data = 8'b00000000;
      11'h68D: data = 8'b00000000;
      11'h68E: data = 8'b00000000;
      11'h68F: data = 8'b00000000;

      11'h690: data = 8'b00000000; // 't'
      11'h691: data = 8'b00000000;
      11'h692: data = 8'b00000000;
      11'h693: data = 8'b00000000;
      11'h694: data = 8'b00010000;
      11'h695: data = 8'b00010000;
      11'h696: data = 8'b01111100;
      11'h697: data = 8'b00010000;
      11'h698: data = 8'b00010000;
      11'h699: data = 8'b00010000;
      11'h69A: data = 8'b00010000;
      11'h69B: data = 8'b00010000;
      11'h69C: data = 8'b00011000; // B
      11'h69D: data = 8'b00000000;
      11'h69E: data = 8'b00000000;
      11'h69F: data = 8'b00000000;
      11'h6A0: data = 8'b00000000;
      11'h6A1: data = 8'b00000000;
      11'h6A2: data = 8'b00000000;
      11'h6A3: data = 8'b00000000;

      11'h6A4: data = 8'b00000000; // 'u'
      11'h6A5: data = 8'b00000000;
      11'h6A6: data = 8'b00000000;
      11'h6A7: data = 8'b00000000;
      11'h6A8: data = 8'b00000000;
      11'h6A9: data = 8'b00000000;
      11'h6AA: data = 8'b01000100;
      11'h6AB: data = 8'b01000100;
      11'h6AC: data = 8'b01000100;
      11'h6AD: data = 8'b01000100;
      11'h6AE: data = 8'b01000100;
      11'h6AF: data = 8'b01000100;
      11'h6B0: data = 8'b00111000; // B
      11'h6B1: data = 8'b00000000;
      11'h6B2: data = 8'b00000000;
      11'h6B3: data = 8'b00000000;
      11'h6B4: data = 8'b00000000;
      11'h6B5: data = 8'b00000000;
      11'h6B6: data = 8'b00000000;
      11'h6B7: data = 8'b00000000;

      11'h6B8: data = 8'b00000000; // 'v'
      11'h6B9: data = 8'b00000000;
      11'h6BA: data = 8'b00000000;
      11'h6BB: data = 8'b00000000;
      11'h6BC: data = 8'b00000000;
      11'h6BD: data = 8'b00000000;
      11'h6BE: data = 8'b01000100;
      11'h6BF: data = 8'b01000100;
      11'h6C0: data = 8'b01000100;
      11'h6C1: data = 8'b01000100;
      11'h6C2: data = 8'b01000100;
      11'h6C3: data = 8'b00101000;
      11'h6C4: data = 8'b00010000; // B
      11'h6C5: data = 8'b00000000;
      11'h6C6: data = 8'b00000000;
      11'h6C7: data = 8'b00000000;
      11'h6C8: data = 8'b00000000;
      11'h6C9: data = 8'b00000000;
      11'h6CA: data = 8'b00000000;
      11'h6CB: data = 8'b00000000;

      11'h6CC: data = 8'b00000000; // 'w'
      11'h6CD: data = 8'b00000000;
      11'h6CE: data = 8'b00000000;
      11'h6CF: data = 8'b00000000;
      11'h6D0: data = 8'b00000000;
      11'h6D1: data = 8'b00000000;
      11'h6D2: data = 8'b01000100;
      11'h6D3: data = 8'b01010100;
      11'h6D4: data = 8'b01010100;
      11'h6D5: data = 8'b01010100;
      11'h6D6: data = 8'b01010100;
      11'h6D7: data = 8'b01010100;
      11'h6D8: data = 8'b00101000; // B
      11'h6D9: data = 8'b00000000;
      11'h6DA: data = 8'b00000000;
      11'h6DB: data = 8'b00000000;
      11'h6DC: data = 8'b00000000;
      11'h6DD: data = 8'b00000000;
      11'h6DE: data = 8'b00000000;
      11'h6DF: data = 8'b00000000;

      11'h6E0: data = 8'b00000000; // 'x'
      11'h6E1: data = 8'b00000000;
      11'h6E2: data = 8'b00000000;
      11'h6E3: data = 8'b00000000;
      11'h6E4: data = 8'b00000000;
      11'h6E5: data = 8'b00000000;
      11'h6E6: data = 8'b01000100;
      11'h6E7: data = 8'b01000100;
      11'h6E8: data = 8'b00101000;
      11'h6E9: data = 8'b00010000;
      11'h6EA: data = 8'b00101000;
      11'h6EB: data = 8'b01000100;
      11'h6EC: data = 8'b01000100; // B
      11'h6ED: data = 8'b00000000;
      11'h6EE: data = 8'b00000000;
      11'h6EF: data = 8'b00000000;
      11'h6F0: data = 8'b00000000;
      11'h6F1: data = 8'b00000000;
      11'h6F2: data = 8'b00000000;
      11'h6F3: data = 8'b00000000;

      11'h6F4: data = 8'b00000000; // 'y'
      11'h6F5: data = 8'b00000000;
      11'h6F6: data = 8'b00000000;
      11'h6F7: data = 8'b00000000;
      11'h6F8: data = 8'b00000000;
      11'h6F9: data = 8'b00000000;
      11'h6FA: data = 8'b01000100;
      11'h6FB: data = 8'b01000100;
      11'h6FC: data = 8'b01000100;
      11'h6FD: data = 8'b01000100;
      11'h6FE: data = 8'b01000100;
      11'h6FF: data = 8'b01000100;
      11'h700: data = 8'b00111100; // B
      11'h701: data = 8'b00000100;
      11'h702: data = 8'b00000100;
      11'h703: data = 8'b00000100;
      11'h704: data = 8'b00000100;
      11'h705: data = 8'b01000100;
      11'h706: data = 8'b00111000;
      11'h707: data = 8'b00000000;

      11'h708: data = 8'b00000000; // 'z'
      11'h709: data = 8'b00000000;
      11'h70A: data = 8'b00000000;
      11'h70B: data = 8'b00000000;
      11'h70C: data = 8'b00000000;
      11'h70D: data = 8'b00000000;
      11'h70E: data = 8'b01111100;
      11'h70F: data = 8'b00000100;
      11'h710: data = 8'b00001000;
      11'h711: data = 8'b00010000;
      11'h712: data = 8'b00100000;
      11'h713: data = 8'b01000000;
      11'h714: data = 8'b01111100; // B
      11'h715: data = 8'b00000000;
      11'h716: data = 8'b00000000;
      11'h717: data = 8'b00000000;
      11'h718: data = 8'b00000000;
      11'h719: data = 8'b00000000;
      11'h71A: data = 8'b00000000;
      11'h71B: data = 8'b00000000;

      11'h71C: data = 8'b00001000; // '{'
      11'h71D: data = 8'b00010000;
      11'h71E: data = 8'b00010000;
      11'h71F: data = 8'b00010000;
      11'h720: data = 8'b00010000;
      11'h721: data = 8'b00010000;
      11'h722: data = 8'b00100000;
      11'h723: data = 8'b00010000;
      11'h724: data = 8'b00010000;
      11'h725: data = 8'b00010000;
      11'h726: data = 8'b00010000;
      11'h727: data = 8'b00010000;
      11'h728: data = 8'b00001000; // B
      11'h729: data = 8'b00000000;
      11'h72A: data = 8'b00000000;
      11'h72B: data = 8'b00000000;
      11'h72C: data = 8'b00000000;
      11'h72D: data = 8'b00000000;
      11'h72E: data = 8'b00000000;
      11'h72F: data = 8'b00000000;

      11'h730: data = 8'b00010000; // '|'
      11'h731: data = 8'b00010000;
      11'h732: data = 8'b00010000;
      11'h733: data = 8'b00010000;
      11'h734: data = 8'b00010000;
      11'h735: data = 8'b00010000;
      11'h736: data = 8'b00010000;
      11'h737: data = 8'b00010000;
      11'h738: data = 8'b00010000;
      11'h739: data = 8'b00010000;
      11'h73A: data = 8'b00010000;
      11'h73B: data = 8'b00010000;
      11'h73C: data = 8'b00010000; // B
      11'h73D: data = 8'b00000000;
      11'h73E: data = 8'b00000000;
      11'h73F: data = 8'b00000000;
      11'h740: data = 8'b00000000;
      11'h741: data = 8'b00000000;
      11'h742: data = 8'b00000000;
      11'h743: data = 8'b00000000;

      11'h744: data = 8'b00100000; // '}'
      11'h745: data = 8'b00010000;
      11'h746: data = 8'b00010000;
      11'h747: data = 8'b00010000;
      11'h748: data = 8'b00010000;
      11'h749: data = 8'b00010000;
      11'h74A: data = 8'b00001000;
      11'h74B: data = 8'b00010000;
      11'h74C: data = 8'b00010000;
      11'h74D: data = 8'b00010000;
      11'h74E: data = 8'b00010000;
      11'h74F: data = 8'b00010000;
      11'h750: data = 8'b00100000; // B
      11'h751: data = 8'b00000000;
      11'h752: data = 8'b00000000;
      11'h753: data = 8'b00000000;
      11'h754: data = 8'b00000000;
      11'h755: data = 8'b00000000;
      11'h756: data = 8'b00000000;
      11'h757: data = 8'b00000000;

      11'h758: data = 8'b01100010; // '~'
      11'h759: data = 8'b10010010;
      11'h75A: data = 8'b10001100;
      11'h75B: data = 8'b00000000;
      11'h75C: data = 8'b00000000;
      11'h75D: data = 8'b00000000;
      11'h75E: data = 8'b00000000;
      11'h75F: data = 8'b00000000;
      11'h760: data = 8'b00000000;
      11'h761: data = 8'b00000000;
      11'h762: data = 8'b00000000;
      11'h763: data = 8'b00000000;
      11'h764: data = 8'b00000000; // B
      11'h765: data = 8'b00000000;
      11'h766: data = 8'b00000000;
      11'h767: data = 8'b00000000;
      11'h768: data = 8'b00000000;
      11'h769: data = 8'b00000000;
      11'h76A: data = 8'b00000000;
      11'h76B: data = 8'b00000000;

      default data = 8'b00000000; // blank
   
   endcase
   
endmodule

////////////////////////////////////////////////////////////////////////////////
//
// KEYBOARD SCAN CODE CONVERTER
//
// Converts an 8 bit scan code to ASCII characters. Note that we don't represent
// any control or other special characters in this table. Controls, shifts and
// other keys are created at a higher level.
//
// There are two tables, the lower case or "normal" lookup table, and a shifted
// table that gives either the upper case for the key, or an alternate 
// character.
//
// To determine the proper arrangement of scan codes to ascii codes, a keyboard
// scan code table was used, which can be found various places on the internet.
//

module scnrom(addr, data);

   input  [7:0] addr;
   output [7:0] data;

   reg [7:0]  data;

   always @(addr) case (addr)

      8'h00: data = 8'h00; // 
      8'h01: data = 8'h00; // f9
      8'h02: data = 8'h00; // 
      8'h03: data = 8'h00; // f5
      8'h04: data = 8'h00; // f3
      8'h05: data = 8'h00; // f1
      8'h06: data = 8'h00; // f2
      8'h07: data = 8'h00; // f12
      8'h08: data = 8'h00; // 
      8'h09: data = 8'h00; // f10
      8'h0A: data = 8'h00; // f8
      8'h0B: data = 8'h00; // f6
      8'h0C: data = 8'h00; // f4
      8'h0D: data = 8'h09; // tab
      8'h0E: data = 8'h60; // `
      8'h0F: data = 8'h00; // 
      8'h10: data = 8'h00; // 
      8'h11: data = 8'h00; // lft alt
      8'h12: data = 8'h00; // lft shift
      8'h13: data = 8'h00; // 
      8'h14: data = 8'h00; // left ctl
      8'h15: data = 8'h71; // q
      8'h16: data = 8'h31; // 1
      8'h17: data = 8'h00; // 
      8'h18: data = 8'h00; // 
      8'h19: data = 8'h00; // 
      8'h1A: data = 8'h7a; // z
      8'h1B: data = 8'h73; // s
      8'h1C: data = 8'h61; // a
      8'h1D: data = 8'h77; // w
      8'h1E: data = 8'h32; // 2
      8'h1F: data = 8'h00; // 
      8'h20: data = 8'h00; // 
      8'h21: data = 8'h63; // c
      8'h22: data = 8'h78; // x
      8'h23: data = 8'h64; // d
      8'h24: data = 8'h65; // e
      8'h25: data = 8'h34; // 4
      8'h26: data = 8'h33; // 3
      8'h27: data = 8'h00; // 
      8'h28: data = 8'h00; // 
      8'h29: data = 8'h20; // sp
      8'h2A: data = 8'h76; // v
      8'h2B: data = 8'h66; // f
      8'h2C: data = 8'h74; // t
      8'h2D: data = 8'h72; // r
      8'h2E: data = 8'h35; // 5
      8'h2F: data = 8'h00; // 
      8'h30: data = 8'h00; // 
      8'h31: data = 8'h6e; // n
      8'h32: data = 8'h62; // b
      8'h33: data = 8'h68; // h
      8'h34: data = 8'h67; // g
      8'h35: data = 8'h79; // y
      8'h36: data = 8'h36; // 6
      8'h37: data = 8'h00; // 
      8'h38: data = 8'h00; // 
      8'h39: data = 8'h00; // 
      8'h3A: data = 8'h6d; // m
      8'h3B: data = 8'h6a; // j
      8'h3C: data = 8'h75; // u
      8'h3D: data = 8'h37; // 7
      8'h3E: data = 8'h38; // 8
      8'h3F: data = 8'h00; // 
      8'h40: data = 8'h00; // 
      8'h41: data = 8'h2c; // ,
      8'h42: data = 8'h6b; // k
      8'h43: data = 8'h69; // i
      8'h44: data = 8'h6f; // o
      8'h45: data = 8'h30; // 0
      8'h46: data = 8'h39; // 9
      8'h47: data = 8'h00; // 
      8'h48: data = 8'h00; // 
      8'h49: data = 8'h2e; // .
      8'h4A: data = 8'h2f; // /
      8'h4B: data = 8'h6c; // l
      8'h4C: data = 8'h3b; // ;
      8'h4D: data = 8'h70; // p
      8'h4E: data = 8'h2d; // -
      8'h4F: data = 8'h00; // 
      8'h50: data = 8'h00; // 
      8'h51: data = 8'h00; // 
      8'h52: data = 8'h27; // '
      8'h53: data = 8'h00; // 
      8'h54: data = 8'h5b; // [
      8'h55: data = 8'h3d; // =
      8'h56: data = 8'h00; // 
      8'h57: data = 8'h00; // 
      8'h58: data = 8'h00; // caps lock
      8'h59: data = 8'h00; // rgt shift
      8'h5A: data = 8'h0D; // ent
      8'h5B: data = 8'h5d; // ]
      8'h5C: data = 8'h00; // 
      8'h5D: data = 8'h5c; // \
      8'h5E: data = 8'h00; // 
      8'h5F: data = 8'h00; // 
      8'h60: data = 8'h00; // 
      8'h61: data = 8'h00; // 
      8'h62: data = 8'h00; // 
      8'h63: data = 8'h00; // 
      8'h64: data = 8'h00; // 
      8'h65: data = 8'h00; // 
      8'h66: data = 8'h08; // bcksp
      8'h67: data = 8'h00; // 
      8'h68: data = 8'h00; // 
      8'h69: data = 8'h31; // 1
      8'h6A: data = 8'h00; // 
      8'h6B: data = 8'h34; // 4
      8'h6C: data = 8'h37; // 7
      8'h6D: data = 8'h00; // 
      8'h6E: data = 8'h00; // 
      8'h6F: data = 8'h00; // 
      8'h70: data = 8'h30; // 0
      8'h71: data = 8'h2e; // .
      8'h72: data = 8'h32; // 2
      8'h73: data = 8'h35; // 5
      8'h74: data = 8'h36; // 6
      8'h75: data = 8'h38; // 8
      8'h76: data = 8'h1B; // esc
      8'h77: data = 8'h00; // num lock
      8'h78: data = 8'h00; // f11
      8'h79: data = 8'h2b; // +
      8'h7A: data = 8'h33; // 3
      8'h7B: data = 8'h2d; // -
      8'h7C: data = 8'h2a; // -
      8'h7D: data = 8'h39; // 9
      8'h7E: data = 8'h00; // scl lock
      8'h7F: data = 8'h00; // 
      8'h80: data = 8'h00; // 
      8'h81: data = 8'h00; // 
      8'h82: data = 8'h00; // 
      8'h83: data = 8'h00; // f7
      8'h84: data = 8'h00; // 
      8'h85: data = 8'h00; // 
      8'h86: data = 8'h00; // 
      8'h87: data = 8'h00; // 
      8'h88: data = 8'h00; // 
      8'h89: data = 8'h00; // 
      8'h8A: data = 8'h00; // 
      8'h8B: data = 8'h00; // 
      8'h8C: data = 8'h00; // 
      8'h8D: data = 8'h00; // 
      8'h8E: data = 8'h00; // 
      8'h8F: data = 8'h00; // 

      default data = 8'b00000000; // blank
   
   endcase
   
endmodule

// upper case version

module scnromu(addr, data);

   input  [7:0] addr;
   output [7:0] data;

   reg [7:0]  data;

   always @(addr) case (addr)

      8'h00: data = 8'h00; // 
      8'h01: data = 8'h00; // f9
      8'h02: data = 8'h00; // 
      8'h03: data = 8'h00; // f5
      8'h04: data = 8'h00; // f3
      8'h05: data = 8'h00; // f1
      8'h06: data = 8'h00; // f2
      8'h07: data = 8'h00; // f12
      8'h08: data = 8'h00; // 
      8'h09: data = 8'h00; // f10
      8'h0A: data = 8'h00; // f8
      8'h0B: data = 8'h00; // f6
      8'h0C: data = 8'h00; // f4
      8'h0D: data = 8'h09; // tab
      8'h0E: data = 8'h7e; // ~
      8'h0F: data = 8'h00; // 
      8'h10: data = 8'h00; // 
      8'h11: data = 8'h00; // lft alt
      8'h12: data = 8'h00; // lft shift
      8'h13: data = 8'h00; // 
      8'h14: data = 8'h00; // lft ctl
      8'h15: data = 8'h51; // Q
      8'h16: data = 8'h21; // !
      8'h17: data = 8'h00; // 
      8'h18: data = 8'h00; // 
      8'h19: data = 8'h00; // 
      8'h1A: data = 8'h5a; // Z
      8'h1B: data = 8'h53; // S
      8'h1C: data = 8'h41; // A
      8'h1D: data = 8'h57; // W
      8'h1E: data = 8'h40; // @
      8'h1F: data = 8'h00; // 
      8'h20: data = 8'h00; // 
      8'h21: data = 8'h43; // C
      8'h22: data = 8'h58; // X
      8'h23: data = 8'h44; // D
      8'h24: data = 8'h45; // E
      8'h25: data = 8'h24; // $
      8'h26: data = 8'h23; // #
      8'h27: data = 8'h00; // 
      8'h28: data = 8'h00; // 
      8'h29: data = 8'h20; // sp
      8'h2A: data = 8'h56; // V
      8'h2B: data = 8'h46; // F
      8'h2C: data = 8'h54; // T
      8'h2D: data = 8'h52; // R
      8'h2E: data = 8'h25; // %
      8'h2F: data = 8'h00; // 
      8'h30: data = 8'h00; // 
      8'h31: data = 8'h4e; // N
      8'h32: data = 8'h42; // B
      8'h33: data = 8'h48; // H
      8'h34: data = 8'h47; // G
      8'h35: data = 8'h59; // Y
      8'h36: data = 8'h5e; // ^
      8'h37: data = 8'h00; // 
      8'h38: data = 8'h00; // 
      8'h39: data = 8'h00; // 
      8'h3A: data = 8'h4d; // M
      8'h3B: data = 8'h4a; // J
      8'h3C: data = 8'h55; // U
      8'h3D: data = 8'h26; // &
      8'h3E: data = 8'h2a; // *
      8'h3F: data = 8'h00; // 
      8'h40: data = 8'h00; // 
      8'h41: data = 8'h3c; // <
      8'h42: data = 8'h4b; // K
      8'h43: data = 8'h49; // I
      8'h44: data = 8'h4f; // O
      8'h45: data = 8'h29; // )
      8'h46: data = 8'h28; // (
      8'h47: data = 8'h00; // 
      8'h48: data = 8'h00; // 
      8'h49: data = 8'h3e; // >
      8'h4A: data = 8'h3f; // ?
      8'h4B: data = 8'h4c; // L
      8'h4C: data = 8'h3a; // :
      8'h4D: data = 8'h50; // P
      8'h4E: data = 8'h5f; // _
      8'h4F: data = 8'h00; // 
      8'h50: data = 8'h00; // 
      8'h51: data = 8'h00; // 
      8'h52: data = 8'h22; // "
      8'h53: data = 8'h00; // 
      8'h54: data = 8'h7b; // {
      8'h55: data = 8'h2b; // +
      8'h56: data = 8'h00; // 
      8'h57: data = 8'h00; // 
      8'h58: data = 8'h00; // caps lock
      8'h59: data = 8'h00; // rgt shift
      8'h5A: data = 8'h0D; // ent
      8'h5B: data = 8'h7d; // }
      8'h5C: data = 8'h00; // 
      8'h5D: data = 8'h7c; // |
      8'h5E: data = 8'h00; // 
      8'h5F: data = 8'h00; // 
      8'h60: data = 8'h00; // 
      8'h61: data = 8'h00; // 
      8'h62: data = 8'h00; // 
      8'h63: data = 8'h00; // 
      8'h64: data = 8'h00; // 
      8'h65: data = 8'h00; // 
      8'h66: data = 8'h08; // bcksp
      8'h67: data = 8'h00; // 
      8'h68: data = 8'h00; // 
      8'h69: data = 8'h31; // 1
      8'h6A: data = 8'h00; // 
      8'h6B: data = 8'h34; // 4
      8'h6C: data = 8'h37; // 7
      8'h6D: data = 8'h00; // 
      8'h6E: data = 8'h00; // 
      8'h6F: data = 8'h00; // 
      8'h70: data = 8'h30; // 0
      8'h71: data = 8'h2e; // .
      8'h72: data = 8'h32; // 2
      8'h73: data = 8'h35; // 5
      8'h74: data = 8'h36; // 6
      8'h75: data = 8'h38; // 8
      8'h76: data = 8'h1B; // esc
      8'h77: data = 8'h00; // num lock
      8'h78: data = 8'h00; // f11
      8'h79: data = 8'h2b; // +
      8'h7A: data = 8'h33; // 3
      8'h7B: data = 8'h2d; // -
      8'h7C: data = 8'h2a; // *
      8'h7D: data = 8'h39; // 9
      8'h7E: data = 8'h00; // scl lock
      8'h7F: data = 8'h00; // 
      8'h80: data = 8'h00; // 
      8'h81: data = 8'h00; // 
      8'h82: data = 8'h00; // 
      8'h83: data = 8'h00; // f7
      8'h84: data = 8'h00; // 
      8'h85: data = 8'h00; // 
      8'h86: data = 8'h00; // 
      8'h87: data = 8'h00; // 
      8'h88: data = 8'h00; // 
      8'h89: data = 8'h00; // 
      8'h8A: data = 8'h00; // 
      8'h8B: data = 8'h00; // 
      8'h8C: data = 8'h00; // 
      8'h8D: data = 8'h00; // 
      8'h8E: data = 8'h00; // 
      8'h8F: data = 8'h00; // 

      default data = 8'b00000000; // blank
   
   endcase
   
endmodule
