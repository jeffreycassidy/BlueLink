#include <iostream>
#include <vector>
#include <cassert>

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>
#include <BlueLink/Host/aligned_allocator.hpp>

#include <BDPIPipe/FixedInt.hpp>
#include <BDPIPipe/BitPackUnpack/Types/FixedInt.hpp>
#include <BDPIPipe/BitPackUnpack/Types/Pad.hpp>
#include <BDPIPipe/BitPackUnpack/Types/std_array.hpp>

#include <BDPIPipe/BitPackUnpack/BDPIAutoArrayBitPacker.hpp>

#include <boost/range/algorithm.hpp>


union CacheLine
{
    std::array<uint8_t,128> u8;
    std::array<uint16_t,64> u16;
    std::array<uint32_t,32> u32;
    std::array<uint64_t,16> u64;
};

struct EndianWED
{
    const CacheLine*	p;
    uint64_t			pad[15];
};


int main(int argc,char **argv)
{
	// create WED
	StackWED<EndianWED,128> wed;

    // create test stimulus
    CacheLine clZero;
    boost::fill(clZero.u64, 0);

    std::vector<CacheLine,aligned_allocator<CacheLine,128>> stim(16,clZero,aligned_allocator<CacheLine,128>());

    // first test: lowest byte set ff, else 0
    stim[0].u8[0] = 0xff;

    // second test: 
    stim[1].u64[0] = 0x0123456789abcdefULL;

    // third test: uint#(4) 0xa, uint#(64) 0x0123456789abcdef
    {
        BDPIAutoArrayBitPacker P(1024,(uint32_t*)stim[2].u64.data());
        P & FixedInt<uint8_t,4>(0xa) & FixedInt<uint64_t,64>(0x0123456789abcdef) & Pad<956>();
    }
    
    // fourth test: series of UInt#(8) with increasing values 0x00..0x7f
    {
    	BDPIAutoArrayBitPacker P(1024,(uint32_t*)stim[3].u64.data());
    	for(unsigned i=0;i<128;++i)
    		P & FixedInt<uint8_t,8>(i);
    }

    // fifth test: raw bits, 0x00..0x7f in increasing memory locations
    {
    	for(unsigned i=0;i<128;++i)
    		stim[4].u8[i] = i;
    }

    // sixth test: same as fourth, using std::array<>
    {
    	BDPIAutoArrayBitPacker P(1024,(uint32_t*)stim[5].u64.data());
    	std::array<FixedInt<uint8_t,8>,128> a;

    	for(unsigned i=0;i<128;++i)
    		a[i] = i;

    	P & a;
    }


    // case 6: array of 0x300000000000000? where ? = 0..f
    {
    	BDPIAutoArrayBitPacker P(1024,(uint32_t*)stim[6].u64.data());
    	std::array<FixedInt<uint64_t,62>,16> a;

    	for(unsigned i=0;i<16;++i)
    		a[i] = (0x3ULL << 60) | i;

    	P & a & Pad<32>();
    }

    wed->p = stim.data();

	// Attach AFU
	AFU afu(string("/dev/cxl/afu0.0d"));
	afu.start(wed);


    sleep(5);


	return 0;
}
