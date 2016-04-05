/*
 * aligned_allocator.hpp
 *
 *  Created on: Jul 24, 2015
 *      Author: jcassidy
 */

#ifndef ALIGNED_ALLOCATOR_HPP_
#define ALIGNED_ALLOCATOR_HPP_

#include <cstdlib>

/** Superficially, this appears to duplicate boost::aligned_allocator. However, Boost requires an attribute on the type which is a
 * bit of a pain.
 *
 * Align is specified in bytes
 *
 */

template<typename T,std::size_t align>class aligned_allocator
{
public:
    typedef T value_type;
    typedef T* pointer;
    typedef T& reference;
    typedef const T* const_pointer;
    typedef const T& const_reference;
    typedef std::size_t size_type;
    typedef std::ptrdiff_t difference_type;

    aligned_allocator(){}
    aligned_allocator(const aligned_allocator&) = default;
    template<class U>aligned_allocator(const aligned_allocator<U,align>& u){}

    template<typename U>struct rebind { typedef aligned_allocator<U,align> other; };

    ~aligned_allocator(){}

    pointer 		address(reference x) 		const { return &x; }
    const_pointer 	address(const_reference x) 	const { return &x; }

    pointer allocate(size_type n,std::allocator<void>::const_pointer hint=nullptr)
    {
        void *p=nullptr;
        int st = posix_memalign(&p,align,n*sizeof(T));

        if (st != 0)
            throw std::bad_alloc();

        if (!p)
            throw std::bad_alloc();

        assert(reinterpret_cast<std::size_t>(p) % align == 0);
        return static_cast<T*>(p);
    }

    void deallocate(pointer p,size_type n)
    {
        free(p);
    }

    size_type max_size() const { return -1U; }

    template<class U>void destroy(U* p)
    {
        p->~U();
    }

    template<class U>void construct(U* p)
    {
    	::new((void*)p) U;
    }

    template<class U,class... Args>void construct(U* p,Args&&...args)
    {
        ::new((void*)p) U (std::forward<Args...>(args...));
    }
};



#endif /* ALIGNED_ALLOCATOR_HPP_ */
