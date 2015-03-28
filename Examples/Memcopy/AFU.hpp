/*
 * AFU.hpp
 *
 *  Created on: Mar 26, 2015
 *      Author: jcassidy
 */

#ifndef AFU_HPP_
#define AFU_HPP_

#include <exception>
#include <string>

#include "WED.hpp"

extern "C" {
	#include <libcxl.h>
}

class AFU {
	std::string devstr_="";
	struct cxl_afu_h* afu_h_=nullptr;

	void open();
	void close();
	void mmio_map();
	void mmio_unmap();



	void start_sim();

public:
	class InvalidDevice : public std::exception {
	public:
		InvalidDevice(const std::string devstr) : s("AFU::InvalidDevice while opening "+devstr){}
		virtual const char* what() const noexcept { return s.c_str(); }

	private:
		std::string s;
	};

	// ownership semantics: move but no copy
	AFU(const AFU&) = delete;
	AFU(AFU&&);

	AFU(){};
	AFU(char*);
	AFU(std::string devstr);

	void start(const WED&);
	void end();

	void await_event();

	~AFU();
};

#include <iomanip>

using namespace std;

AFU::AFU(char* devstr) : devstr_(devstr)
{
	open();
}

AFU::AFU(const std::string devstr) : devstr_(devstr)
{
	open();
}

AFU::AFU(AFU&& afu)
{
	swap(afu.devstr_,devstr_);

	afu_h_ = afu.afu_h_;
	afu.afu_h_ = nullptr;
}

AFU::~AFU()
{
	close();
}

void AFU::open()
{
	afu_h_ = cxl_afu_open_dev((char*)devstr_.c_str());
	if (!afu_h_)
		throw InvalidDevice(devstr_);
}

void AFU::close()
{
	if(afu_h_)
		cxl_afu_free(afu_h_);
	devstr_.clear();
	afu_h_=nullptr;
}

void AFU::start(const WED& w)
{
	if(!afu_h_)
		throw InvalidDevice(devstr_);
	cxl_afu_attach(afu_h_,(__u64)w.get());
}

void AFU::end()
{

}

void AFU::mmio_map()
{
}

void AFU::mmio_unmap()
{
	cxl_mmio_unmap(afu_h_);
}

void AFU::await_event()
{
	while(!cxl_pending_event(afu_h_))
	{
		usleep(10000);			// pause 10ms
	}

	struct cxl_event e;
	int ret = cxl_read_event(afu_h_,&e);

	if (ret == 0)
	{
		cout << "Received event: ";
		switch(e.header.type)
		{
		case CXL_EVENT_RESERVED:
			cout << "(reserved)"; break;
		case CXL_EVENT_AFU_INTERRUPT:
			cout << "AFU Interrupt code " << e.irq.irq << " with flags " << hex << setw(4) << e.irq.flags; break;
		case CXL_EVENT_DATA_STORAGE:
			cout << "Data storage"; break;
		case CXL_EVENT_AFU_ERROR:
			cout << "AFU error code " << e.afu_error.error << " with flags " << e.afu_error.flags; break;
		}
		cout << endl;
	}
	else
		cout << "Unexpected return from cxl_read_event: " << ret << endl;
}

#endif /* AFU_HPP_ */
