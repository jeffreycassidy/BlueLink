#include <boost/multiprecision/gmp.hpp>
#include <boost/range/adaptor/indexed.hpp>
#include <iostream>
#include <fstream>
#include <map>

using namespace std;

using namespace boost::multiprecision;

/** Reorders the output of Test_HostToAFUBulk according to the printed index.
 *
 * Testbench writes out a file of <addr> <128B halfline>
 *
 * This orders the half-lines by address and prints at 64b hex integers (same format as host2afu.expected.out)
 */

int main(int argc,char **argv)
{
	ifstream is("HostToAFUBulk.hex");

	vector<number<gmp_int>> V;

	while(!is.eof())
	{
		unsigned o;
		number<gmp_int> v;

		is >> hex >> o;
		if (is.eof())
			break;
		is >> v;

		if (o >= V.size())
			V.resize(o+1,0);

		V[o] = v;
	}


	for(const auto cl : V | boost::adaptors::indexed(0U))			// cache lines (512b)
		for(unsigned j=0;j<8;++j)									// j indexes 64b/8B x 8 ints = 512b
		{
			number<gmp_int> tmp = (cl.value() >> (j << 6)) & (~0ULL);		// shift out in little-endian order (LSBs first)
			uint64_t o = static_cast<uint64_t>(tmp);
			cout << hex << setw(16) << setfill(' ') << o << endl;
		}
}
