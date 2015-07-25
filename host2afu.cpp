#include <cinttypes>
#include <memory>
#include <iostream>

#include <boost/random/mersenne_twister.hpp>

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>
#include <boost/range/adaptor/indexed.hpp>

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include "aligned_allocator.hpp"

#include <iomanip>
#include <vector>
#include <fstream>


#define CACHELINE_BYTES 128

struct MemcopyWED {
	uint64_t	addr_to;
	uint64_t	size;

	uint64_t	resv[13];
};

#include <type_traits>

using namespace std;

template<class T,std::size_t size,std::size_t align>ostream& operator<<(ostream& os,StackWED<T,size,align>& wed)
{
    return os <<
        setw(16) << wed.get() <<
        " size=" << setw(4) << size <<
        " align=" << setw(4) << align <<
        " allocated " << setw(4) << wed.allocated() <<
        " bytes at " << setw(16) << wed.base() <<
            '-' << setw(16) << reinterpret_cast<const void*>(reinterpret_cast<const char*>(wed.base())+wed.allocated()) <<
        " for payload size " << setw(4) << wed.payloadSize() <<
        " (end pointer " << reinterpret_cast<const void*>(reinterpret_cast<const char*>(wed.base())+wed.offset()+wed.payloadSize()) << ")";
}

template<class T,std::size_t size,std::size_t align>void showBytes(std::ostream& os,const WEDBase<T,size,align>& wed)
{
    os << hex;

    for(unsigned x : wed.bytes())
        os << setfill('0') << setw(2) << x << ' ';
}

//template<typename T>ostream& operator<<(ostream& os,boost::iterator_range<T>

struct StreamWED {
    void*       src;
    uint64_t    size;
};


int main (int argc, char *argv[])
{
    StackWED<char[12],128> wa;
    char t;
    StackWED<char[12],16> wb;

    std::vector<char,aligned_allocator<char,128>> v(1,0);

    StackWED<StreamWED,128> wed;

    cout << "wa=" << wa << endl;
    cout << "wb=" << wb << endl;

    (*wa)[0] = 0xff;

    cout << "wa @" << wa.get() << ": ";
    showBytes(cout,wa);
    cout << endl;


    cout << "wb @" << wb.get() << ": ";
    showBytes(cout,wb);
    cout << endl;


    cout << "wed @" << wed.get() << ": ";
    showBytes(cout,wed);
    cout << endl;

	boost::random::mt19937_64 rng;

    const std::size_t N=256;

    std::vector<uint64_t,aligned_allocator<uint64_t,128>> golden(N,0),i(N,0),o(N,0);
    boost::generate(golden,rng);

    boost::copy(golden,i.begin());

    wed->src=i.data();
    wed->size=N*8;

    cout << "Stimulus is ready (" << N << " dwords, " << N*8 << " bytes)" << endl;

    ofstream os("seq.expected.out");

    for(const auto x : i | boost::adaptors::indexed(0U))
    {
        cout << setw(16) << hex << x.value() << ' ';
        if(x.index() % 4 == 3)
            cout << endl;
        os << setw(16) << hex << x.value() << endl;
    }

    os.close();

#ifdef HARDWARE
	AFU afu(string("/dev/cxl/afu0.0d"));
#else
	AFU afu(string("/dev/cxl/afu0.0"));
#endif

	afu.start(wed);

//	cout << "AFU started, waiting 200ms for finish" << endl;
//
//	usleep(200000);
//
//	//afu.await_event();
//	cout << "  done" << endl;
//	
//	afu.await_event(1000);
//
//	cout << "  WED read completed, checking readback: " << endl;
//	for(unsigned i=0;i<8;++i)
//		cout << "    AFU MMIO[" << setw(2) << hex << (i<<3) << "]: " << setw(16) << afu.mmio_read64(i<<3) << endl;
//
//	cout << "Sending go signal" << endl;
//	afu.mmio_write64(0,0);
//
//	afu.await_event(1000);
//	cout << "  copy finished" << endl;
//
//	for(size_t i=Ndw; i<2*Ndw; ++i)
//		if (golden[i] != 0)
//			cerr << "Corruption write at " << i << endl;
//
//	for(size_t i=3*Ndw; i<4*Ndw; ++i)
//			if (golden[i] != 0)
//				cerr << "Corruption write at " << i << endl;
//
//	for(size_t i=5*Ndw; i<6*Ndw; ++i)
//			if (golden[i] != 0)
//				cerr << "Corruption write at " << i << endl;
//
//	for(size_t i=0; i<Ndw; i += 4)
//	{
//		bool match=true;
//		for(size_t j=i; j<i+4; ++j)
//			match &= golden[j]==odata[j];
//
//		cout << setw(4) << hex << i << ": ";
//
//		if (match)
//		{
//			cout << "      OK";
//			for(size_t j=i; j<i+4; ++j)
//				cout << "  " << setw(16) << setfill('0') << odata[j];
//		}
//		else
//		{
//			cout << "Expected";
//			for (size_t j=i; j<i+4; ++j)
//				cout << "  " << setw(16) << setfill('0') << golden[j];
//			cout << endl << "    Received";
//			for(size_t j=i; j<i+4; ++j)
//				cout << "  " << setw(16) << setfill('0') << odata[j];
//		}
//		cout << endl << endl;
//	}
//
  return 0;
}
