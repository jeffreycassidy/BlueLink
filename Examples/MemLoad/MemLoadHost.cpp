#include <vector>
#include <array>
#include <string>
#include <iostream>
#include <fstream>
#include <iomanip>

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <boost/range/algorithm.hpp>

#include <boost/random/mersenne_twister.hpp>

#include <BlueLink/Host/aligned_allocator.hpp>

using namespace std;

struct MemLoadWED
{
	const uint64_t*	pSrc=nullptr;
	uint64_t* 		pDst=nullptr;
	uint64_t		size=0;

	array<uint64_t,13>	pad;

	MemLoadWED(){ boost::fill(pad,0); }
};

int main(int argc,char **argv)
{
	//// Source constants
#ifdef SIM
	const unsigned logNHL 	 = 10;				// 1024 512b half-lines
	const unsigned timeout=1800;
#else
	const unsigned logNHL	= 16;				// 64k 512b half-lines
	const unsigned timeout	= 4;
#endif

	const unsigned logNBanks =  4;				// 16 banks



	//// Derived constants
		const unsigned Nl1024=1 << (logNHL+1);	// # 1024b (128B) cache lines
		const unsigned Nhl512=1 << (logNHL);	// # 512b (64B) half-lines
		const unsigned Nui64=1 << (logNHL+3);	// # 64b (8B) words
		const unsigned NB= 1 << (logNHL+6);		// # 8b (1B) bytes

		const unsigned logNui64 = logNHL+3;
		const unsigned logNL = logNHL+1;

		const unsigned NBanks = 1<<logNBanks;

		const unsigned NWordsPerBank = (1 << (logNHL+3-logNBanks));

	BOOST_STATIC_ASSERT(logNL >= 6);

	StackWED<MemLoadWED,128,128> wed;

	vector<uint64_t,aligned_allocator<uint64_t,128>> src(Nui64,0),dst(Nui64,0);

	cout << "Running with " << NB << " byte transfer (" << Nl1024 << " cache lines, " << Nhl512 << " half-lines, " << Nui64 << " 64b words)" << endl;

	// set up WED
	wed->pSrc = src.data();
	wed->pDst = dst.data();
	wed->size = NB;

	// fill source with random numbers
	boost::mt19937_64 rng;
	boost::generate(src, rng);

	ofstream os("output.expected.hex");

	for(uint64_t i : src)
		os << setw(16) << hex << i << endl;
	os.close();


	// start accelerator
	AFU afu("/dev/cxl0.0d");
	afu.start(wed);
	sleep(1);


	////// Do host-AFU copy

	cout << "Waiting for host->AFU copy to finish" << endl;

	uint64_t tsH2AStart = afu.mmio_read64(0x10);
	uint64_t tsH2ADone  = 0;

	unsigned i;

	for(i=0;i<timeout && (tsH2ADone = afu.mmio_read64(0x18)) == 0; ++i)
		sleep(1);

	if (i==timeout)
		cout << "TIMEOUT!" << endl;

	cout << "  Started at " << tsH2AStart << " and finished at " << tsH2ADone << " (duration " << tsH2ADone-tsH2AStart << ")" << endl;



	////// Check BRAM readback

	std::vector<std::pair<uint8_t,uint32_t>> addrs{
		make_pair(0,0),
		make_pair(0,NWordsPerBank-1),						// last element in bank 1
		make_pair(1,NWordsPerBank-1),
		make_pair(1,0),
		make_pair(1,NWordsPerBank-1),
		make_pair(NBanks-2,NWordsPerBank-1),
		make_pair(NBanks-2,NWordsPerBank-2),
		make_pair(NBanks-2,NWordsPerBank-3),
		make_pair(NBanks-1,NWordsPerBank-1),				// last element overall
		make_pair(0,1),
		make_pair(NBanks-1,1),
		make_pair(NBanks-1,0)								// last bank, elements 1 and 0
	};

	cout << "Checking BRAM readback: " << endl;
	for(const auto p : addrs)
	{

		afu.mmio_write64(0x00,(p.first << 16) | p.second);
		cout << " Bank " << hex << (unsigned)p.first << " offset " << hex << p.second << ' ';
#ifdef SIM
		sleep(1);
#endif

		uint64_t expect = src[(p.first<<(logNui64-logNBanks)) | p.second];
		uint64_t actual = afu.mmio_read64(0x00);

		if (actual == expect)
			cout << "OK (" << hex << setw(16) << expect << ")";
		else
			cout << "Mismatch - expecting " << hex << setw(16) << expect << " received " << hex << actual;
		cout << endl;
	}



	////// Do AFU->host copy

	cout << "Starting AFU->host copy" << endl;

	afu.mmio_write64(0x08,0);

	uint64_t tsA2HStart=afu.mmio_read64(0x20);
	uint64_t tsA2HDone =afu.mmio_read64(0x28);

	for(unsigned i=0;i<timeout && (tsA2HDone = afu.mmio_read64(0x28)) == 0; ++i)
	{
#ifdef SIM
		sleep(1);
#endif
	}

	if (i==timeout)
		cout << "TIMEOUT!" << endl;

	cout << "AFU->host transfer started at " << tsA2HStart << " and finished at " << tsA2HDone << " (duration " << tsA2HDone-tsA2HStart << ")" << endl;



	////// Check output

	cout << "Output: " << endl;

	os.open("output.actual.hex");

	for(uint64_t o : dst)
		os << setw(16) << hex << o << endl;
	os.close();

	for(unsigned i=0;i<Nui64;++i)
		if (src[i] != dst[i])
			cout << "Mismatch at byte offset " << std::hex << setw(8) << 8*i << ": expected " << setw(16) << std::hex << src[i] << " and received " << setw(16) << std::hex << dst[i] << endl;

	cout << "Output check done" << endl;

	afu.mmio_write64(0x10,0);

	return 0;
}
