
module mkTB_AFUWriteBuf();
    WriteBuf#(2) dut <- mkAFUWriteBuf(16);

    function Action testwriteall(RequestTag t, Bit#(1024) data) = action
        $display($time," Writing to tag %d: %64X",t,data[1023:768]);
        $display($time,"                    %64X",data[ 767:512]);
        $display($time,"                    %64X",data[ 511:256]);
        $display($time,"                    %64X",data[ 255:  0]);
        dut.write(t,data);
    endaction;

    function Action testwriteseg(RequestTag t,UInt#(6) seg,Bit#(512) data) = action
        $display($time," Writing to tag %3d offset %3d: %64X",t,seg,data[ 511:256]);
        $display($time,"                                %64X",data[ 255:  0]);
        dut.writeSeg(t,seg,data);
    endaction;

    Reg#(UInt#(16)) i <- mkReg(0);

    Stmt stim = seq

        testwriteall(0,   1024'h0000000000000000000000000000000000000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111111122222222222222222222222222222222222222222222222222222222222222223333333333333333333333333333333333333333333333333333333333333333 );

        testwriteall(2,   1024'hdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadb00faaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa );

        testwriteseg(1,1,512'hcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc);
        noAction;
        testwriteseg(1,0,512'hbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb);
                                
        
        while (i < 16) seq
            action
                let br = BufferReadRequest { brtag: truncate(i>>1), brad: truncate(i%2) };
                $display($time, " Request: ",fshow(br));
                dut.pslin.request.put(br);
            endaction

            action 
                let o = dut.pslin.response;
                $display($time,"  Response: %64X",o[511:256]);
                $display($time,"            %64X",o[255:  0]);
                i <= i + 1;
            endaction
        endseq

        repeat(10) noAction;
    endseq;

    mkAutoFSM(stim);

endmodule

