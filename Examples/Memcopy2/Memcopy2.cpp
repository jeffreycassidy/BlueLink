#include <iostream>
#include <vector>
#include <cassert>

#if BOOST_VERSION >= 105600
#define HAVE_BOOST_ALIGN
#include <boost/align/is_aligned.hpp>
#endif

#include <boost/random/mersenne_twister.hpp>
#include <boost/range/algorithm.hpp>


#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <BlueLink/Host/aligned_allocator.hpp>

/** Struct must be packed in reverse element order wrt. Bluespec struct to facilitate endian conversion. */

struct MemcopyWED {
	const uint64_t*	pSrc;
	uint64_t*		pDst;
	uint64_t		size;
	uint64_t		pad[13];
};

int main(int argc,char **argv)
{
	// number of 64b words, and bytes
	const unsigned N=2048;
	const unsigned Nb=N*8;

	// create source/destination buffers initialized to zero, ensuring alignment
	vector<uint64_t,aligned_allocator<uint64_t,128>> src(N,0),dst(3*N,0);
	const uint64_t* pSrc = src.data();
	uint64_t* pDst = dst.data()+N;

	// create WED
	StackWED<MemcopyWED,128> wed;
	wed->pSrc = pSrc;
	wed->pDst = pDst;
	wed->size = Nb;

    cout << setw(16) << hex << "  pSrc= " << pSrc << endl;
    cout << setw(16) << hex << "  pDst= " << pDst << endl;
    cout << setw(16) << hex << "  size= " << wed->size << endl;

#ifdef HAVE_BOOST_ALIGN
	assert(boost::align::is_aligned(128,pSrc);
	assert(boost::align::is_aligned(128,pDst);
	assert(boost::align::is_aligned(128,pWED);
	assert(boost::align::is_aligned(128,Nb);
	cout << "Alignment OK" << endl;
#else
#warning "Alignment checks bypassed due to missing boost::align"
#endif

	// generate random data
	boost::random::mt19937_64 rng;
	boost::generate(src, rng);

	

	// Attach AFU
	AFU afu(string("/dev/cxl/afu0.0d"));
	afu.start(wed);

	for(unsigned i=0;i<4;++i)
		cout << "PSA[" << setw(2) << 8*i << "]=" << setw(16) << afu.mmio_read64(8*i) << endl;

    afu.print_details();

    cout << "Sending start pulse" << endl;

	// launch the memcopy
	afu.mmio_write64(32,0);

	// wait for finish
	const unsigned timeout=15;
	unsigned d;
	for (d=0; d < timeout && afu.mmio_read64(24) != 0x1111111111111111UL; ++d)
		sleep(1);

	if (d==timeout)
		cout << "ERROR: AFU timed out after " << timeout << " seconds" << endl;

	// check for corruption
	auto itDst = dst.cbegin();
	int i=-N;

	for(i=-N;i<0;++i,++itDst)
		if (*itDst)
			cout << "Corruption write " << (-i) << " before start: " << setw(16) << hex << *itDst << endl;

    unsigned ok=0;
	
	for(auto itSrc = src.cbegin(); itSrc != src.cend(); ++i,++itDst,++itSrc)
		if (*itSrc != *itDst)
			cout << "Mismatch at index " << i << ": " << setw(16) << hex << *itDst << " != " << setw(16) << *itSrc << endl;
        else
            ++ok;

	for(;i<N;++i,++itDst)
		if (*itDst)
			cout << "Corruption write " << i << " after end: " << setw(16) << hex << *itDst << endl;


	for(unsigned i=0;i<4;++i)
		cout << "PSA[" << setw(2) << 8*i << "]=" << setw(16) << afu.mmio_read64(8*i) << endl;

	afu.mmio_write64(40,0);

    cout << dec << ok << "/" << N << " OK" << endl;

	return 0;
}
