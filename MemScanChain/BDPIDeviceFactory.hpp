/*
 * BDPIDeviceFactory.hpp
 *
 *  Created on: Apr 1, 2016
 *      Author: jcassidy
 */

#ifndef MEMSCANCHAIN_BDPIDEVICEFACTORY_HPP_
#define MEMSCANCHAIN_BDPIDEVICEFACTORY_HPP_

#include <cinttypes>

class BDPIDevice;

/// Prototype of a method which returns a BDPIDevice
//typedef (BDPIDevice*)(*BDPIDeviceFactoryMethodPtr)(const char* argstr,const uint32_t* data);


/** Provides an abstract base class for a factory to create BDPIDevice from two arguments (1 string, 1 data)
 */

class BDPIDeviceFactory
{
public:
	BDPIDeviceFactory();
	virtual ~BDPIDeviceFactory();

	virtual BDPIDevice* build(const char* argstr,const uint32_t* data)=0;

	void registerSelf();
};


#endif /* MEMSCANCHAIN_BDPIDEVICEFACTORY_HPP_ */
