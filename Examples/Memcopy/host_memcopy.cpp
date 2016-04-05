/*
 * host_memcopy.c
 *
 *  Created on: Mar 25, 2015
 *      Author: jcassidy
 */

#include <cinttypes>
#include <memory>
#include <iostream>

#include <boost/random/mersenne_twister.hpp>

#include <boost/align/aligned_allocator.hpp>

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>
#include <boost/range/adaptor/indexed.hpp>

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <iomanip>
#include <functional>
#include <fstream>
#include <vector>

struct MemcopyWED {
	uint64_t	addr_from;
	uint64_t	addr_to;
	uint64_t	size;

	uint64_t	resv[13];
};

using namespace std;

int main (int argc, char *argv[])
{
	const size_t Nbytes=1024;
	const size_t Ndw=Nbytes/8;

	// allocate space for input/output/golden
	vector<
		uint64_t,
		boost::alignment::aligned_allocator<uint64_t,128>> golden(Ndw), input(Ndw), output(3*Ndw,0);

	assert(boost::alignment::is_aligned(golden.data(),128ULL));
	assert(boost::alignment::is_aligned(input.data(),128ULL));
	assert(boost::alignment::is_aligned(output.data(),128ULL));


	// generate stimulus
	boost::random::mt19937_64 rng;

	boost::generate(golden, std::ref(rng));
	boost::copy(golden, input.begin());

	ofstream os("golden.hex");
	for(const auto w : golden)
		os << setw(16) << hex << w << endl;
	os.close();


	MemcopyWED* w = static_cast<MemcopyWED*>(wed.get());

	w->addr_from=(uint64_t)input.data();
	w->addr_to=(uint64_t)output.data()+Ndw;
	w->size=Nbytes;

	cout << "From: " << hex << setw(16) << w->addr_from << endl;
	cout << "  To: " << hex << setw(16) << w->addr_to << endl;
	cout << "Size: " << hex << setw(16) << w->size << endl;

	afu.start(wed.get());

	cout << "AFU started, waiting 200ms for finish" << endl;

	usleep(200000);
	
	afu.await_event(1000);

	cout << "  WED read completed, checking readback: " << endl;
	for(unsigned i=0;i<8;++i)
		cout << "    AFU MMIO[" << setw(2) << hex << (i<<3) << "]: " << setw(16) << afu.mmio_read64(i<<3) << endl;

	cout << "Sending go signal" << endl;
	afu.mmio_write64(0,0);

	afu.await_event(1000);
	cout << "  copy finished" << endl;


	for(size_t i=0;i<Ndw;++i)
		if (golden[i] != input[i])
			cerr << "Corrupted input data at " << setw(16) << hex << i << endl;

	size_t i;

	for(i=0; i<Ndw; ++i)
		if (output[i] != 0)
			cerr << "Corrupted output data at output offset " << setw(16) << hex << endl;

	for(;i<2*Ndw;++i)
		if (output[i-Ndw] != golden[i])
			cerr << "Mismatch at " << setw(16) << hex << i-Ndx << " expecting " << setw(16) << golden[i] << " got " << setw(16) << output[i-Ndw] << endl;

	for(;i<3*Ndw;++i)
		if (output[i] != 0)
			cerr << "Corrupted output data at output offset " << setw(16) << hex << endl;

	os.open("output.hex");
	for(size_t i=Ndw; i<2*Ndw; ++i)
		os << setw(16) << hex << output[i] << endl;

	return 0;
}
