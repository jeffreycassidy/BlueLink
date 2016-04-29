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

	const size_t Ndw = 16384;

	// allocate space for input/output/golden
	vector<
		Input,
		boost::alignment::aligned_allocator<Input,128>> input(Ndw,0), output(Ndw,0);

	assert(boost::alignment::is_aligned(128,input.data()));
	assert(boost::alignment::is_aligned(128,output.data()));

	for(unsigned i=0;i<input.size();++i)
		input[i]=0xff00000000000000ULL | i;

	AFU afu(DEVICE_STRING);

	StackWED<MemLoadWED,128,128> wed;

	wed->src=input.data();
	wed->dst=output.data();
	wed->iSize=wed->oSize=input.size()*sizeof(Input);

	cout << "To:   " << hex << setw(16) << wed->dst << endl;
	cout << "Size: " << hex << setw(16) << wed->oSize << endl;
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

	cout << "Starting" << endl;
	afu.mmio_write64(0,0x0ULL);		// start signal: write 0 to MMIO 0

	unsigned timeout=100;

	for(N=0;N < timeout && (st=afu.mmio_read64(0))&0xff != STATUS_DONE;++N)	// wait for done status
	{
		cout << "  status " << st << endl << flush;
		usleep(sim ? 1000000 : 1000);
	}

	if (N == timeout)
		cout << "ERROR: Timeout waiting for done status" << endl;

	cout << "Terminating" << endl;
	afu.mmio_write64(0,0x1ULL);

	for(unsigned i=0;i<Ndw;++i)
		if (output[i] != input[i])
			cout << "ERROR: Memory mismatch at offset " << setw(16) << hex << i << " expecting " << setw(16) << input[i] << " but received " << setw(16) << output[i] << endl;

	return 0;
}
