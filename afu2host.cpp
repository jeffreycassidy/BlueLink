#include <cinttypes>
#include <memory>
#include <iostream>

#include <boost/random/mersenne_twister.hpp>

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>
#include <boost/range/adaptor/indexed.hpp>


#include <boost/align/is_aligned.hpp>

#include "aligned_allocator.hpp"


#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <iomanip>
#include <vector>
#include <fstream>

#define CACHELINE_BYTES 128

#include <type_traits>

using namespace std;

struct StreamWED {
    void*       src;
    uint64_t    size;
};


int main (int argc, char *argv[])
{
	std::vector<char,aligned_allocator<char,128>> v(1,0);

	StackWED<StreamWED,128> wed;

	const std::size_t N = argc > 1 ? atoi(argv[1]) : 256;

	cout << "Running with N=" << N << endl;

	// set up the receive buffer
	std::vector<uint64_t,aligned_allocator<uint64_t,128>> received(3*N,0),expected(N,0);

	boost::random::mt19937 rng;
	boost::generate(expected,rng);

	{
		ofstream os("seq.expected.out");
		for(const auto x : expected)
			os << setfill('0') << uppercase << hex << setw(8) << x << endl;
	}

	wed->src=received.data()+N;
	wed->size=N*sizeof(uint64_t);

	assert(boost::alignment::is_aligned(CACHELINE_BYTES,received.data()));
	assert(boost::alignment::is_aligned(CACHELINE_BYTES,wed->src));


#ifdef HARDWARE
	AFU afu(string("/dev/cxl/afu0.0d"));
#else
	AFU afu(string("/dev/cxl/afu0.0"));
#endif

	afu.start(wed);

	const unsigned Nsleep=2;

	cout << "AFU started, sleeping for " << Nsleep << " seconds" << endl;

	sleep(Nsleep);;

	cout << "Host code awake again, checking: " << endl;

	ofstream os("seq.received.out");

	bool corruption=false;

	for(const auto x : received | boost::adaptors::indexed(0U))
	{
		if (x.index() < N)
		{
			if (x.value() != 0)
			{
				corruption = true;
				cout << "ERROR: Corruption write at index " << x.index() << " value " << x.value() << endl;
			}
		}
		else if (x.index() < 2*N)
		{
			if (x.index() % 4 == 0)
				cout << x.index() << ": ";
			cout << setw(16) << hex << x.value() << ' ';
			if(x.index() % 4 == 3)
				cout << endl;
			os << setw(16) << hex << x.value() << endl;
		}
		else
		{
			if (x.value() != 0)
			{
				corruption = true;
				cout << "ERROR: Corruption write at index " << x.index() << " value " << x.value() << endl;
			}
		}
	}

	assert(!corruption);

	os.close();

	return 0;
}
