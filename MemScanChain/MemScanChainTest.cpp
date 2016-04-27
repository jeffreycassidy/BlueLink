/*
 * MemScanChainTest.cpp
 *
 *  Created on: Apr 27, 2016
 *      Author: jcassidy
 */

#include <BDPIDevice/Device.hpp>
#include <BDPIDevice/ReadPortPipeWrapper.hpp>
#include <BDPIDevice/WritePortWrapper.hpp>

#include <BDPIDevice/BitPacking/Types/FixedInt.hpp>
#include <BDPIDevice/BitPacking/Types/std_bool.hpp>
#include <BDPIDevice/BitPacking/Types/std_tuple.hpp>

#include <BDPIDevice/StandardNewFactory.hpp>
#include <BDPIDevice/DeviceFactory.hpp>

#include <vector>
#include <tuple>
#include <cinttypes>

#include <boost/random/mersenne_twister.hpp>

template<typename AddressType,typename DataType>struct Request
{
	typedef AddressType Address;
	typedef DataType	Data;

	bool 		request;
	bool 		write;
	Address 	addr;
	Data 		data;
};

template<class Packer,class Address,class Data>Packer& operator&(Packer& P,const Request<Address,Data>& a)
{
	P & a.request & a.write & a.addr & a.data;
	return P;
}


template<class Unpacker,class Address,class Data>Unpacker& operator&(Unpacker& P,Request<Address,Data>& a)
{
	P & a.request & a.write & a.addr & a.data;
	return P;
}


class MemScanChainTest : public Device
{
public:
	typedef FixedInt<uint16_t,16>	Address;
	typedef FixedInt<uint32_t,32>	Data;

private:
	class Stimulus : public ReadPortPipeWrapper<
		MemScanChainTest::Stimulus,
		MemScanChainTest,
		Request<Address,Data>>
	{
	public:
		Stimulus(MemScanChainTest* t) :
			ReadPortPipeWrapper<
				Stimulus,
				MemScanChainTest,
				Request<Address,Data>>(t,49)
		{}


	private:
		virtual void implementDeq() override;

		Request<Address,Data>									m_current;		// value currently available on the read port
		std::vector<std::pair<uint64_t,Request<Address,Data>>>	m_history;		// history of values deq'd, with timestamp

		std::vector<Data>										m_expect;		// expected responses
	};


	class Output : public WritePortWrapper<
		Output,
		MemScanChainTest,
		Request<Address,Data>>
	{
	public:
		//// TODO: Fix magic number below (bit widths)
		Output(MemScanChainTest* t) : WritePortWrapper(t,50)
		{
			status(Status::Ready);
		}

		void write(const Request<Address,Data>& t);
	};

public:

	Request<Address,Data> nextRequest();

	MemScanChainTest(const char* argstr,const uint32_t* data) :
		Device({ &m_stimPort, &m_resultPort }),
		m_stimPort(this),
		m_resultPort(this)
	{
		std::cout << "MemScanChainTest created with arguments '" << argstr << "'" << std::endl;
	}

	virtual ~MemScanChainTest(){}

private:

	static StandardNewFactory<MemScanChainTest> s_factory;

	virtual void preClose() override;
	class Stimulus;
	class Output;

	Stimulus						m_stimPort;
	Output							m_resultPort;

	boost::random::mt19937_64 		m_rng;
};

StandardNewFactory<MemScanChainTest> MemScanChainTest::s_factory("MemScanChainTest");





void MemScanChainTest::Stimulus::implementDeq()
{
	m_history.emplace_back(device()->timebase(),m_current);
	m_current = device()->nextRequest();
	set(m_current);
}

void MemScanChainTest::preClose()
{
	std::cout << "Testbench closing" << std::endl;
}

Request<MemScanChainTest::Address,MemScanChainTest::Data> MemScanChainTest::nextRequest()
{
	Request<MemScanChainTest::Address,MemScanChainTest::Data> ret;
	ret.write=false;
	ret.request=false;
	ret.addr=0;
	ret.data=0;
	return ret;
}



#include <iostream>
#include <iomanip>

using namespace std;

void MemScanChainTest::Output::write(const Request<MemScanChainTest::Address,MemScanChainTest::Data>& t)
{
	const auto f = cout.flags();
	cout << "Time " << setw(20) << dec << device()->timebase() << ' ';
	if (!t.request)
		cout << "Read response: " << hex << setw(16) << t.data << endl;
	else
	{
		cout << "Passthrough: " << (t.write ? "Write" : " Read") << " address " << hex << setw(16) << t.addr;
		if (t.write)
			cout << " data " << setw(16) << t.data;
		cout << endl;
	}
	cout.flags(f);
}

extern "C" void bdpi_initMemScanChainTest(){}
