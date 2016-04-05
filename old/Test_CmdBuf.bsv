package Test_CmdBuf;

import PSLTypes::*;
import CmdBuf::*;
import ClientServer::*;
import BLProgrammableLUT::*;
import Vector::*;

import StmtFSM::*;


module mkTB_CmdBuf() provisos (NumAlias#(nclient,4));

	CacheCmdBuf#(4,2) dut <- mkCmdBuf(16);

	Vector#(nclient,RWire#(CmdWithoutTag)) clientCmd <- replicateM(mkRWire);

	for(Integer i=0;i<4;i=i+1)
	begin
		rule tryPutCmd if (clientCmd[i].wget matches tagged Valid .c);
			let t <- dut.client[i].putcmd(c);
			$display($time,": Client %d granted tag %d",i,t);
		endrule

		rule getResponse;
			let resp <- dut.client[i].response.get;
			$display($time,": Client %d received response ",i,fshow(resp));
		endrule
	end

	function Action tryRead(Integer i,EAddress64 addr) = action
		clientCmd[i].wset(CmdWithoutTag { com: Read_cl_s, cea: addr, cabt: Strict, csize: 128 });
	endaction;


	function Action sendDone(RequestTag t) = action
		$display($time,": Sent response for tag %d",t);
		dut.psl.response.put(CacheResponse { response: Done, rtag: t, rcredits: 0, rcachepos: 0, rcachestate: 0 });
	endaction;


	Stmt stim = seq

		action
			tryRead(0,64'h0);
			tryRead(1,64'h0);
			tryRead(2,64'h0);
			tryRead(3,64'h0);
		endaction

		action
			tryRead(0,64'h0);
			tryRead(1,64'h0);
			tryRead(2,64'h0);
			tryRead(3,64'h0);
		endaction

		action
			tryRead(0,64'h0);
			tryRead(1,64'h0);
			tryRead(2,64'h0);
			tryRead(3,64'h0);
		endaction

		action
			tryRead(0,64'h0);
			tryRead(1,64'h0);
			tryRead(2,64'h0);
			tryRead(3,64'h0);
		endaction
		
		action
			tryRead(0,64'h0);
			tryRead(1,64'h0);
			tryRead(2,64'h0);
			tryRead(3,64'h0);
		endaction

		repeat(20) tryRead(1,64'hffffffffffffffff);

		sendDone(0);

		noAction;

		action
			tryRead(0,64'h0);
			tryRead(1,64'h0);
			tryRead(2,64'h0);
			tryRead(3,64'h0);
		endaction

		sendDone(15);


		repeat(10) noAction;
	endseq;

	mkAutoFSM(stim);

	function Maybe#(t) doWGet(RWire#(t) rw) = rw.wget;

	rule showRequest if (any(isValid,map(doWGet,clientCmd)));
		$write($time,": Request from clients ");
		for(Integer i=0;i<valueOf(nclient);i=i+1)
			if (isValid(clientCmd[i].wget))
				$write("%3d",i);
			else
				$write("   ");
		$display;
	endrule

	rule showCmdIssued;
		let cmd <- dut.psl.request.get;
		$display($time," Command issued: ",fshow(cmd));
	endrule

endmodule

endpackage
