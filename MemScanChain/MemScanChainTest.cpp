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


/** The request type to be passed to/from the DUT */

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





/**
 *
 */


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
		Stimulus(MemScanChainTest* t);
		void nextRequest();
		void deq();

	private:
		Request<Address,Data>		m_current;
	};


	class Output : public WritePortWrapper<
		Output,
		MemScanChainTest,
		Request<Address,Data>>
	{
	public:
		Output(MemScanChainTest* t);
		void write(const Request<Address,Data>& t);
	};

public:
	MemScanChainTest(const char* argstr,const uint32_t* data);
	virtual ~MemScanChainTest();

private:

	static StandardNewFactory<MemScanChainTest> s_factory;

	virtual void preClose() override;

	// these need to be initialized before Stimulus/Output below
	unsigned m_stimAddr=0;
	unsigned m_outputPos=0;

	Stimulus						m_stimPort;
	Output							m_resultPort;

	boost::random::mt19937_64 		m_rng;

	std::vector<std::pair<uint64_t,Request<Address,Data>>>	m_history;		// history of values deq'd, with timestamp
	std::vector<Data>										m_contents;		// memory contents
	std::vector<Request<Address,Data>>						m_expect;		// expected responses

	unsigned m_errCount=0;
};

/// Register the factory so we can create MemScanChainTest by passing the string to bdpi_createDeviceFromFactory
StandardNewFactory<MemScanChainTest> MemScanChainTest::s_factory("MemScanChainTest");




#include <iostream>
#include <iomanip>


template<class AddressType,class DataType>std::ostream& operator<<(std::ostream& os,const Request<AddressType,DataType>& t)
{
	if (!t.request)
	{
		os << "Data:    " << t.data;
	}
	else
	{
		os << "Request: " << (t.write ? "Write" : " Read") << " address " << t.addr;
		if (t.write)
			os << " data " << t.data;
	}
	return os;
}


using namespace std;

MemScanChainTest::MemScanChainTest(const char* argstr,const uint32_t* data) :
	Device({ &m_stimPort, &m_resultPort }),
	m_stimPort(this),
	m_resultPort(this)
{
	std::cout << "MemScanChainTest created with arguments '" << argstr << "'" << std::endl;
}


MemScanChainTest::Stimulus::Stimulus(MemScanChainTest* t) : ReadPortPipeWrapper(t,50)
{
	status(Ready);
	nextRequest();
}

MemScanChainTest::~MemScanChainTest()
{
}

void MemScanChainTest::Stimulus::nextRequest()
{
	// update output data
	if (device()->m_stimAddr < 300)								// passthrough data ffff[0x000-0x12A]
	{
		m_current.write=false;
		m_current.request=false;
		m_current.addr=device()->m_stimAddr;
		m_current.data=0xffff << 16 | device()->m_stimAddr;
	}
	else if (device()->m_stimAddr < 600)						// write data eeee[0x0000-0x012A] to addresses 0x0000-0x012A
	{
		m_current.write=true;
		m_current.request=true;
		m_current.addr=device()->m_stimAddr-300;
		m_current.data=0xeeee << 16 | (device()->m_stimAddr-300);
	}
	else if (device()->m_stimAddr < 900)						// read addresses 0x0000-0x012A
	{
		m_current.write=false;
		m_current.request=true;
		m_current.addr=device()->m_stimAddr-600;
		m_current.data=0;
	}
	else
		status(End);

	set(m_current);
	device()->m_stimAddr++;

}

void MemScanChainTest::Stimulus::deq()
{
	// log to the history vector
	device()->m_history.emplace_back(device()->timebase(),m_current);

	const auto f = cout.flags();
	cout << "Time " << setw(20) << dec << device()->timebase() << "  IN " << m_current << endl;
	cout.flags(f);

	if (m_current.addr.value() >= 256 || !m_current.request)	// data or non-local request -> pass through
		device()->m_expect.push_back(m_current);
	else if (!m_current.write)									// local read
	{
		device()->m_expect.emplace_back();
		device()->m_expect.back().write=false;
		device()->m_expect.back().request=false;
		device()->m_expect.back().addr=0;
		device()->m_expect.back().data=device()->m_contents.at(m_current.addr.value());
	}

	if (m_current.write)
	{
		if (m_current.addr.value() >= device()->m_contents.size())
			device()->m_contents.resize(m_current.addr.value()+1,Data());
		device()->m_contents[m_current.addr.value()] = m_current.data;
	}

	nextRequest();
}

void MemScanChainTest::preClose()
{
	std::cout << "Testbench closing" << std::endl;
	std::cout << "  " << m_errCount << " errors" << std::endl;
}


MemScanChainTest::Output::Output(MemScanChainTest* t) : WritePortWrapper(t,50)
{
	status(Status::Ready);
}


void MemScanChainTest::Output::write(const Request<MemScanChainTest::Address,MemScanChainTest::Data>& t)
{
	const auto f = cout.flags();
	cout << "Time " << setw(20) << dec << device()->timebase() << " OUT " << t << endl;

	const Request<Address,Data> expected = device()->m_expect[device()->m_outputPos];

	bool err=true;
	if (expected.request && !t.request)
		cout << "**** ERROR - Expected a request pass-through but received data" << endl;
	else if (t.request && !expected.request)
		cout << "**** ERROR - Expecting response data but received request pass-through" << endl;
	else if (expected.request && (t.addr != expected.addr || t.write != expected.write || (expected.write && t.data != expected.data)))
		cout << "**** ERROR - Passthrough request (" << t << ") differs from expected (" << expected << ")" << endl;
	else if (t.data != expected.data)
		cout << "**** ERROR - Data received (" << t.data << ") differs from expected (" << expected.data << ")" << endl;
	else
		err=false;

	device()->m_errCount += err;

	device()->m_outputPos++;
	cout.flags(f);
}

extern "C" void bdpi_initMemScanChainTest(){}
