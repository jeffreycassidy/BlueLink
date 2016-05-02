package BlockMapPassthrough;

import MMIO::*;
import FIFO::*;
import ClientServer::*;
import Endianness::*;


import BlockMapAFU::*;


module mkBlockMapPassthrough(BlockMapAFU#(Bit#(512),Bit#(512)));
    FIFO#(Bit#(512)) f <- mkFIFO;
    FIFO#(Bit#(64)) mmResp <- mkFIFO1;

    interface Server stream;
        interface Put request;
            method Action put(Bit#(512) id);
                $display($time," INFO: mkPassThrough received data");
                for(Integer i=7;i>=0;i=i-1)
                begin
                    $write("%016X ",endianSwap((Bit#(64))'(id[i*64+63:i*64])));
                    if (i % 4 == 0)
                    begin
                        $display;
                        if (i > 0)
                            $write("                                       ");
                    end
                end
                f.enq(id);
            endmethod
        endinterface

        interface Get response = toGet(f);
    endinterface

    interface Server mmio;
        interface Put request;
            method Action put(MMIORWRequest req);
                mmResp.enq(64'h0);
                $display($time," INFO: mkPassThrough received MMIO request ",fshow(req));
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Bit#(64)) get;
                mmResp.deq;
                return mmResp.first;
            endmethod
        endinterface
    endinterface
endmodule

endpackage
