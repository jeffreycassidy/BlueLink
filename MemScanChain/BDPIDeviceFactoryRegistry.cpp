/*
 * BDPIDeviceFactoryRegistry.cpp
 *
 *  Created on: Apr 2, 2016
 *      Author: jcassidy
 */

#include "BDPIDeviceFactoryRegistry.hpp"
#include "BDPIDeviceFactory.hpp"
#include <map>

namespace detail {

BDPIDeviceFactoryRegistryBase::BDPIDeviceFactoryRegistryBase()
{
}

BDPIDevice* BDPIDeviceFactoryRegistryBase::build(const char* factoryName,const char* argstr,const uint32_t* data)
{
	std::string factoryNameStr(factoryName);

	std::cout << "Building device of type '" << factoryName << "' with arguments '" << argstr << "'" << std::endl;

	const auto it = m_registry.find(factoryNameStr);

	if (it != m_registry.end())
		return it->second->build(argstr,data);
	else
	{
		std::cout << "  No matching factory found (";
		for(const auto& p : m_registry)
			std::cout << p.first << ' ';
		std::cout << ')' << std::endl;
	}

	return nullptr;
}

void BDPIDeviceFactoryRegistryBase::registerFactory(std::string factoryName,BDPIDeviceFactory* factory)
{
	std::cout << "Registering device factory named '" << factoryName << "'" << std::endl;
	const auto p = m_registry.insert(std::make_pair(factoryName,factory));

	if (!p.second)
		throw std::logic_error(("Factory with name '"+factoryName+"' already exists").c_str());
}

};


template class Singleton<detail::BDPIDeviceFactoryRegistryBase>;
//detail::BDPIDeviceFactoryRegistryBase Singleton<detail::BDPIDeviceFactoryRegistryBase>::m_instance;


extern "C" uint64_t bdpi_createDeviceFromFactory(const char* devType,const char* argstr,const uint32_t* data)
{
	BDPIDevice* dev = BDPIDeviceFactoryRegistry::instance().build(devType,argstr,data);
	return reinterpret_cast<uint64_t>(dev);
}
