/*
 * BDPIDevice.cpp
 *
 *  Created on: Mar 29, 2016
 *      Author: jcassidy
 */

#include "BDPIDevice.hpp"
#include "BDPIPort.hpp"

BDPIDevice::BDPIDevice()
{
}

BDPIDevice::~BDPIDevice()
{
}

void BDPIDevice::tick(uint64_t t)
{
	cycleFinish();
	m_timebase=t;
	cycleStart();
}

void BDPIDevice::close()
{
	preClose();
	for(BDPIPort* p : m_ports)
		p->close();
	postClose();
}

BDPIPort* BDPIDevice::getPort(uint8_t p) const
{
	return m_ports.at(p);
}

uint8_t BDPIDevice::addPort(BDPIPort* p)
{
	uint8_t i = m_ports.size();
	m_ports.push_back(p);
	return i;
}

uint64_t BDPIDevice::timebase() const
{
	return m_timebase;
}


void bdpi_deviceTick(uint64_t devicePtr,uint64_t timebase)
{
	BDPIDevice *d = reinterpret_cast<BDPIDevice*>(devicePtr);
	d->tick(timebase);
}

void bdpi_deviceClose(uint64_t devicePtr)
{
	BDPIDevice *d = reinterpret_cast<BDPIDevice*>(devicePtr);
	d->close();
}

uint64_t bdpi_deviceGetPort(uint64_t devicePtr,uint8_t port)
{
	BDPIDevice *d = reinterpret_cast<BDPIDevice*>(devicePtr);
	return reinterpret_cast<uint64_t>(d->getPort(port));
}
