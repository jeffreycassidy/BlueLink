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

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>
#include <boost/range/adaptor/indexed.hpp>


#include "AFU.hpp"
#include "WED.hpp"

#include <iomanip>
#include <vector>


#define CACHELINE_BYTES 128

#define AFU_MMIO_REG_SIZE 0x4000000
#define MMIO_TRACE_ADDR   0x3FFFFF8


struct MemcopyWED {
	uint64_t	addr_from;
	uint64_t	addr_to;
	uint64_t	size;

	uint64_t	resv[13];
};

//cxl_mmio_write64(afu_h,MMIO_TRACE_ADDR,trace_id)
//cxl_mmio_read64(afu_h,MMIO_TRACE_ADDR)
//
//struct alignas(128) wed {
//	__u64	from;
//	__u64	to;
//	__u64	size;
//};
//
//class WED {
//
//public:
//	static WED* New();
//
//private:
//	WED();			// make default constructor invisible
//};
//
//static WED* WED::New()
//{
//
//}
//
//class MemcopyWED : public WED
//{
//
//
//};

using namespace std;

using boost::begin;
using boost::end;

using boost::adaptors::indexed;

int main (int argc, char *argv[])
{
	const size_t Nbytes=1024;
	const size_t Ndw=Nbytes/8;
	WED wed;

	boost::random::mt19937_64 rng;

	//vector<uint64_t> golden(Nbytes/8,0),idata(Nbytes/8,0),odata(Nbytes/8,0);

	uint64_t *golden,*idata,*odata;

	int ret = posix_memalign((void**)&golden,128,6*Nbytes);
	assert(!ret);

	idata=golden+2*Nbytes/8;
	odata=golden+4*Nbytes/8;

	for(size_t i=0; i<6*Ndw; ++i)
		golden[i]=0;

	generate(golden, golden+Ndw, rng);

	copy(golden, golden+Ndw, idata);

	for(size_t i = 0; i<Ndw; ++i)
	{
		if (i % 4 == 0)
			cout << endl << setw(4) << hex << (i<<3);
		cout << "  " << right << setw(16) << hex << idata[i];
	}
	cout << endl;

	AFU afu(string("dev/cxl/afu0.0"));


	MemcopyWED* w = static_cast<MemcopyWED*>(wed.get());

	w->addr_from=(uint64_t)idata;
	w->addr_to=(uint64_t)odata;
	w->size=Nbytes;

	cout << "From: " << hex << setw(16) << w->addr_from << endl;
	cout << "  To: " << hex << setw(16) << w->addr_to << endl;
	cout << "Size: " << hex << setw(16) << w->size << endl;

	afu.start(wed);

	afu.await_event();

	//afu.wait_finish();

	for(size_t i=Ndw; i<2*Ndw; ++i)
		if (golden[i] != 0)
			cerr << "Corruption write at " << i << endl;

	for(size_t i=3*Ndw; i<4*Ndw; ++i)
			if (golden[i] != 0)
				cerr << "Corruption write at " << i << endl;

	for(size_t i=5*Ndw; i<6*Ndw; ++i)
			if (golden[i] != 0)
				cerr << "Corruption write at " << i << endl;

	for(size_t i=0; i<Ndw; i += 4)
	{
		bool match=true;
		for(size_t j=i; j<i+4; ++j)
			match &= golden[j]==odata[j];

		cout << setw(4) << hex << i << ": ";

		if (match)
		{
			cout << "      OK";
			for(size_t j=i; j<i+4; ++j)
				cout << "  " << setw(16) << setfill('0') << odata[j];
		}
		else
		{
			cout << "Expected";
			for (size_t j=i; j<i+4; ++j)
				cout << "  " << setw(16) << setfill('0') << golden[j];
			cout << endl << "    Received";
			for(size_t j=i; j<i+4; ++j)
				cout << "  " << setw(16) << setfill('0') << odata[j];
		}
		cout << endl << endl;
	}

//  while (wed0->major==0xFFFF) {
//    struct timespec ts;
//    ts.tv_sec = 0;
//    ts.tv_nsec = 100;
//    nanosleep(&ts, &ts);
//    if (clock_gettime(CLOCK_REALTIME, &now) == -1) {
//      perror("clock_gettime");
//      return -1;
//    }
//    time_passed = (now.tv_sec - start.tv_sec) +
//		   (double)(now.tv_nsec - start.tv_nsec) /
//		   (double)(1000000000L);
//    if (((int) time_passed) > timeout)
//      break;
//  }


  return 0;
}
