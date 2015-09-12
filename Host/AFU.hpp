/*
 * AFU.hpp
 *
 *  Created on: Mar 26, 2015
 *      Author: jcassidy
 */

#ifndef AFU_HPP_
#define AFU_HPP_

#include <exception>
#include <iostream>
#include <errno.h>
#include <unistd.h>
#include <string>
#include <string.h>
#include <vector>

#include "WED.hpp"

extern "C" {
	#include <libcxl.h>
	#include <sys/errno.h>

	extern int errno;
}

constexpr std::size_t CACHELINE_BYTES=128;

class AFU {
	std::string devstr_="";
	struct cxl_afu_h* afu_h_=nullptr;

	void open();
	void mmio_map();
	void mmio_unmap();


	static const std::vector<std::pair<unsigned,std::string>> mode_names;

public:
	class InvalidDevice : public std::exception {
	public:
		InvalidDevice(const std::string devstr) : s("AFU::InvalidDevice while opening "+devstr){}
		virtual const char* what() const noexcept { return s.c_str(); }

	private:
		std::string s;
	};

	class AFUAttrGetFail : public std::exception {
	public:
		AFUAttrGetFail(const std::string) : s_("AFU::AttrGetFail"){}
		virtual const char* what() const noexcept { return s_.c_str(); }
	private:
		std::string s_;
	};

	class MMIOMapFail : public std::exception {
	public:
		MMIOMapFail(){}
		virtual const char* what() const noexcept { return strerror(errno); }
	};

	class MMIOUnmapFail : public std::exception {
	public:
		MMIOUnmapFail(){}
		virtual const char* what() const noexcept { return strerror(errno); }
	};

	// ownership semantics: move but no copy
	AFU(const AFU&) = delete;
	AFU(AFU&&);

	AFU(){};
	AFU(char*);
	AFU(std::string devstr);

	void open(std::string);
	void close();

	void start(void*);
	void start(const WED&);

	void print_details() const;

	uint64_t mmio_read64(unsigned) const;
	void mmio_write64(unsigned,uint64_t) const;

	void await_event(unsigned) const;

	~AFU();
};

const std::vector<std::pair<unsigned,std::string>> AFU::mode_names
{
	std::make_pair(CXL_MODE_DEDICATED,"Dedicated"),
	std::make_pair(CXL_MODE_DIRECTED,"AFU-Directed"),
	std::make_pair(CXL_MODE_TIME_SLICED,"Time-sliced")
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

void AFU::open(const std::string devstr)
{
	devstr_=devstr;
	open();
}

void AFU::close()
{
	if(afu_h_)
	{
		mmio_unmap();
		cxl_afu_free(afu_h_);
	}
	devstr_.clear();
	afu_h_=nullptr;
}

void AFU::start(void* p)
{
	if(!afu_h_)
		throw InvalidDevice(devstr_);

	int ret = cxl_afu_attach(afu_h_,(__u64)p);
	if (ret)
	{
		std::cerr << "cxl_afu_attach failed with error code: " << ret << std::endl;
		std::cerr << "  strerror(errno): " << strerror(errno) << std::endl;
		throw InvalidDevice(devstr_);
	}
	cout << "AFU started with WED " << p << endl;
	mmio_map();
	cout << "  and MMIO mapped" << endl;
}

void AFU::start(const WED& w)
{
	start(w.get());

}


void AFU::mmio_map()
{
	int ret;
	if ((ret=cxl_mmio_map(afu_h_,CXL_MMIO_BIG_ENDIAN)))
	{
		cerr << "cxl_mmio_map failed with error code: " << ret << endl;
		cerr << "  strerror(errno): " << strerror(errno) << endl;
		throw MMIOMapFail();
	}
}

uint64_t AFU::mmio_read64(const unsigned offset) const
{
	uint64_t t;
	int ret;
	if (!afu_h_)
		throw InvalidDevice(devstr_);
	if ((ret=cxl_mmio_read64(afu_h_,offset,&t)))
	{
		cout << "cxl_mmio_read64 returned a nonzero exit code: " << ret << endl;
		cout << "  error string: " << strerror(errno) << endl;
	}
	return t;
}

void AFU::mmio_write64(const unsigned offset,const uint64_t data) const
{
	int ret;
	if (!afu_h_)
		throw InvalidDevice(devstr_);
	if ((ret=cxl_mmio_write64(afu_h_,offset,data)))
	{
		cout << "cxl_mmio_write64 returned a nonzero exit code: " << ret << endl;
		cout << "  error string: " << strerror(errno) << endl;
	}
}

void AFU::mmio_unmap()
{
	if (cxl_mmio_unmap(afu_h_))
		throw MMIOUnmapFail();
}

void AFU::await_event(unsigned timeout_ms) const
{
	unsigned i;
	for(i=0;i<timeout_ms /* && !cxl_event_pending(afu_h_) */; ++i)
	{
		usleep(1000);			// pause 10ms
	}

	if (i==timeout_ms)
	{
		cout << "  No event received, timed out after " << timeout_ms << " ms" << endl;
		return;
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

void AFU::print_details() const
{
	cout << "AFU details: " << endl;
#ifdef HARDWARE

	int ret;
	long val;
	if ((ret=cxl_get_api_version(afu_h_,&val)))
		throw AFUAttrGetFail("");
	else
		cout << "  API version: " << hex << val << endl;

	if((ret=cxl_get_api_version_compatible(afu_h_,&val)))
		throw AFUAttrGetFail("");
	else
		cout << "  API version compatible: " << hex << val << endl;

	//int cxl_get_cr_class(struct cxl_afu_h *afu, long cr_num, long *valp);
	//int cxl_get_cr_device(struct cxl_afu_h *afu, long cr_num, long *valp);
	//int cxl_get_cr_vendor(struct cxl_afu_h *afu, long cr_num, long *valp);

	if((ret=cxl_get_irqs_max(afu_h_,&val)))
		throw AFUAttrGetFail("");
	else
		cout << "  Max irqs: " << dec << val << endl;

	if((ret=cxl_get_irqs_min(afu_h_,&val)))
		throw AFUAttrGetFail("");
	else
			cout << "  Min irqs: " << val << endl;

	if((ret=cxl_get_mmio_size(afu_h_,&val)))
		throw AFUAttrGetFail("");
	else
		cout << "  MMIO size: 0x" << hex << setw(6) << val << endl;

	if((ret=cxl_get_mode(afu_h_,&val)))
		throw AFUAttrGetFail("");
	else
			cout << "  Mode: " << val << endl;

	if((ret=cxl_get_modes_supported(afu_h_,&val)))
		throw AFUAttrGetFail("");
	else
	{
		cout << "  Modes supported: " << hex << val << " (";
		for(const auto& p : mode_names)
		{
			if (val & p.first)
				cout << ' ' << p.second;
		}
		cout << ")" << endl;
	}

	if((ret=cxl_get_mode(afu_h_,&val)))
		throw AFUAttrGetFail("");
	else
	{
		cout << "  Mode: ";
		unsigned i;
		for(i=0;i<mode_names.size() && val != mode_names[i].first;++i){}

		if (i==mode_names.size())
			cout << "UNKNOWN (" << hex << val << ")" << endl;
		else
			cout << mode_names[i].second << endl;
	}


	//int cxl_get_prefault_mode(struct cxl_afu_h *afu, enum cxl_prefault_mode *valp);
	//int cxl_get_pp_mmio_len(afu_h_,&val);
	//int cxl_get_pp_mmio_off(afu_h_,&val);

	//int cxl_get_base_image(struct cxl_adapter_h *adapter, long *valp);
	//int cxl_get_caia_version(struct cxl_adapter_h *adapter, long *majorp,
	//			 long *minorp);
	//int cxl_get_image_loaded(struct cxl_adapter_h *adapter, enum cxl_image *valp);
	//int cxl_get_psl_revision(struct cxl_adapter_h *adapter, long *valp);
#else
	cout << "  ** Not available in simulation **" << endl;
#endif
}

#endif /* AFU_HPP_ */
