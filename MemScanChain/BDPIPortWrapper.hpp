/*
 * BDPIPortWrapper.hpp
 *
 *  Created on: Apr 1, 2016
 *      Author: jcassidy
 */

#ifndef MEMSCANCHAIN_BDPIPORTWRAPPER_HPP_
#define MEMSCANCHAIN_BDPIPORTWRAPPER_HPP_

#include "BDPIPort.hpp"

template<class Wrapped,class Device,class Return,class Args...>class BDPIPortWrapper : public BDPIPort
{
public:

private:
	virtual void implementWriteData(const uint32_t* data) override;
	virtual void implementReadData(uint32_t* ret) override;
	virtual void implementClose() override;

	Device*		m_device=nullptr;

	Wrapped		m_wrapped;
};

template<class Derived,class Device,class Return,class Args...>void BDPIPortWrapper<Derived,Device,Return,Args...>::
	implementWriteData(const uint32_t* data)
{
	// Unpack args
	m_derived.write(Args...);
}

template<class Derived,class Device,class Return,class Args...>void BDPIPortWrapper<Derived,Device,Return,Args...>::
	implementReadData(uint32_t* data)
{
	Return r = m_derived.read();
	// Pack return value
}

template<class Derived,class Device,class Return,class Args...>void BDPIPortWrapper<Derived,Device,Return,Args...>::
	implementClose()
{
	m_derived.close();
}


template<typename Data,typename Address>class MemoryPort : public BDPIPortWrapper<
	MemoryPort<Data,Address>,
	Data,
	Address,
	Data>
{
public:

private:

}



#endif /* MEMSCANCHAIN_BDPIPORTWRAPPER_HPP_ */
