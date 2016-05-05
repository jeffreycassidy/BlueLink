/*
 * BlockMapAFUBase.hpp
 *
 *  Created on: Apr 22, 2016
 *      Author: jcassidy
 */

#ifndef MODULES_HENYEYGREENSTEIN_BLOCKMAPAFUBASE_HPP_
#define MODULES_HENYEYGREENSTEIN_BLOCKMAPAFUBASE_HPP_

#include <BlueLink/Host/AFU.hpp>
#include <BlueLink/Host/WED.hpp>

struct BlockMapParam {
	void*		dst;
	uint64_t	oSize;
	const void*	src;
	uint64_t	iSize;
};

struct BlockMapWED
{
	BlockMapParam	param;
	uint64_t		pad[12];
};

class BlockMapAFUBase : public AFU
{
public:
	BlockMapAFUBase(const char* devStr) : AFU(devStr){}
	enum Status { Resetting=0, Ready=1, Waiting=2, Running=3, Done=4 };

	void start();						// starts the AFU, reads WED, and waits for run()

	void awaitReady();

	void run();							// starts the block map
	void terminate();					// send termination pulse to AFU (allow to finish, kills MMIO)

	Status status() const;

protected:
	StackWED<BlockMapWED,128,128> m_wed;

private:

	unsigned m_usecDelayTime=1000;
	unsigned m_timeoutDelay=2000;

	unsigned m_waitTimeoutSteps=10;
	unsigned m_waitSleep=100000;


	bool m_verbose=true;
};



#endif /* MODULES_HENYEYGREENSTEIN_BLOCKMAPAFUBASE_HPP_ */
