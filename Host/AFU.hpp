/*
 * AFU.hpp
 *
 *  Created on: Mar 26, 2015
 *      Author: jcassidy
 */

#ifndef AFU_HPP_
#define AFU_HPP_

#include <exception>
#include <errno.h>
#include <unistd.h>
#include <string>

#include <map>


#include <string.h>			// for strerror
#include <sys/errno.h>

class WED;

class AFU {

public:
	class InvalidDevice;
	class AttrGetFail;
	class MMIOMapFail;
	class MMIOUnmapFail;

	// ownership semantics: move but no copy
	AFU(const AFU&) = delete;
	AFU(AFU&&);

	AFU();
	AFU(const char* devstr);
	AFU(std::string devstr);

	void open(std::string);
	void close();

	void start(void*);
	void start(const WED&);

	void print_details() const;

	/// MMIO reads and writes, with offset specified in bytes
	uint64_t mmio_read64(unsigned) const;
	uint32_t mmio_read32(unsigned) const;
	void mmio_write64(unsigned,uint64_t) const;
	void mmio_write32(unsigned,uint32_t) const;

	void await_event(unsigned) const;

	~AFU();

	static constexpr std::size_t CACHELINE_BYTES=128;

private:
	std::string 		m_devstr="";
	struct cxl_afu_h* 	m_afu_h=nullptr;

	void open();
	void mmio_map();
	void mmio_unmap();

	static const std::map<unsigned,std::string> mode_names;
};



class AFU::InvalidDevice : public std::exception {
public:
	InvalidDevice(const std::string devstr) : s("AFU::InvalidDevice while opening "+devstr){}
	virtual const char* what() const noexcept { return s.c_str(); }

private:
	std::string s;
};

class AFU::AttrGetFail : public std::exception {
public:
	AttrGetFail(const std::string) : s_("AFU::AttrGetFail"){}
	virtual const char* what() const noexcept { return s_.c_str(); }
private:
	std::string s_;
};

class AFU::MMIOMapFail : public std::exception {
public:
	MMIOMapFail(){}
	virtual const char* what() const noexcept { return strerror(errno); }
};

class AFU::MMIOUnmapFail : public std::exception {
public:
	MMIOUnmapFail(){}
	virtual const char* what() const noexcept { return strerror(errno); }
};



#endif /* AFU_HPP_ */
