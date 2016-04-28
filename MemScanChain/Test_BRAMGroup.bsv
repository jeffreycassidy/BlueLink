package Test_BRAMGroup;

import BRAMStall::*;
import AlteraM20k::*;
import StmtFSM::*;
import Vector::*;
import MemScanChain::*;
import PAClib::*;

import Assert::*;

module mkTB_BRAMGroup()
    provisos (
        Alias#(addrT,UInt#(8)),
        NumAlias#(nbData,32),
        Mul#(nbData,n,nbGroupData),
        Alias#(dataT,UInt#(nbData)),
        Alias#(groupDataT,Bit#(nbGroupData)),
        NumAlias#(n,4)
        );
    Integer bankDepth = 256;
    Integer depth = bankDepth*valueOf(n);

    Vector#(n,BRAM2PortStall#(addrT,dataT)) br <- replicateM(mkBRAM2Stall(256));

    BRAMPortGroup#(addrT,groupDataT,n,dataT) g <- mkBRAMGroup(map(portA,br));

    Reg#(Bool) groupAutoDeq <- mkReg(False);

    function Action groupRead(addrT addr) = action
        g.grouped.putcmd(False,addr,?);
        $display($time," Group read  address %04X",addr);
    endaction;

    function Action groupWrite(addrT addr,groupDataT data) = action
        g.grouped.putcmd(True,addr,data);
        $display($time," Group write address %04X data %032X",addr,data);
    endaction;

    function Action groupDeq = action
        g.grouped.readdata.deq;
        $display($time," Group deq");
    endaction;

    function Action iRead(Integer i,addrT addr) = action
        g.individual[i].putcmd(False,addr,?);
        $display($time," Individual read block %02X address %08X",i,addr);
    endaction;

    function Action iWrite(Integer i,addrT addr,dataT data) = action
        g.individual[i].putcmd(True,addr,data);
        $display($time," Individual write block %02X address %08X data %032X",i,addr,data);
    endaction;

    function Action iDeq(Integer i) = action
        g.individual[i].readdata.deq;
        $display($time," Individual block %02X deq",i);
    endaction;

    Stmt stim = seq
        g.enableGrouped(True);

        groupWrite(0,128'hffff0003ffff0002ffff0001ffff0000);
        groupRead(0);
        noAction;
        par
            dynamicAssert(g.grouped.readdata.notEmpty,"Missing expected group readdata");
            dynamicAssert(g.grouped.readdata.first == 128'hffff0003ffff0002ffff0001ffff0000,"Data is not as expected");
            groupDeq;
        endpar


        g.enableGrouped(False);

        // do individual reads, checking that striping is reasonable

        action
            for(Integer i=0;i<valueOf(n);i=i+1)
                iRead(i,0);
        endaction
        noAction;

        action
            for(Integer i=0;i<valueOf(n);i=i+1)
                dynamicAssert(g.individual[i].readdata.notEmpty,"Missing expected individual readdata");
        endaction
        
        action
            for(Integer i=0;i<valueOf(n)-1;i=i+1)
                iDeq(i);
        endaction

        action
            for(Integer i=0;i<valueOf(n)-1;i=i+1)
                dynamicAssert(!g.individual[i].readdata.notEmpty,"Unexpected individual readdata");
            dynamicAssert(last(g.individual).readdata.notEmpty,"Missing expected individual readdata");
        endaction
        iDeq(valueOf(n)-1);


        // a series of individual writes, with leading 2 bytes going aaaa, bbbb, cccc, dddd
        // and trailing 2 bytes going 0,1,2,3

        action
            for(Integer i=0;i<valueOf(n);i=i+1)
                iWrite(i,1,32'haaaa0000 | fromInteger(i));
        endaction
        action
            for(Integer i=0;i<valueOf(n);i=i+1)
                iWrite(i,2,32'hbbbb0000 | fromInteger(i));
        endaction
        action
            for(Integer i=0;i<valueOf(n);i=i+1)
                iWrite(i,3,32'hcccc0000 | fromInteger(i));
        endaction
        action
            for(Integer i=0;i<valueOf(n);i=i+1)
                iWrite(i,4,32'hdddd0000 | fromInteger(i));
        endaction

        g.enableGrouped(True);

        groupAutoDeq <= True;

        groupRead(0);
        groupRead(1);
        groupRead(2);
        groupRead(3);
        action
            groupRead(4);
            groupAutoDeq <= False;
        endaction

        repeat(2) noAction;
        groupAutoDeq <= True;

        repeat(10) noAction;
    endseq;

    rule doGroupAutoDeq if (groupAutoDeq);
        groupDeq;
    endrule

    rule showGroupReadIfPresent;
        let v = g.grouped.readdata.first;
        $display($time," Group read data: %032X",v);
    endrule

    for(Integer i=0;i<valueOf(n);i=i+1)
        rule showIndividualReadIfPresent;
            let v = g.individual[i].readdata.first;
            $display($time," Individual read block %02X data: %032X",i,v);
        endrule

    mkAutoFSM(stim);
endmodule

endpackage
