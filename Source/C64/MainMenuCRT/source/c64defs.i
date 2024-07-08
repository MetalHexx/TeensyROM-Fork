; MIT License
; 
; Copyright (c) 2023 Travis Smith
; 
; Permission is hereby granted, free of charge, to any person obtaining a copy of this software 
; and associated documentation files (the "Software"), to deal in the Software without 
; restriction, including without limitation the rights to use, copy, modify, merge, publish, 
; distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom 
; the Software is furnished to do so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be included in all copies or 
; substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING 
; BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
; DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


   ;System Mem locations
   C64ScreenRAM       = $0400  ;$5c00  ; to screen memory
   BorderColorReg     = $d020 
   BackgndColorReg    = $d021
   SIDLoc             = $d400
   C64ColorRAM        = $d800  ; color memory (fixed)
   IO1Port            = $de00
   GamePort2          = $dc00
   GamePort1          = $dc01   
   TODHoursBCD        = $dc0b
   TODMinBCD          = $dc0a
   TODSecBCD          = $dc09
   TODTenthSecBCD     = $dc08
   CIA1TimerA_Lo      = $dc04
   CIA1TimerA_Hi      = $dc05
  
   ;Kernal routines:
   IRQDefault = $ea31
   SendChar   = $ffd2
   ScanKey    = $ff9f ;SCNKEY
   GetIn      = $ffe4 ;GETIN
   SetCursor  = $fff0 ;PLOT
   
   ;BASIC routines:
   ;BasicColdStartVect = $a000 ; $e394  58260
   BasicWarmStartVect = $a002 ; $e37b  58235
   ;PrintString =  $ab1e

   ;Koala image file mem/offsets
   ;File preceded by 2 byte for address: 00 60 ...
   KLAStart     = $2000            ; $2711 (10,001) bytes, last is KLAStart+$2710
   KLAScreenRAM = KLAStart + 8000  ;($1f40=8000) 1k of multi-color data 
   KLAColorRAM  = KLAStart + 9000  ;($2328=9000) 1k of color data 
   KLABackground= KLAStart + 10000 ;($2710=10000) Background color
   ARTBorder    = KLAStart + 9000  ;($2328=9000)  Border color for hi-res files

   ;chr$ symbols
   ChrBlack    = 144
   ChrWhite    = 5
   ChrRed      = 28
   ChrCyan     = 159
   ChrPurple   = 156
   ChrGreen    = 30
   ChrBlue     = 31
   ChrYellow   = 158 
   ChrOrange   = 129
   ChrBrown    = 149
   ChrLtRed    = 150
   ChrDrkGrey  = 151
   ChrMedGrey  = 152
   ChrLtGreen  = 153
   ChrLtBlue   = 154
   ChrLtGrey   = 155
               
   ChrF1       = 133
   ChrF2       = 137
   ChrF3       = 134
   ChrF4       = 138
   ChrF5       = 135
   ChrF6       = 139
   ChrF7       = 136
   ChrF8       = 140
   ChrToLower  = 14
   ChrToUpper  = 142
   ChrRvsOn    = 18
   ChrRvsOff   = 146
   ChrClear    = 147
   ChrReturn   = 13
   ChrSpace    = 32
   ChrCRSRUp   = 145
   ChrCRSRDn   = 17
   ChrCRSRLeft = 157
   ChrCRSRRight= 29
   ChrUpArrow  = 94
   ChrLeftArrow= 95
   ChrHome     = 19
   ChrFillLeft = 181
   ChrFillRight= 182
 
;Poke colors
   PokeBlack   = 0
   PokeWhite   = 1
   PokeRed     = 2
   PokeCyan    = 3
   PokePurple  = 4
   PokeGreen   = 5
   PokeBlue    = 6
   PokeYellow  = 7
   PokeOrange  = 8
   PokeBrown   = 9
   PokeLtRed   = 10
   PokeDrkGrey = 11
   PokeMedGrey = 12
   PokeLtGreen = 13
   PokeLtBlue  = 14
   PokeLtGrey  = 15


