#include <cinttypes>
#include <memory>
#include <iostream>

#include <boost/random/mersenne_twister.hpp>

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>
#include <boost/range/adaptor/indexed.hpp>

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <BlueLink/Host/aligned_allocator.hpp>

#include <iomanip>
#include <vector>
#include <fstream>

using namespace std;

template<class T,std::size_t size,std::size_t align>void showBytes(std::ostream& os,const WEDBase<T,size,align>& wed)
{
    os << hex;

    for(unsigned x : wed.bytes())
        os << setfill('0') << setw(2) << x << ' ';
}

struct StreamWED {
    void*       pSrc;
    uint64_t    size;
    uint64_t    pad[14];
};


int main (int argc, char *argv[])
{
    const std::size_t N=256;

	boost::random::mt19937_64 rng;

    std::vector<uint64_t,aligned_allocator<uint64_t,128>> i(N,0);

    // Generate sequence and create copy to send to AFU
    boost::generate(i,rng);

	// Display values to send & write
	ofstream os("host2afu.expected.out");
    for(const auto x : i | boost::adaptors::indexed(0U))
    {
        cout << setw(16) << hex << x.value() << ' ';
        if(x.index() % 4 == 3)
            cout << endl;

        os << setw(16) << hex << x.value() << endl;
    }
    os.close();


    // Set up WED, attach AFU, and send go signal
    StackWED<StreamWED,128> wed;
    wed->pSrc=i.data();
    wed->size=N*8;

	AFU afu(string("/dev/cxl/afu0.0d"));
	afu.start(wed);

	afu.mmio_write64(0,0);


	// send go signal and wait for done signal (MMIO dword #3)
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

	for(unsigned i=0;i<8;++i)
		cout << "    AFU MMIO[" << setw(2) << hex << (i<<3) << "]: " << setw(16) << afu.mmio_read64(i<<3) << endl;

	// shut down AFU
	afu.mmio_write64(40,0);

	return !(timedout);
}
