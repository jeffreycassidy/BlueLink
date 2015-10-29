package Endianness;

import Vector::*;

/* Endianness utility functions.
 *
 * For IBM CAPI interface:
 *      increasing brad/bwad is increasing memory address
 *      within each line, leftmost byte comes from the low address
 *      P8 processor in little-endian mode
 *      { bwdata[0], bwdata[1] } is always a contiguous 1024b word from memory
 *
 * But in Bluespec:
 *      vectors are stored in descending index order (MSB/L to LSB/R): v[N-1] v[N-2] .. v[1] v[0]
 *      structs & tuples pack first element at MSB
 *      bit indexing is always downto, with MSB at left
 *
 * Consequently:
 *      reading contiguous 1024b lines as a 2-vector of Bit#(512) requires swapping ( bwad0 -> v[1], bwad1 -> v[0]), after which
 *      v[1] MS byte is lowest memory address in the line
 *      v[0] LS byte is highest memory address in the line
 *      pack(v) runs from lowest to highest memory address
 *      multi-byte word order is little-endian
 *  
 *      Order of elements in host struct and Bluespec struct/tuple are same
 *      Order of vectors stored in host are _reversed_ wrt Bluespec
 */



/** Perform endian swap (byte reverse) on an 8N-bit vector */
function Bit#(n) endianSwap(Bit#(n) i) provisos (Mul#(nbytes,8,n),Div#(n,8,nbytes),Log#(nbytes,k));
    Vector#(nbytes,Bit#(8)) t = toChunks(i);
    return pack(reverse(t));
endfunction



/** Struct wrapper for little-endian multi-byte quantities */
typedef struct {
    t _payload;
} LittleEndian#(type t) deriving (Eq);

instance Bits#(LittleEndian#(t),nb)
    provisos (
        Bits#(t,nb),
        Mul#(nbytes,8,nb),
        Div#(nb,8,nbytes));

    function Bit#(nb) pack(LittleEndian#(t) i);
        return endianSwap(pack(i._payload));
    endfunction

    function LittleEndian#(t) unpack(Bit#(nb) b);
        return LittleEndian { _payload: unpack(endianSwap(b))};
    endfunction
endinstance

function t unpackle(LittleEndian#(t) le)
    provisos (
        Bits#(t,nb),
        Mul#(nbytes,8,nb),
        Div#(nb,8,nbytes))
    = le._payload;

function LittleEndian#(t) packle(t i)
    provisos (
        Bits#(t,nb),
        Mul#(nbytes,8,nb),
        Div#(nb,8,nbytes))
    = LittleEndian { _payload: i };



typedef enum {
    HostNative,
    /*
     * Does not perform an endian swap on the cache line. On LE hosts, cache lines are 1024b LE bit vectors (opposite to Bluespec).
     * C/C++ struct elements will appear in normal (declaration) order, but multi-byte elements will need to be endian-reversed
     * when used in Bluespec code.
     * Items packed into a BDPIBitPacker will appear in reverse order with incorrect endianness.
     */

    EndianSwap
    /* 
     * Performs an endian swap on the entire 1024b cache line.
     * Typically, this will convert a 1024b LE host cache line into a 1024b BE bit vector suitable for use in Bluespec.
     * 
     * Elements in C/C++ structs appear in reverse order, but their multi-byte elements do not need any manipulation before use.
     * Items packed into a BDPIBitPacker appear in standard left to right order with correct endiannness.
     * 
     * NOTE: When packing C/C++ structs, do not forget that padding elements (including implicit padding at end of struct) are 
     * reversed too, ie. if a struct declares X bytes but has an alignment of Y, there are Y-X bytes of padding implicitly.
     */
} EndianPolicy deriving(Eq);




/* SegReg
 *
 * A segmented register, accessible either as a whole (r.entire) or in segments (r.seg[N])
 * Segment addressing is direct, ie. no endian swap and the index corresponds to brad/bwad.
 *
 * Entire-register read/write may implement an endian swap, depending on module arguments.
 */

interface SegReg#(type t,numeric type ns,numeric type nbs);
    interface Vector#(ns,Reg#(Bit#(nbs))) seg;

    interface Reg#(t) entire;
endinterface


module mkSegReg#(EndianPolicy endianPolicy,t init)(SegReg#(t,ns,nbs))
    provisos (
        Div#(nb,8,nbytes),
        Mul#(nbytes,8,nb),
        Div#(nb,nbs,ns),
        Mul#(ns,nbs,nb),
        Bits#(t,nb));

    Vector#(ns,Bit#(nbs)) initChunks = reverse(toChunks(pack(init)));

    // seg corresponds to bwad/brad index (increasing bwad/brad -> increasing address)
    Vector#(ns,Reg#(Bit#(nbs))) r <- genWithM(compose(mkReg,select(initChunks)));

    // need to reverse host (LE) bwad/brad order to get contiguous BSV (BE) bit vector
    Vector#(ns,Reg#(Bit#(nbs))) rRev  = reverse(r);

    interface Vector seg = r;

    interface Reg entire;
        method Action _write(t i) = writeVReg(rRev,toChunks(
            case (endianPolicy) matches
                HostNative:     pack(i);
                EndianSwap:     endianSwap(pack(i));
            endcase));

        method t _read = unpack(
            case (endianPolicy) matches
                HostNative:     pack(readVReg(rRev));
                EndianSwap:     endianSwap(pack(readVReg(rRev)));
            endcase);
    endinterface
endmodule

endpackage
