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
	Address 	addr;
	bool 		write;
	Data 		data;
};

template<class Packer,class Address,class Data>Packer& operator&(Packer& P,const Request<Address,Data>& a)
{
	P & a.request & a.addr & a.write & a.data;
	return P;
}


template<class Unpacker,class Address,class Data>Unpacker& operator&(Unpacker& P,Request<Address,Data>& a)
{
	P & a.request & a.addr & a.write & a.data;
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
				Request<Address,Data>>(t,50)
		{
			status(Ready);
		}


	private:
		virtual void implementDeq() override;

		Request<Address,Data>									m_current;		// value currently available on the read port
		std::vector<std::pair<uint64_t,Request<Address,Data>>>	m_history;		// history of values deq'd, with timestamp

		std::vector<Data>										m_expect;		// expected responses

		unsigned m_addr=0;
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




#include <iostream>
#include <iomanip>

using namespace std;

void MemScanChainTest::Stimulus::implementDeq()
{
	// log to the history vector
	m_history.emplace_back(device()->timebase(),m_current);

	const auto f = cout.flags();
	cout << "Time " << setw(20) << dec << device()->timebase() << "  IN ";
	if (!m_current.request)
		cout << "Data:    " << hex << setw(16) << m_current.data << endl;
	else
	{
		cout << "Request: " << (m_current.write ? "Write" : " Read") << " address " << hex << setw(16) << m_current.addr;
		if (m_current.write)
			cout << " data " << setw(16) << m_current.data;
		cout << endl;
	}
	cout.flags(f);

	// update output data
	m_current.write=false;
	m_current.request=false;
	m_current.addr=m_addr++;
	m_current.data=0xffff << 16 | (m_addr << 8) | m_addr;
	set(m_current);

	if (m_addr == 300)
		status(End);
}

void MemScanChainTest::preClose()
{
	std::cout << "Testbench closing" << std::endl;
}



void MemScanChainTest::Output::write(const Request<MemScanChainTest::Address,MemScanChainTest::Data>& t)
{
	const auto f = cout.flags();
	cout << "Time " << setw(20) << dec << device()->timebase() << " OUT ";
	if (!t.request)
		cout << "Data:    " << hex << setw(16) << t.data << endl;
	else
	{
		cout << "Request: " << (t.write ? "Write" : " Read") << " address " << hex << setw(16) << t.addr;
		if (t.write)
			cout << " data " << setw(16) << t.data;
		cout << endl;
	}
	cout.flags(f);
}

extern "C" void bdpi_initMemScanChainTest(){}
