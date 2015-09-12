#include <cinttypes>
#include <memory>
#include <iostream>

#include <boost/random/mersenne_twister.hpp>

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

#define CACHELINE_BYTES 128

#include <type_traits>

using namespace std;

struct StreamWED {
    void*       src;
    uint64_t    size;

    uint64_t	pad[14];
};

/** AFU-to-host streaming test
 *
 * Passes a pointer and size (N=512=0x200) to the AFU, expecting it to fill the pointer with 32b integers 0..N-1.
 *
 * Verifies:
 * 		Transfer does not time out
 * 		No corruption writes before/after allocated memory
 * 		Correct writes within memory
 *
 */

int main (int argc, char *argv[])
{
	const std::size_t N = 512;
	cout << "Running with N=" << N << endl;

	// set up the receive buffer
	std::vector<uint32_t,aligned_allocator<uint32_t,128>> received(3*N,0);


	// set up WED and attach AFU
	StackWED<StreamWED,128> wed;


	wed->src=received.data()+N;
	wed->size=N*sizeof(uint32_t);

#ifdef HAVE_BOOST_ALIGN
	assert(boost::alignment::is_aligned(CACHELINE_BYTES,received.data()));
	assert(boost::alignment::is_aligned(CACHELINE_BYTES,wed->src));
#endif


	AFU afu(string("/dev/cxl/afu0.0d"));

	afu.start(wed);


	// dump MMIO regs to stdout
	cout << hex << setfill('0');

	for(unsigned i=0;i<4;++i)
		cout << "PSA[" << setw(2) << 8*i << "]=" << setw(16) << afu.mmio_read64(8*i) << endl;


	// start the transfer by writing MMIO dword #4
	afu.mmio_write64(32,0);


	// wait for done signal (MMIO dword #3)
	const unsigned timeout=10;
	bool timedout=false;

	cout << "Waiting for done signal from AFU" << endl;

	unsigned d;
	for(d=0; afu.mmio_read64(24) != 0x1111111111111111 && d < timeout; ++d)
		sleep(1);

	if (d == timeout)
	{
		timedout = true;
		cout << "ERROR: AFU timed out after " << timeout << " seconds" << endl;
	}


	// check for memory corruption
	bool corruption=false, mismatch=false;

	for(unsigned i=0;i<3*N;++i)
	{
		if (N <= i && i < 2*N)
		{
			if (received[i] != (i-N))
			{
				mismatch=true;
				std::cerr << "ERROR: Mismatch, received " << received[i] << " when expecting " << (i-N) << std::endl;
			}

			if (i % 4 == 0)
				cout << i << ": ";
			cout << setfill('0') << setw(8) << hex << received[i] << ' ';

			if(i % 4 == 3)
				cout << endl;
		}
		else if (received[i] != 0)
		{
			corruption = true;
			cout << "ERROR: Corruption write at index " << i << " value " << received[i] << endl;
		}
	}


	for(unsigned i=0;i<4;++i)
		cout << "PSA[" << setw(2) << 8*i << "]=" << setw(16) << afu.mmio_read64(8*i) << endl;

	sleep(1);

	// allow AFU to finish
	afu.mmio_write64(40,0);


	return !(corruption || mismatch || timedout);
}
