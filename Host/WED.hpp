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

#include <boost/align/align.hpp>

/** Simplest possible WED container, just an opaque non-copyable wrapper around a void*.
 *
 */

class WED
{
public:
    void* get() const { return reinterpret_cast<void*>(m_p); }

    WED(WED&&) = delete;
    WED(const WED&) = delete;
    WED& operator=(const WED&) = delete;

protected:
    explicit WED(void* p) : m_p(p)
    {
    }

    void set(void* p){ m_p=p; }

private:
    void* m_p=nullptr;
};


/** A more sophisticated WED container, knowing the contained type, size, and alignment and providing the dereference operators.
 */

template<class T,std::size_t TSize=128,std::size_t TAlign=TSize>class WEDBase : public WED
{
public:
    typedef T type;

    BOOST_STATIC_ASSERT_MSG(sizeof(T) == TSize,"Type does not match specified size in WEDBase");

    WEDBase() : WED(nullptr){}

    explicit WEDBase(T* p) : WED(reinterpret_cast<unsigned char*>(p))
        {
            boost::fill(bytes(),0);
        }

    T& operator*(){ return *static_cast<T*>(get()); }
    const T& operator*() const { return *static_cast<T*>(get()); }

    T* operator->(){ return static_cast<T*>(get()); }
    const T* operator->() const { return static_cast<const T*>(get()); }

    boost::iterator_range<unsigned char*> bytes()
        { unsigned char* p = reinterpret_cast<unsigned char*>(get()); return boost::iterator_range<unsigned char*>(p,p+Size); }

    boost::iterator_range<const unsigned char*> bytes() const
        { const unsigned char *p = reinterpret_cast<unsigned const char*>(get()); return boost::iterator_range<const unsigned char*>(p,p+Size); }

    std::size_t payloadSize() const { return sizeof(T); }

protected:
    static constexpr std::size_t Size=TSize;
    static constexpr std::size_t Align=TAlign;
};

template<class T,std::size_t TSize,std::size_t Align=128>class StackWED : public WEDBase<T,TSize,Align>
{
private:
    static constexpr std::size_t AllocSize=TSize+Align;

public:

    BOOST_STATIC_ASSERT(TSize==sizeof(T));

    StackWED()
		{
    		std::size_t space=AllocSize;
    		void* ptr = v.data();
    		boost::alignment::align(Align,sizeof(T),ptr,space);

    		assert(ptr);
    		assert(space>=sizeof(T));
    		assert(boost::alignment::is_aligned(Align,ptr));

    		WEDBase<T,sizeof(T),Align>::set(reinterpret_cast<T*>(ptr));

    		boost::fill(v,0);

		}

    ~StackWED()
    {}

private:
    std::array<uint8_t,AllocSize> v;
};


#endif /* WED_HPP_ */
