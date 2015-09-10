#include <cinttypes>
#include <memory>
#include <iostream>

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>
#include <boost/range/adaptor/indexed.hpp>

#ifdef HAVE_BOOST_ALIGN
#include <boost/align/is_aligned.hpp>
#endif

#include <BlueLink/Host/aligned_allocator.hpp>

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <iomanip>
#include <vector>
#include <fstream>
#include <cstdlib>

#define CACHELINE_BYTES 128

#include <type_traits>



#include <boost/version.hpp>

#include "BitPackUnpack/BitUnpacker.hpp"
#include "BitPackUnpack/BDPIAutoArrayBitPacker.hpp"
#include "BitPackUnpack/ConstGMPArray.hpp"

#include "BitPackUnpack/Types/std_pair.hpp"
#include "BitPackUnpack/Types/std_tuple.hpp"
#include "BitPackUnpack/Types/std_array.hpp"
#include "BitPackUnpack/Types/std_bool.hpp"
#include "BitPackUnpack/Types/FixedInt.hpp"
#include "BitPackUnpack/Types/Pad.hpp"

#include "FixedInt.hpp"
#include "FixedPoint.hpp"

using namespace std;

struct StreamWED {
	void*       init;
	void*       src;
	void*       dest;
    uint64_t    init_size;
	uint64_t    src_size;
	uint64_t    dest_size;
};


void fill_init_buffer(uint32_t* buffer, unsigned Nb, uint32_t size, string file_name) {
	ifstream fstream(file_name);
	BDPIAutoArrayBitPacker packer(Nb, &buffer[0]);
	
	for (int i = 0; i < size; ++i) {
		float temp;
		FixedInt<unsigned,4> extra_bits(0);
		fstream >> temp;
		FixedPoint<unsigned,3,17> ni_by_nt(temp);
		fstream >> temp;
		FixedPoint<unsigned,3,17> nt_by_ni(temp);
		fstream >> temp;
		FixedPoint<unsigned,2,18> cos_crit(temp);

		packer & extra_bits & ni_by_nt & nt_by_ni & cos_crit;
	}
	cout << setw(8) << hex << packer.value() << endl;
	//packer should populate buffer once it's deleted
}

void fill_src_buffer(uint32_t* buffer, unsigned Nb, uint32_t size, string input_file, string rng_file) {

  ifstream fstream(input_file);
  ifstream rngstream(rng_file);
  BDPIAutoArrayBitPacker packer(Nb, &buffer[0]);

	for (int i = 0; i < size; ++i) {
		float temp;
		unsigned temp_int;
		FixedInt<unsigned,4> extra_bits(0);
		fstream >> temp;
		FixedPoint<signed,3,17> vNorm_i(temp);
		fstream >> temp;
		FixedPoint<signed,3,17> vNorm_j(temp);
		fstream >> temp;
		FixedPoint<signed,3,17> vNorm_k(temp);
		fstream >> temp;
		FixedPoint<signed,3,17> vIn_i(temp);
		fstream >> temp;
		FixedPoint<signed,3,17> vIn_j(temp);
		fstream >> temp;
		FixedPoint<signed,3,17> vIn_k(temp);
		fstream >> temp;
		FixedPoint<unsigned,2,18> cos_i(temp);
		rngstream >> temp;
		FixedPoint<unsigned,2,18> rand_num(temp);
		fstream >> temp_int;
		FixedInt<unsigned,20> index(temp_int);

		packer & extra_bits & vNorm_i & vNorm_j & vNorm_k;
		packer & extra_bits & vIn_i & vIn_j & vIn_k;
		packer & extra_bits & cos_i & rand_num & index;
	}
	cout << setw(8) << hex << packer.value() << endl;
}


int main () {

	std::vector<char,aligned_allocator<char,128>> v(1,0);

	StackWED<StreamWED,128> wed;

	//cacheline is 1024 bits, so for an array of 32 bit ints, keep them as multiples of 32 for whole cachelines;
	const std::size_t N = 32;

	cout << "Running with N=" << N << endl;

	// set up the receive buffer
	std::vector<uint32_t,aligned_allocator<uint32_t,128>> init_buf(N,0), src_buf(3*N,0), dest_buf(3*N,0);

#ifdef HAVE_BOOST_ALIGN
	assert(boost::alignment::is_aligned(CACHELINE_BYTES,init_buf.data()));
	assert(boost::alignment::is_aligned(CACHELINE_BYTES,src_buf.data()));
	assert(boost::alignment::is_aligned(CACHELINE_BYTES,dest_buf.data()));
#endif
   
	fill_init_buffer(init_buf.data(), N*32, 6, "interfaceID.18bits.txt");
	fill_src_buffer(src_buf.data(), 3*N*32, 16, "input.18bits.txt", "output.rng.txt");

	wed->init = init_buf.data();
	wed->src = src_buf.data();
	wed->dest = dest_buf.data();
	wed->init_size = N*sizeof(uint32_t);
	wed->src_size = 3*N*sizeof(uint32_t);
	wed->dest_size = 3*N*sizeof(uint32_t);

	AFU afu(string("/dev/cxl/afu0.0d"));

	afu.start(wed);

	for(unsigned i=0;i<4;++i)
		cout << "PSA[" << setw(2) << 8*i << "]=" << setw(16) << afu.mmio_read64(8*i) << endl;

	afu.mmio_write64(32,0); //start the afu

	const unsigned timeout=10;

	unsigned d;
	for(d=0; afu.mmio_read64(24) != 0x1111111111111111 && d < timeout; ++d)
		sleep(1);

	if (d == timeout)
		cout << "ERROR: AFU timed out after " << timeout << " seconds" << endl;

	cout << "Host code awake again, checking: " << endl;

    for (auto& value : dest_buf) {
	  cout << hex << setw(16) << value << endl;
	}

	BitUnpacker<ConstGMPArray> unpacker(3*N*32, dest_buf.data());

	ofstream ostream("refref.afu.out");

	for (int i = 0; i < 48; ++i) {

	  
	  //array would be in reverse order
	  std::array<FixedPoint<signed,3,17>,3> vOut;
	  FixedInt<unsigned,4> extra_bits;	  
	  /*FixedPoint<signed,3,17> vOut_i;
	  FixedPoint<signed,3,17> vOut_j;
	  FixedPoint<signed,3,17> vOut_k;
	  unpacker & vOut_k & vOut_j & vOut_i & extra_bits;*/
	  unpacker & vOut & extra_bits;

	  cout << extra_bits.value() << " " << (float)vOut[0] << " " << (float)vOut[1] << " " << (float)vOut[2] << endl;
	  //cout << hex << setw(5) << extra_bits.value() << " " << vOut_i.value() << " " << vOut_j.value() << " " << vOut_k.value() << endl;
	}
	
	afu.mmio_write64(40,0); //start the afu
}
