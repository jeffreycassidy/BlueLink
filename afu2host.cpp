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
#include <fstream>

#define CACHELINE_BYTES 128

#include <type_traits>

using namespace std;

struct StreamWED {
    void*       src;
    uint64_t    size;
};

#include <boost/version.hpp>

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

#ifdef HAVE_BOOST_ALIGN
	assert(boost::alignment::is_aligned(CACHELINE_BYTES,received.data()));
	assert(boost::alignment::is_aligned(CACHELINE_BYTES,wed->src));
#endif


	AFU afu(string("/dev/cxl/afu0.0d"));

	afu.start(wed);

	cout << hex << setfill('0');

	for(unsigned i=0;i<4;++i)
		cout << "PSA[" << setw(2) << 8*i << "]=" << setw(16) << afu.mmio_read64(8*i) << endl;

	afu.mmio_write64(32,0);

	cout << "Waiting for done signal from AFU" << endl;

	const unsigned timeout=10;

	unsigned d;
	for(d=0; afu.mmio_read64(24) != 0x1111111111111111 && d < timeout; ++d)
		sleep(1);

	if (d == timeout)
		cout << "ERROR: AFU timed out after " << timeout << " seconds" << endl;

	ofstream os("seq.received.out");

	bool corruption=false;

	for(unsigned i=0;i<3*N;++i)
	{
		if (i < N)
		{
			if (received[i] != 0)
			{
				corruption = true;
				cout << "ERROR: Corruption write at index " << i << " value " << received[i] << endl;
			}
		}
		else if (i < 2*N)
		{
			if (i % 4 == 0)
				cout << i << ": ";
			cout << setfill('0') << setw(16) << hex << received[i] << ' ';
			if(i % 4 == 3)
				cout << endl;
			os << setw(16) << hex << received[i] << endl;
		}
		else
		{
			if (received[i] != 0)
			{
				corruption = true;
				cout << "ERROR: Corruption write at index " << i << " value " << received[i] << endl;
			}
		}
	}

	assert(!corruption);


	for(unsigned i=0;i<4;++i)
		cout << "PSA[" << setw(2) << 8*i << "]=" << setw(16) << afu.mmio_read64(8*i) << endl;

	afu.mmio_write64(40,0);

	os.close();

	return 0;
}
