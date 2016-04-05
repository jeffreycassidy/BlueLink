/*
 * WED.hpp
 *
 *  Created on: Mar 26, 2015
 *      Author: jcassidy
 */

#ifndef WED_HPP_
#define WED_HPP_

#include <utility>

#include <array>
#include <boost/range.hpp>

#include <boost/range/algorithm.hpp>
#include <boost/align/is_aligned.hpp>

/** Simplest possible WED container, just an opaque non-copyable wrapper around a void*.
 *
 */

class WED
{
public:
    void* get() const { return reinterpret_cast<void*>(p_); }

    WED(WED&&) = delete;
    WED(const WED&) = delete;
    WED& operator=(const WED&) = delete;

protected:
    explicit WED(unsigned char* p) : p_(p)
    {
    	assert(boost::alignment::is_aligned(128,p_));
    }

private:
    unsigned char* p_=nullptr;
};


/** A more sophisticated WED container, knowing the contained type, size, and alignment and providing the dereference operators.
 */

template<class T,std::size_t Nb=128,std::size_t Align=Nb>class WEDBase : public WED
{
public:
    typedef T type;

    BOOST_STATIC_ASSERT_MSG(sizeof(T) == Nb,"Type does not match specified size in WEDBase");

    explicit WEDBase(T* p) : WED(reinterpret_cast<unsigned char*>(p))
        {
            boost::fill(bytes(),0);
        }

    T& operator*(){ return *static_cast<T*>(get()); }
    const T& operator*() const { return *static_cast<T*>(get()); }

    T* operator->(){ return static_cast<T*>(get()); }
    const T* operator->() const { return static_cast<const T*>(get()); }

    boost::iterator_range<unsigned char*> bytes()
        { unsigned char* p = reinterpret_cast<unsigned char*>(get()); return boost::iterator_range<unsigned char*>(p,p+size_); }

    boost::iterator_range<const unsigned char*> bytes() const
        { const unsigned char *p = reinterpret_cast<unsigned const char*>(get()); return boost::iterator_range<const unsigned char*>(p,p+size_); }

    std::size_t payloadSize() const { return sizeof(T); }

protected:
    static constexpr std::size_t size_=Nb;
    static constexpr std::size_t align_=Align;
};

template<class T,std::size_t size,std::size_t align=size>class StackWED : public WEDBase<T,size,align>
{
private:
    static constexpr std::size_t alloc_=size+align;

public:

    StackWED() : WEDBase<T,size,align>(reinterpret_cast<T*>(v.begin() + offset())){}
    ~StackWED(){}

    // get the base of the unaligned storage
    const void* base() const { return &v[0]; }

    // check how many bytes are allocated in total
    std::size_t allocated() const { return alloc_; }

    // get the offset from the base to the start of actual data
//    std::size_t offset() const
//        { return reinterpret_cast<const char*>(WED::get())-&v[0]; }

    std::size_t offset() const
        { return align - (reinterpret_cast<std::size_t>(v.begin()) % align); }

private:
    std::array<char,alloc_> v;
};


#endif /* WED_HPP_ */
