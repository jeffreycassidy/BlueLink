/*
 * BlockRAMGroupTest.cpp
 *
 *  Created on: Apr 28, 2016
 *      Author: jcassidy
 */

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <boost/align/aligned_allocator.hpp>

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>

#include <iostream>
#include <iomanip>
#include <functional>
#include <fstream>
#include <vector>

#ifndef DEVICE_STRING
#define DEVICE_STRING "/dev/cxl/afu0.0d"
#endif

struct MemLoadWED {
	void* dst;
	uint64_t	oSize;
	const void*	src;
	uint64_t	iSize;

	uint64_t	resv[12];
};

#define STATUS_READY 0x1ULL
#define STATUS_WAITING 0x2ULL
#define STATUS_RUNNING 0x3ULL
#define STATUS_DONE 0x4ULL

using namespace std;

typedef uint64_t Input;

int main(int argc,char **argv)
{
#ifdef HARDWARE
	const bool sim = false;
#else
	const bool sim = true;
#endif

	const size_t Ndw = argc > 1 ? atoi(argv[1]) : 32768;

	// allocate space for input/output/golden
	vector<
		Input,
		boost::alignment::aligned_allocator<Input,128>> input(Ndw,0);

	assert(boost::alignment::is_aligned(128,input.data()));

	for(unsigned i=0;i<input.size();++i)
		input[i]=0xff00000000000000ULL | i;

	AFU afu(DEVICE_STRING);

	StackWED<MemLoadWED,128,128> wed;

	wed->src=input.data();
	wed->iSize=input.size()*sizeof(Input);
	wed->dst=nullptr;
	wed->oSize=0;

	cout << "From: " << hex << setw(16) << wed->src << endl;
	cout << "Size: " << hex << setw(16) << wed->iSize << endl;

	afu.start(wed.get());

	unsigned long long st=0;

	unsigned N;
	for(N=0;N<100 && (st=afu.mmio_read64(0))&0xff != STATUS_WAITING;++N)
	{
		cout << "  Waiting for 'waiting' status (st=" << st << " looking for " << STATUS_WAITING << ")" << endl;
		usleep(sim ? 100000 : 100);
	}
//
//	for(unsigned i=0;i<4;++i)
//		cout << "MMIO[" << setw(6) << hex << (i<<3) << "] " << setw(16) << hex << afu.mmio_read64(i<<3) << endl;

	cout << "Starting" << endl;
	afu.mmio_write64(0,0x0ULL);		// start signal: write 0 to MMIO 0

	unsigned timeout=1000;

	for(N=0;N < timeout && (st=afu.mmio_read64(0))&0xff != STATUS_DONE;++N)	// wait for done status
	{
		cout << "  status " << st << endl << flush;
		usleep(sim ? 100000 : 1000);
	}

	if (N == timeout)
		cout << "ERROR: Timeout waiting for done status" << endl;

	cout << "Terminating" << endl;
	afu.mmio_write64(0,0x1ULL);

	return 0;
}

