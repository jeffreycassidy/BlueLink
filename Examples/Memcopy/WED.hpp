/*
 * WED.hpp
 *
 *  Created on: Mar 26, 2015
 *      Author: jcassidy
 */

#ifndef WED_HPP_
#define WED_HPP_

#include <utility>

class WED {
	static constexpr size_t size_=128;
	static constexpr size_t align_=128;
	static constexpr size_t mask_=0x7f;
public:

	WED();
	WED(WED&&);
	~WED();

	void* get() const { return p_; }

private:
	void* p_=nullptr;
};

WED::WED()
{
	int ret = posix_memalign(&p_,align_,size_);
	if (ret || !p_ || (mask_ & (size_t)(p_)))
		throw std::bad_alloc();
}

WED::WED(WED&& w)
{
	p_=nullptr;
	std::swap(p_,w.p_);
}

WED::~WED()
{
	if(p_)
		free(p_);
}

#endif /* WED_HPP_ */
