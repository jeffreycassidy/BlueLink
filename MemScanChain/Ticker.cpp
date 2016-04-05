/*
 * Ticker.cpp
 *
 *  Created on: Apr 2, 2016
 *      Author: jcassidy
 */

#include "BDPIDevice.hpp"
#include "BDPIDeviceFactory.hpp"
#include "BDPIDeviceFactoryRegistry.hpp"

#include <string>

/** Trivial example of BDPIDevice, just prints ticks to stdout.
 *
 * IMPORTANT NOTE: On Linux, lazy binding seems to mean that global variables in a .so file aren't initialized until
 * a function or symbol from that library is accessed. That means the BDPIDeviceFactoryRegistration object isn't
 * initialized (and hence the factory is not registered) until a symbol from the library is touched, if the registry is
 * in a separate module.
 *
 * The init_Ticker() method is provided for that purpose. It should be called before expecting the factory to respond
 * appropriately to a request to build a Ticker.
 *
 */

class Ticker : public BDPIDevice
{
public:
	Ticker(std::string argstr,const uint32_t* data);

	class TickerFactory : public BDPIDeviceFactory
	{
	public:
		TickerFactory()
		{
			std::cout << "TickerFactory::TickerFactory()" << std::endl;

		}
		~TickerFactory(){}

		BDPIDevice* build(const char* argstr,const uint32_t* data)
		{
			return new Ticker(std::string(argstr),data);
		}
	};

private:
	virtual void cycleStart() override;
	virtual void cycleFinish() override;

	virtual void preClose() override;
	virtual void postClose() override;

	std::string 			m_name;

	static TickerFactory 	m_factory;

	// Add the TickerFactory to the global factory registry
	static BDPIDeviceFactoryRegistration m_registration;
};

// IMPORTANT: Read note in title block regarding lazy symbol initialization - need to touch a symbol in this file
// before these will be initialized.
BDPIDeviceFactoryRegistration Ticker::m_registration{"Ticker",&m_factory};
Ticker::TickerFactory Ticker::m_factory;

#include <iostream>
#include <iomanip>
using namespace std;


// dummy method to call to precipitate symbol resolution and global var initialization (see note in title block)
extern "C" void init_Ticker()
{
}

Ticker::Ticker(std::string argstr,const uint32_t* data) :
		m_name(argstr)
{
	cout << "Ticker::Ticker(argstr,data) called with argstr '" << argstr << "'" << endl;
}

void Ticker::cycleStart()
{
	cout << setw(9) << timebase() << " " << setw(20) << m_name << " Ticker::preTick()" << endl;
}

void Ticker::cycleFinish()
{
	cout << setw(9) << timebase() << " " << setw(20) << m_name << " Ticker::postTick()" << endl;
}

void Ticker::preClose()
{
	cout << setw(9) << timebase() << " " << setw(20) << m_name << " Ticker::preClose()" << endl;
}

void Ticker::postClose()
{
	cout << setw(9) << timebase() << " " << setw(20) << m_name << " Ticker::postClose()" << endl;
}
