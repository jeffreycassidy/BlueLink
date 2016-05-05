/*
 * HG_CAPI_Host.cpp
 *
 *  Created on: Apr 20, 2016
 *      Author: jcassidy
 */

#include <cinttypes>

#include <boost/random/mersenne_twister.hpp>

#include <boost/align/aligned_allocator.hpp>

#include <boost/range.hpp>
#include <boost/range/algorithm.hpp>

#include <iostream>
#include <iomanip>
#include <functional>
#include <vector>

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

#include <BDPIDevice/BitPacking/Packer.hpp>
#include <BDPIDevice/BitPacking/Unpacker.hpp>

#include <BDPIDevice/BitPacking/Types/std_pair.hpp>
#include <BDPIDevice/BitPacking/Types/std_array.hpp>
#include <BDPIDevice/BitPacking/Types/FixedInt.hpp>
#include <BDPIDevice/BitPacking/Types/FixedPoint.hpp>
#include <FMHW/modules/HenyeyGreenstein/HGRandomStim.hpp>

#include <boost/range.hpp>

#include "BlockMapAFUBase.hpp"

using namespace std;

template<class TestFixture>class BlockMapAFU : public BlockMapAFUBase
{
public:
	typedef std::vector<
			typename TestFixture::input_container_type,
			boost::alignment::aligned_allocator<typename TestFixture::input_container_type,128>>
			input_vector;

	typedef std::vector<
			typename TestFixture::output_container_type,
			boost::alignment::aligned_allocator<typename TestFixture::output_container_type,128>>
			output_vector;

	BlockMapAFU(const char* devStr) : BlockMapAFUBase(devStr){}
	void start();

	bool check();

	void resizeInput(std::size_t N){ m_packedInput.resize(N); }

	boost::iterator_range<typename input_vector::iterator> 			input() { return m_packedInput; }
	boost::iterator_range<typename input_vector::const_iterator> 	input() const { return m_packedInput; }

	TestFixture fixture;

private:
	unsigned m_maxErrorsToPrint=4096;

	std::vector<
		typename TestFixture::input_container_type,
		boost::alignment::aligned_allocator<typename TestFixture::input_container_type,128>> 	m_packedInput;

	std::vector<
		typename TestFixture::output_container_type,
		boost::alignment::aligned_allocator<typename TestFixture::output_container_type,128>> 	m_packedOutput;
};

template<class TestFixture>void BlockMapAFU<TestFixture>::start()
{
	// allocate and blank the output vector
	m_packedOutput.resize(m_packedInput.size());
	memset(m_packedOutput.data(),0,m_packedOutput.size()*sizeof(typename TestFixture::output_container_type));

	// set up WED
	m_wed->param.src = m_packedInput.data();
	m_wed->param.iSize = sizeof(typename TestFixture::input_container_type)*m_packedInput.size();
	m_wed->param.dst = m_packedOutput.data();
	m_wed->param.oSize = sizeof(typename TestFixture::output_container_type)*m_packedInput.size();

	AFU::start(m_wed.get());
}

template<class TestFixture>bool BlockMapAFU<TestFixture>::check()
{
	unsigned errCt=0;
	fixture.checker.clear();
	cout << "Checking output" << endl;



	for(unsigned i=0;i<m_packedInput.size();++i)
	{
		Unpacker<typename TestFixture::input_container_type>  Ui(TestFixture::input_bits,m_packedInput[i]);
		Unpacker<typename TestFixture::output_container_type> Uo(TestFixture::output_bits,m_packedOutput[i]);

		typename TestFixture::packed_input_type 	in;
		typename TestFixture::packed_output_type 	out;

		Ui & in;
		Uo & out;

		bool ok = fixture.checker(fixture.convertToNativeType(in),fixture.convertToNativeType(out));
		errCt += !ok;
		if (!ok && errCt <= m_maxErrorsToPrint)
			cout << "  (at sample " << i << ")" << endl;
	}
	if (errCt > m_maxErrorsToPrint)
		cout << " ... and " << errCt-m_maxErrorsToPrint << " more errors truncated" << endl;

	cout << "  Errors: " << errCt << '/' << m_packedInput.size() << endl;
	return errCt==0;
}
