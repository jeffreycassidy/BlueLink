/*
 * BlockMapAFUBase.cpp
 *
 *  Created on: Apr 22, 2016
 *      Author: jcassidy
 */

#include "BlockMapAFUBase.hpp"

#include <boost/align/is_aligned.hpp>
#include <iostream>
#include <iomanip>

using namespace std;

void BlockMapAFUBase::start()
{
	if(!boost::alignment::is_aligned(128,m_wed.get()))
		throw std::logic_error("Unaligned WED pointer");
	if(!boost::alignment::is_aligned(128,m_wed->param.src))
		throw std::logic_error("Unaligned src");
	if(!boost::alignment::is_aligned(128,m_wed->param.dst))
		throw std::logic_error("Unaligned dst");
	if(m_wed->param.iSize % 128 != 0)
		throw std::logic_error("Unaligned read transfer size");
	if(m_wed->param.oSize % 128 != 0)
		throw std::logic_error("Unaligned write transfer size");

	AFU::start(m_wed.get());

	Status st=Resetting;

	unsigned N;
	for(N=0;N<100 && (st=status()) != Waiting;++N)
	{
		cout << "  Waiting for 'waiting' status (st=" << st << " looking for " << Waiting << ")" << endl;
		usleep(m_usecDelayTime);
	}

	if (m_verbose)
		for(unsigned i=0;i<8;++i)
			cout << "MMIO[" << setw(6) << hex << (i<<3) << "] " << setw(16) << hex << AFU::mmio_read64(i<<3) << endl;
}

void BlockMapAFUBase::awaitReady()
{
	unsigned i;
	for(i=0;i<m_waitTimeoutSteps && (mmio_read64(0)&0xff) != Waiting;++i)
	{
		usleep(m_waitSleep);
	}
	if (i == m_waitTimeoutSteps)
		cout << "ERROR: Timeout while waiting for Waiting status" << endl;
}

void BlockMapAFUBase::run()
{
	cout << "Starting" << endl;
	AFU::mmio_write64(0,0x0ULL);		// start signal: write 0 to MMIO 0

	unsigned N;
	Status st=Resetting;

	for(N=0;N < m_timeoutDelay && (st=Status(AFU::mmio_read64(0)&0xff)) != Done;++N)	// wait for done status
	{
		cout << "  status " << hex << st << " input: " << dec << AFU::mmio_read64(0x38) << "/" << AFU::mmio_read64(0x30) << "  output: " << AFU::mmio_read64(0x28) << "/" << AFU::mmio_read64(0x20) << endl << flush;
		usleep(m_usecDelayTime);
	}

	if (N == m_timeoutDelay)
		cout << "ERROR: Timeout waiting for done status" << endl;
}

void BlockMapAFUBase::terminate()
{
	cout << "Terminating" << endl;
	AFU::mmio_write64(0,0x1ULL);
}


BlockMapAFUBase::Status BlockMapAFUBase::status() const
{
	return BlockMapAFUBase::Status(mmio_read64(0) & 0xff);
}
