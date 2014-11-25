// This package is part of BlueLink, a Bluespec library supporting the IBM CAPI coherent POWER8-FPGA link
// github.com/jeffreycassidy/BlueLink
//
// Copyright 2014 Jeffrey Cassidy
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package Parity;

// Defines some basic data types for manipulating parity-protected data words and structures
// typeclass Parity#(data_t,parity_t)   permits definition of parity types (eg OddParity) and their associated calculation
// typeclass ParityStruct#(data_t,parity_struct_t) allows definitions of structures containing parity words

import FShow::*;
import Vector::*;




/** Typeclass for parity calculation; parity function to apply is implicit in the return type
 * eg. if you do OddParity b = parity(32'hdeadbeef) it knows to use the instance for Parity#(Bit#(32),OddParity)
 */

typeclass Parity#(type data_t,type parity_t) provisos (Eq#(parity_t));
    function parity_t parity(data_t i);                                     // return the calculated parity for data
endtypeclass




/** Typeclass for creating/accessing a struct with multiple parity-protected elements
 * Also has related non-typeclass functions:
 *  parity_calc(data_t i)           Returns a parity structure with calculated correct parity
 *  parity_x(data_t i)              Gives parity struct with X parity
 *  parity_maybe(parity_struct_t p) Returns Maybe#(data_t): tagged Valid data if parity OK, else tagged Invalid
 *          
 */

typeclass ParityStruct#(type data_t,type parity_struct_t) dependencies (parity_struct_t determines data_t);
    function parity_struct_t make_parity_struct(Bool pargen,data_t i);      // convert to (pargen=True -> calculate parity, else X)
    function data_t          ignore_parity(parity_struct_t p);              // strip out the parity bits
    function Bool            parity_ok(parity_struct_t p);                  // return True if parity OK
endtypeclass

function parity_struct_t parity_calc(data_t i) provisos (ParityStruct#(data_t,parity_struct_t))
    = make_parity_struct(True, i);

function parity_struct_t parity_x   (data_t i) provisos (ParityStruct#(data_t,parity_struct_t))
    = make_parity_struct(False,i);

function Maybe#(data_t)  parity_maybe (Bool check_parity,parity_struct_t p) provisos (ParityStruct#(data_t,parity_struct_t))
    = !check_parity || parity_ok(p) ? tagged Valid ignore_parity(p) : tagged Invalid;




/** Data structure representing a data word protected by parity bits (as a Parity#() instance)
 * FShow instance displays the contents of a ParityStruct, including parity bits and results of a parity check
 * format is <FShow#(data_t)> [parity 'h<parity value> <OK|ERR>]
 */

typedef struct {
    data_t      data;
    parity_t    parityval;
} DataWithParity#(type data_t,type parity_t) deriving (Bits);


instance ParityStruct#(data_t,DataWithParity#(data_t,parity_t)) provisos (Parity#(data_t,parity_t),Bits#(data_t,nd));
    function DataWithParity#(data_t,parity_t) make_parity_struct(Bool pargen,data_t i) =
        DataWithParity { data: i, parityval: pargen ? parity(i) : ? };

    function data_t ignore_parity(DataWithParity#(data_t,parity_t) p) = p.data;
    function Bool parity_ok(DataWithParity#(data_t,parity_t) p) = p.parityval == parity(p.data);
endinstance

instance FShow#(DataWithParity#(data_t,parity_t)) provisos
    (FShow#(data_t), Parity#(data_t,parity_t), Bits#(data_t,nd), Bits#(parity_t,np));
    function Fmt fshow(DataWithParity#(data_t,parity_t) i) = fshow(i.data) + fshow(" [parity ") + fshow(pack(i.parityval)) +
        fshow(parity_ok(i) ? " OK ]" : " ERR]");
endinstance




/** Simple odd parity
 *
 */

typedef struct {
    Bit#(1) pbit;
} OddParity deriving(Bits,Eq,Literal);

instance Parity#(data_t,OddParity) provisos (Bits#(data_t,nb));
    function OddParity parity(data_t i) = OddParity { pbit: reduceXnor(pack(i)) };
endinstance




/** Word-wise parity
 * 
 * Type parameters
 *      np          Number of parity bits (np*nbw must equal bit length)
 *      parity_t    Parity function to apply
 */

typedef struct {
    Vector#(np,parity_t) pvec;
} WordWiseParity#(numeric type np,type parity_t) deriving(Bits,Eq);

instance Parity#(data_t,WordWiseParity#(np,parity_t)) provisos (
    Bits#(data_t,nb),Mul#(nbw,np,nb),Parity#(Bit#(nbw),parity_t));

    function WordWiseParity#(np,parity_t) parity(data_t i);
        Vector#(np,Bit#(nbw)) b = reverse(unpack(pack(i)));
        return WordWiseParity { pvec: map(parity,b) };
    endfunction
endinstance



endpackage
