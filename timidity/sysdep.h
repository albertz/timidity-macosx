/*
    TiMidity++ -- MIDI to WAVE converter and player
    Copyright (C) 1999-2002 Masanao Izumo <mo@goice.co.jp>
    Copyright (C) 1995 Tuukka Toivonen <tt@cgs.fi>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

#ifndef SYSDEP_H_INCLUDED
#define SYSDEP_H_INCLUDED 1

#if defined(__WIN32__) && !defined(__W32__)
#define __W32__
#endif


/* The size of the internal buffer is 2^AUDIO_BUFFER_BITS samples.
   This determines maximum number of samples ever computed in a row.

   For Linux and FreeBSD users:

   This also specifies the size of the buffer fragment.  A smaller
   fragment gives a faster response in interactive mode -- 10 or 11 is
   probably a good number. Unfortunately some sound cards emit a click
   when switching DMA buffers. If this happens to you, try increasing
   this number to reduce the frequency of the clicks.

   For other systems:

   You should probably use a larger number for improved performance.

*/
#ifndef DEFAULT_AUDIO_BUFFER_BITS
# ifdef __W32__
#  define DEFAULT_AUDIO_BUFFER_BITS 12
# else
#  define DEFAULT_AUDIO_BUFFER_BITS 11
# endif
#endif


#ifndef NO_VOLATILE
# define VOLATILE_TOUCH(val) /* do nothing */
# define VOLATILE volatile
#else
extern int volatile_touch(void* dmy);
# define VOLATILE_TOUCH(val) volatile_touch(&(val))
# define VOLATILE
#endif /* NO_VOLATILE */

/* Byte order */
#ifdef WORDS_BIGENDIAN
# ifndef BIG_ENDIAN
#  define BIG_ENDIAN 4321
# endif
# undef LITTLE_ENDIAN
#else
# undef BIG_ENDIAN
# ifndef LITTLE_ENDIAN
#  define LITTLE_ENDIAN 1234
# endif
#endif


/* integer type definitions: ISO C now knows a better way */
#if __STDC_VERSION__ == 199901L
#include <stdint.h> // int types are defined here
typedef uint_fast64_t uint64;
typedef  int_fast64_t  int64;
typedef uint_fast32_t uint32;
typedef  int_fast32_t  int32;
typedef uint_fast16_t uint16;
typedef  int_fast16_t  int16;
typedef uint_fast8_t  uint8;
typedef  int_fast8_t   int8;
#else /* not C99 */

/* DEC MMS has 64 bit long words */
/* Linux-Axp has also 64 bit long words */
#if defined(DEC) || defined(__alpha__)
typedef unsigned int uint32;
typedef int int32;
#else
#if !defined(_APPLE_) && !defined(_UINT32) // vavi
typedef unsigned long uint32;
#else
typedef uint32_t uint32;
#endif
#define _UINT32
typedef long int32;
#endif
#ifdef HPUX
typedef unsigned short uint16;
typedef short int16;
typedef unsigned char uint8;
typedef char int8;
#else
typedef unsigned short uint16;
typedef signed short int16;
typedef unsigned char uint8;
typedef signed char int8;
#endif

#if __GNUC__
typedef long long int int64;
#elif _MSC_VER
typedef _int64 int64;
#endif
#endif /* C99 */


/* Instrument files are little-endian, MIDI files big-endian, so we
   need to do some conversions. */
#define XCHG_SHORT(x) ((((x)&0xFF)<<8) | (((x)>>8)&0xFF))
#if defined(__i486__) && !defined(__i386__)
# define XCHG_LONG(x) \
     ({ int32 __value; \
        asm ("bswap %1; movl %1,%0" : "=g" (__value) : "r" (x)); \
       __value; })
#else
# define XCHG_LONG(x) ((((x)&0xFF)<<24) | \
		      (((x)&0xFF00)<<8) | \
		      (((x)&0xFF0000)>>8) | \
		      (((x)>>24)&0xFF))
#endif

#ifdef LITTLE_ENDIAN
# define LE_SHORT(x) (x)
# define LE_LONG(x) (x)
# ifdef __FreeBSD__
#  define BE_SHORT(x) __byte_swap_word(x)
#  define BE_LONG(x) __byte_swap_long(x)
# else
#  define BE_SHORT(x) XCHG_SHORT(x)
#  define BE_LONG(x) XCHG_LONG(x)
# endif
#else /* BIG_ENDIAN */
# define BE_SHORT(x) (x)
# define BE_LONG(x) (x)
# ifdef __FreeBSD__
#  define LE_SHORT(x) __byte_swap_word(x)
#  define LE_LONG(x) __byte_swap_long(x)
# else
#  define LE_SHORT(x) XCHG_SHORT(x)
#  define LE_LONG(x) XCHG_LONG(x)
# endif /* __FreeBSD__ */
#endif /* LITTLE_ENDIAN */

/* max_channels is defined in "timidity.h" */
#if MAX_CHANNELS <= 32
typedef struct _ChannelBitMask
{
    uint32 b; /* 32-bit bitvector */
} ChannelBitMask;
#define CLEAR_CHANNELMASK(bits)		((bits).b = 0)
#define FILL_CHANNELMASK(bits)		((bits).b = ~0)
#define IS_SET_CHANNELMASK(bits, c) ((bits).b &   (1u << (c)))
#define SET_CHANNELMASK(bits, c)    ((bits).b |=  (1u << (c)))
#define UNSET_CHANNELMASK(bits, c)  ((bits).b &= ~(1u << (c)))
#define TOGGLE_CHANNELMASK(bits, c) ((bits).b ^=  (1u << (c)))
#define COPY_CHANNELMASK(dest, src)	((dest).b = (src).b)
#define REVERSE_CHANNELMASK(bits)	((bits).b = ~(bits).b)
#define COMPARE_CHANNELMASK(bitsA, bitsB)	((bitsA).b == (bitsB).b)
#else
typedef struct _ChannelBitMask
{
    uint32 b[8];		/* 256-bit bitvector */
} ChannelBitMask;
#define CLEAR_CHANNELMASK(bits) \
	memset((bits).b, 0, sizeof(ChannelBitMask));
#define FILL_CHANNELMASK(bits) \
	memset((bits).b, 0xFF, sizeof(ChannelBitMask));
#define IS_SET_CHANNELMASK(bits, c) \
	((bits).b[((c) >> 5) & 0x7] &   (1u << ((c) & 0x1F)))
#define SET_CHANNELMASK(bits, c) \
	((bits).b[((c) >> 5) & 0x7] |=  (1u << ((c) & 0x1F)))
#define UNSET_CHANNELMASK(bits, c) \
	((bits).b[((c) >> 5) & 0x7] &= ~(1u << ((c) & 0x1F)))
#define TOGGLE_CHANNELMASK(bits, c) \
	((bits).b[((c) >> 5) & 0x7] ^=  (1u << ((c) & 0x1F)))
#define COPY_CHANNELMASK(dest, src) \
	memcpy(&(dest), &(src), sizeof(ChannelBitMask))
#define REVERSE_CHANNELMASK(bits) \
	((bits).b[((c) >> 5) & 0x7] = ~(bits).b[((c) >> 5) & 0x7])
#define COMPARE_CHANNELMASK(bitsA, bitsB) \
	(memcmp(bitsA, bitsB, sizeof(ChannelBitMask)) == 0)
#endif

#ifdef LOOKUP_HACK
   typedef int8 sample_t;
   typedef uint8 final_volume_t;
#  define FINAL_VOLUME(v) ((final_volume_t)~_l2u[v])
#  define MIXUP_SHIFT 5
#  define MAX_AMP_VALUE 4095
#else
   typedef int16 sample_t;
   typedef int32 final_volume_t;
#  define FINAL_VOLUME(v) (v)
#  define MAX_AMP_VALUE ((1<<(AMP_BITS+1))-1)
#endif
#define MIN_AMP_VALUE (MAX_AMP_VALUE >> 9)

#ifdef USE_LDEXP
#  define TIM_FSCALE(a,b) ldexp((double)(a),(b))
#  define TIM_FSCALENEG(a,b) ldexp((double)(a),-(b))
#  include <math.h>
#else
#  define TIM_FSCALE(a,b) ((a) * (double)(1<<(b)))
#  define TIM_FSCALENEG(a,b) ((a) * (1.0L / (double)(1<<(b))))
#endif

#ifdef HPUX
#undef mono
#endif

#ifdef sun
#ifndef SOLARIS
/* SunOS 4.x */
#include <sys/stdtypes.h>
#include <memory.h>
#define memcpy(x, y, n) bcopy(y, x, n)
#else
/* Solaris */
int usleep(unsigned int useconds); /* shut gcc warning up */
#endif
#endif /* sun */


#ifdef __W32__
#undef PATCH_EXT_LIST
#define PATCH_EXT_LIST { ".pat", 0 }

#define URL_DIR_CACHE_DISABLE
#endif

/* The path separator (D.M.) */
/* Windows: "\"
 * Cygwin:  both "\" and "/"
 * Macintosh: ":"
 * Unix: "/"
 */
#if defined(__W32__)
#  define PATH_SEP '\\'
#  define PATH_STRING "\\"
#if defined(__CYGWIN32__) || defined(__MINGW32__)
#  define PATH_SEP2 '/'
#endif
#elif defined(__MACOS__)
#  define PATH_SEP ':'
#  define PATH_STRING ":"
#else
#  define PATH_SEP '/'
#  define PATH_STRING "/"
#endif

#ifdef PATH_SEP2
#define IS_PATH_SEP(c) ((c) == PATH_SEP || (c) == PATH_SEP2)
#else
#define IS_PATH_SEP(c) ((c) == PATH_SEP)
#endif

/* new line code */
#ifndef NLS
#ifdef __W32__
#if defined(__BORLANDC__) || defined(__CYGWIN32__) || defined(__MINGW32__)
#  define NLS "\n"
#else
#  define NLS "\r\n"
#endif
#else /* !__W32__ */
#  define NLS "\n"
#endif
#endif /* NLS */

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif /* M_PI */

#ifndef __W32__
#undef MAIL_NAME
#endif /* __W32__ */

#ifdef __BORLANDC__
/* strncasecmp() -> strncmpi(char *,char *,size_t) */
#define strncasecmp(a,b,c) strncmpi(a,b,c)
#define strcasecmp(a,b) strcmpi(a,b)
#endif /* __BORLANDC__ */

#ifdef _MSC_VER
#define strncasecmp(a,b,c)	_strnicmp((a),(b),(c))
#define strcasecmp(a,b)		_stricmp((a),(b))
#define open _open
#define close _close
#define write _write
#define lseek _lseek
#define unlink _unlink
#endif /* _MSC_VER */

#define SAFE_CONVERT_LENGTH(len) (6 * (len) + 1)

#ifdef __MACOS__
#include "mac_com.h"
#endif

#ifndef HAVE_POPEN
# undef DECOMPRESSOR_LIST
# undef PATCH_CONVERTERS
#endif

#endif /* SYSDEP_H_INCUDED */
