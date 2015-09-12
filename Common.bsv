package Common;

import GetPut::*;
import Vector::*;

/** Unifying interface for all things that can be read (and Vectors thereof): Reg, ReadOnly, PulseWire
 * Can be handy when using map.
 * 
 */

typeclass Readable#(type ifc_t,type t) dependencies (ifc_t determines t);
    function t read(ifc_t ifc);
endtypeclass

instance Readable#(Vector#(n,ifc_t),Vector#(n,t)) provisos (Readable#(ifc_t,t));
    function Vector#(n,t) read(Vector#(n,ifc_t) ifc) = map(read,ifc);
endinstance

instance Readable#(PulseWire,Bool);
    function Bool read(PulseWire pw) = pw._read;
endinstance

instance Readable#(Reg#(t),t);
    function t read(Reg#(t) r) = r._read;
endinstance

instance Readable#(ReadOnly#(t),t);
    function t read(ReadOnly#(t) r) = r._read;
endinstance


/** Conversion to WriteOnly */

function WriteOnly#(t) regToWriteOnly(Reg#(t) r) = interface WriteOnly;
    method Action _write(t i) = r._write(i);
endinterface;


/** Get/Put instances for registers with data wrapped in Maybe#(); useful typically for DReg.
 */

instance ToPut#(Reg#(Maybe#(t)),t) provisos (Bits#(t,n));
    function Put#(t) toPut(Reg#(Maybe#(t)) r) = interface Put;
        method Action put(t i) = r._write(tagged Valid i);
    endinterface;
endinstance

instance ToGet#(Reg#(Maybe#(t)),t) provisos (Bits#(t,n));
    function Get#(t) toGet(Reg#(Maybe#(t)) r) = interface Get;
        method ActionValue#(t) get if (r._read matches tagged Valid .v) = actionvalue return v; endactionvalue;
    endinterface;
endinstance

function ReadOnly#(t) readIfValid(Maybe#(t) o) = interface ReadOnly;
    method t _read if (o matches tagged Valid .v) = v;
endinterface;

endpackage
