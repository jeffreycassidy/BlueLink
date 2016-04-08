/*
 * AFU.cpp
 *
 *  Created on: Apr 5, 2016
 *      Author: jcassidy
 */

#include "AFU.hpp"
#include "WED.hpp"
#include <iostream>
#include <iomanip>

extern "C" {
	#include <libcxl.h>
}

using namespace std;

const std::map<unsigned,std::string> AFU::mode_names
{
	std::make_pair(CXL_MODE_DEDICATED,"Dedicated"),
	std::make_pair(CXL_MODE_DIRECTED,"AFU-Directed"),
	std::make_pair(CXL_MODE_TIME_SLICED,"Time-sliced")
};

AFU::AFU()
{
}


AFU::AFU(const char* devstr) : m_devstr(devstr)
{
	open();
}

AFU::AFU(const std::string devstr) : m_devstr(devstr)
{
	open();
}

AFU::AFU(AFU&& afu)
{
	swap(afu.m_devstr,m_devstr);

	m_afu_h = afu.m_afu_h;
	afu.m_afu_h = nullptr;
}

AFU::~AFU()
{
	close();
}

void AFU::open()
{
	m_afu_h = cxl_afu_open_dev((char*)m_devstr.c_str());
	if (!m_afu_h)
		throw InvalidDevice(m_devstr);
}

void AFU::open(const std::string devstr)
{
	m_devstr=devstr;
	open();
}

void AFU::close()
{
	if(m_afu_h)
	{
		mmio_unmap();
		cxl_afu_free(m_afu_h);
	}
	m_devstr.clear();
	m_afu_h=nullptr;
}

void AFU::start(void* p)
{
	if(!m_afu_h)
		throw InvalidDevice(m_devstr);

	int ret = cxl_afu_attach(m_afu_h,(__u64)p);
	if (ret)
	{
		std::cerr << "cxl_afu_attach failed with error code: " << ret << std::endl;
		std::cerr << "  strerror(errno): " << strerror(errno) << std::endl;
		throw InvalidDevice(m_devstr);
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
	if ((ret=cxl_mmio_map(m_afu_h,CXL_MMIO_BIG_ENDIAN)))
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
	if (!m_afu_h)
		throw InvalidDevice(m_devstr);
	if ((ret=cxl_mmio_read64(m_afu_h,offset,&t)))
	{
		cout << "cxl_mmio_read64 returned a nonzero exit code: " << ret << endl;
		cout << "  error string: " << strerror(errno) << endl;
	}
	return t;
}


uint32_t AFU::mmio_read32(const unsigned offset) const
{
	uint32_t t;
	int ret;
	if (!m_afu_h)
		throw InvalidDevice(m_devstr);
	if ((ret=cxl_mmio_read32(m_afu_h,offset,&t)))
	{
		cout << "cxl_mmio_read32 returned a nonzero exit code: " << ret << endl;
		cout << "  error string: " << strerror(errno) << endl;
	}
	return t;
}

void AFU::mmio_write64(const unsigned offset,const uint64_t data) const
{
	int ret;
	if (!m_afu_h)
		throw InvalidDevice(m_devstr);
	if ((ret=cxl_mmio_write64(m_afu_h,offset,data)))
	{
		cout << "cxl_mmio_write64 returned a nonzero exit code: " << ret << endl;
		cout << "  error string: " << strerror(errno) << endl;
	}
}

void AFU::mmio_write32(const unsigned offset,const uint32_t data) const
{
	int ret;
	if (!m_afu_h)
		throw InvalidDevice(m_devstr);
	if ((ret=cxl_mmio_write32(m_afu_h,offset,data)))
	{
		cout << "cxl_mmio_write32 returned a nonzero exit code: " << ret << endl;
		cout << "  error string: " << strerror(errno) << endl;
	}
}

void AFU::mmio_unmap()
{
	if (cxl_mmio_unmap(m_afu_h))
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
	int ret = cxl_read_event(m_afu_h,&e);

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
	if ((ret=cxl_get_api_version(m_afu_h,&val)))
		throw AFUAttrGetFail("");
	else
		cout << "  API version: " << hex << val << endl;

	if((ret=cxl_get_api_version_compatible(m_afu_h,&val)))
		throw AFUAttrGetFail("");
	else
		cout << "  API version compatible: " << hex << val << endl;

	//int cxl_get_cr_class(struct cxl_afu_h *afu, long cr_num, long *valp);
	//int cxl_get_cr_device(struct cxl_afu_h *afu, long cr_num, long *valp);
	//int cxl_get_cr_vendor(struct cxl_afu_h *afu, long cr_num, long *valp);

	if((ret=cxl_get_irqs_max(m_afu_h,&val)))
		throw AFUAttrGetFail("");
	else
		cout << "  Max irqs: " << dec << val << endl;

	if((ret=cxl_get_irqs_min(m_afu_h,&val)))
		throw AFUAttrGetFail("");
	else
			cout << "  Min irqs: " << val << endl;

	if((ret=cxl_get_mmio_size(m_afu_h,&val)))
		throw AFUAttrGetFail("");
	else
		cout << "  MMIO size: 0x" << hex << setw(6) << val << endl;

	if((ret=cxl_get_mode(m_afu_h,&val)))
		throw AFUAttrGetFail("");
	else
			cout << "  Mode: " << val << endl;

	if((ret=cxl_get_modes_supported(m_afu_h,&val)))
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

	if((ret=cxl_get_mode(m_afu_h,&val)))
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



