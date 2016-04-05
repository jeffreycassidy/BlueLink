/*
 * BDPIDeviceFactoryRegistry.hpp
 *
 *  Created on: Apr 2, 2016
 *      Author: jcassidy
 */

#ifndef MEMSCANCHAIN_BDPIDEVICEFACTORYREGISTRY_HPP_
#define MEMSCANCHAIN_BDPIDEVICEFACTORYREGISTRY_HPP_

#include "Singleton.hpp"

#include <map>
#include <string>

class BDPIDevice;
class BDPIDeviceFactory;

#include <iostream>

namespace detail {

/** Registry for keeping track of multiple factories
 *
 */

class BDPIDeviceFactoryRegistryBase
{
public:
	void registerFactory(std::string factoryName,BDPIDeviceFactory* factory);
	BDPIDevice* build(const char* factoryName,const char* argstr,const uint32_t* data);

	BDPIDeviceFactoryRegistryBase();

private:
	std::map<std::string,BDPIDeviceFactory*> 		m_registry;
};

};

typedef Singleton<detail::BDPIDeviceFactoryRegistryBase> BDPIDeviceFactoryRegistry;
extern template class Singleton<detail::BDPIDeviceFactoryRegistryBase>;

class BDPIDeviceFactoryRegistration
{
public:
	BDPIDeviceFactoryRegistration(const char* devType,BDPIDeviceFactory* factory)
	{
		std::cout << "BDPIDeviceFactoryRegistration: registering factory for type '" << devType << "'" << std::endl;
		BDPIDeviceFactoryRegistry::instance().registerFactory(devType,factory);
	}
};


extern "C" {
	uint64_t	bdpi_createDeviceFromFactory(const char* devType,const char* argstr,const uint32_t* data);
}




#endif /* MEMSCANCHAIN_BDPIDEVICEFACTORYREGISTRY_HPP_ */
