// Connects the AFU to the PSL with a SnoopConmnection (prints all events to stdout)

package Test_Memcopy;

import PSLTypes::*;
import Connectable::*;
import PSLInterface::*;
import Memcopy::*;
import SnoopConnection::*;

module mkMemcopyTB();
	AFU#(1) afu <- mkMemcopy;
	let 	psl <- mkPSL(afu.description);

	mkSnoopConnection("PSL",psl,"AFU",afu);
endmodule

endpackage
