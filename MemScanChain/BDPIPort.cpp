/*
 * BDPIPort.cpp
 *
 *  Created on: Mar 29, 2016
 *      Author: jcassidy
 */

#include "BDPIPort.hpp"

BDPIPort::BDPIPort()
{
}

BDPIPort::~BDPIPort()
{
}

void BDPIPort::readData(uint32_t* data)
{
	implementReadData(data);
}

void BDPIPort::writeData(const uint32_t* data)
{
	implementWriteData(data);
}

void BDPIPort::close()
{
	implementClose();
}

BDPIPort::Status BDPIPort::status() const
{
	return m_status;
}

uint8_t bdpi_portGetStatus(uint64_t portPtr)
{
	BDPIPort* p = reinterpret_cast<BDPIPort*>(portPtr);
	return static_cast<uint8_t>(p->status());
}

void bdpi_portGetReadData(uint32_t* ret,uint64_t portPtr)
{
	BDPIPort* p = reinterpret_cast<BDPIPort*>(portPtr);
	p->readData(ret);
}

void bdpi_portPutWriteData(uint64_t portPtr,const uint32_t* data)
{
	BDPIPort* p = reinterpret_cast<BDPIPort*>(portPtr);
	p->writeData(data);
}

void bdpi_portClose(uint64_t portPtr)
{
	BDPIPort* p = reinterpret_cast<BDPIPort*>(portPtr);
	p->close();
}
