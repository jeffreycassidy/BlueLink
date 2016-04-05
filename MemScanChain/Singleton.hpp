/*
 * Singleton.hpp
 *
 *  Created on: Apr 2, 2016
 *      Author: jcassidy
 */

#ifndef MEMSCANCHAIN_SINGLETON_HPP_
#define MEMSCANCHAIN_SINGLETON_HPP_

#include <iostream>

template<class T>class Singleton
{
public:
	static T& instance();

private:
	Singleton();

	static T			m_instance;
	static bool 		m_initialized;
};

template<class T>bool Singleton<T>::m_initialized=false;
template<class T>T Singleton<T>::m_instance;

template<class T>T& Singleton<T>::instance()
{
	if (!m_initialized)
	{
		std::cout << "Singleton is initializing itself" << std::endl;
		m_instance = T();
		m_initialized = true;
	}
	return m_instance;
}




#endif /* MEMSCANCHAIN_SINGLETON_HPP_ */
