/*
 * host_memcopy.c
 *
 *  Created on: Mar 25, 2015
 *      Author: jcassidy
 */

#include <cinttypes>
#include <boost/random/mersenne_twister.hpp>

#include <boost/align/aligned_allocator.hpp>

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>
#include <boost/range/adaptor/indexed.hpp>

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <iostream>
#include <iomanip>
#include <functional>
#include <fstream>
#include <vector>

#define DEVICE_STRING "/dev/cxl/afu0.0d"

struct MemcopyWED {
	uint64_t	addr_from;
	uint64_t	addr_to;
	uint64_t	size;

	uint64_t	resv[13];
};

#define STATUS_READY 0x1ULL
#define STATUS_WAITING 0x2ULL
#define STATUS_RUNNING 0x3ULL
#define STATUS_DONE 0x4ULL

using namespace std;

int main (int argc, char *argv[])
{
#ifdef HARDWARE
	const bool sim = false;
#else
	const bool sim = true;
#endif
	const size_t Nbytes=65536;
	const size_t Ndw=Nbytes/8;

	// allocate space for input/output/golden
	vector<
		uint64_t,
		boost::alignment::aligned_allocator<uint64_t,128>> golden(Ndw), input(Ndw), output(3*Ndw,0);

	assert(boost::alignment::is_aligned(128,golden.data()));
	assert(boost::alignment::is_aligned(128,input.data()));
	assert(boost::alignment::is_aligned(128,output.data()));


	// generate stimulus
	boost::random::mt19937_64 rng;

	boost::generate(golden, std::ref(rng));
	boost::copy(golden, input.begin());

	ofstream os("golden.hex");
	for(const auto w : golden)
		os << setw(16) << hex << w << endl;
	os.close();

	AFU afu(DEVICE_STRING);

	StackWED<MemcopyWED,128,128> wed;

	wed->addr_from=(uint64_t)input.data();
	wed->addr_to=(uint64_t)(output.data()+Ndw);
	wed->size=Nbytes;

	cout << "From: " << hex << setw(16) << wed->addr_from << endl;
	cout << "  To: " << hex << setw(16) << wed->addr_to << endl;
	cout << "Size: " << hex << setw(16) << wed->size << endl;

	afu.start(wed.get());

	unsigned long long st=0;

	unsigned N;
	for(N=0;N<100 && (st=afu.mmio_read64(0)) != STATUS_WAITING;++N)
	{
		cout << "  Waiting for 'waiting' status (st=" << st << " looking for " << STATUS_WAITING << ")" << endl;
		usleep(sim ? 100000 : 100);
	}

	for(unsigned i=0;i<4;++i)
		cout << "MMIO[" << setw(6) << hex << (i<<3) << "] " << setw(16) << hex << afu.mmio_read64(i<<3) << endl;

	cout << "Starting" << endl;
	afu.mmio_write64(0,0x0ULL);		// start signal: write 0 to MMIO 0

	unsigned timeout=1000;

	for(N=0;N < timeout && (st=afu.mmio_read64(0)) != STATUS_DONE;++N)	// wait for done status
	{
		cout << "  status " << st << endl << flush;
		usleep(sim ? 100000 : 1000);
	}

	if (N == timeout)
		cout << "ERROR: Timeout waiting for done status" << endl;

	cout << "Terminating" << endl;
	afu.mmio_write64(0,0x1ULL);


	bool ok=true;

	// check for correct copy and no corruption
	for(size_t i=0;i<Ndw;++i)
		if (golden[i] != input[i])
		{
			ok = false;
			cerr << "Corrupted input data at " << setw(16) << hex << i << endl;
		}

	size_t i;

	for(i=0; i<Ndw; ++i)
		if (output[i] != 0)
		{
			ok = false;
			cerr << "Corrupted output data at output offset " << setw(16) << i << hex << endl;
		}

	for(;i<2*Ndw;++i)
		if (output[i] != golden[i-Ndw])
		{
			ok = false;
			cerr << "Mismatch at " << setw(16) << hex << i-Ndw << " expecting " << setw(16) << golden[i-Ndw] << " got " << setw(16) << output[i] << endl;
		}

	for(;i<3*Ndw;++i)
		if (output[i] != 0)
		{
			ok = false;
			cerr << "Corrupted output data at output offset " << setw(16) << hex << i << endl;
		}

	// write output data to file
	os.open("output.hex");
	for(size_t i=Ndw; i<2*Ndw; ++i)
		os << setw(16) << hex << output[i] << endl;

	if (ok)
		cout << "Checks passed!" << endl;

	return ok ? 0 : -1;
}
