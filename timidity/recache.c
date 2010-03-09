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

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif /* HAVE_CONFIG_H */
#include <stdio.h>
#ifndef __W32__
#include <unistd.h>
#endif
#include <stdlib.h>

#ifndef NO_STRING_H
#include <string.h>
#else
#include <strings.h>
#endif

#include "timidity.h"
#include "common.h"
#include "instrum.h"
#include "playmidi.h"
#include "output.h"
#include "controls.h"
#include "tables.h"
#include "mblock.h"
#include "recache.h"

#define HASH_TABLE_SIZE 251
#define MIXLEN 256

#define MIN_LOOPSTART MIXLEN
#define MIN_LOOPLEN   1024
#define MAX_EXPANDLEN (1024*32)
#define CACHE_DATA_LEN (allocate_cache_size/sizeof(sample_t))

static sample_t *cache_data = NULL;
int32 allocate_cache_size = DEFAULT_CACHE_DATA_SIZE;
static int32  cache_data_len;
static struct cache_hash *cache_hash_table[HASH_TABLE_SIZE];
static MBlockList hash_entry_pool;

#define CACHE_RESAMPLING_OK	0
#define CACHE_RESAMPLING_NOTOK	1
#define INT32MAX 2147483647L /* (1LU<<31)-1 */

#if defined(CSPLINE_INTERPOLATION)
# define INTERPVARS_CACHE      int32   ofsd, v0, v1, v2, v3, temp;
# define RESAMPLATION_CACHE \
        v1 = (int32)src[(ofs>>FRACTION_BITS)]; \
        v2 = (int32)src[(ofs>>FRACTION_BITS)+1]; \
 	if((ofs<ls+(1L<<FRACTION_BITS))||((ofs+(2L<<FRACTION_BITS))>le)){ \
                dest[i] = (sample_t)(v1 + (((v2-v1) * (ofs & FRACTION_MASK)) >> FRACTION_BITS)); \
 	}else{ \
		ofsd=ofs; \
                v0 = (int32)src[(ofs>>FRACTION_BITS)-1]; \
                v3 = (int32)src[(ofs>>FRACTION_BITS)+2]; \
                ofs &= FRACTION_MASK; \
	        temp=v2; \
 		v2 = (6*v2+((((5*v3 - 11*v2 + 7*v1 - v0)>>2)* \
 		     (ofs+(1L<<FRACTION_BITS))>>FRACTION_BITS)* \
 		     (ofs-(1L<<FRACTION_BITS))>>FRACTION_BITS)) \
 		     *ofs; \
 		v1 = (((6*v1+((((5*v0 - 11*v1 + 7*temp - v3)>>2)* \
 		     ofs>>FRACTION_BITS)*(ofs-(2L<<FRACTION_BITS)) \
 		     >>FRACTION_BITS))*((1L<<FRACTION_BITS)-ofs))+v2) \
 		     /(6L<<FRACTION_BITS); \
 		dest[i] = (v1 > 32767)? 32767: ((v1 < -32768)? -32768: v1); \
		ofs = ofsd; \
 	}
#elif defined(LAGRANGE_INTERPOLATION)
# define INTERPVARS_CACHE      int32   ofsd, v0, v1, v2, v3;
# define RESAMPLATION_CACHE \
        v1 = (int32)src[(ofs>>FRACTION_BITS)]; \
        v2 = (int32)src[(ofs>>FRACTION_BITS)+1]; \
	if((ofs<ls+(1L<<FRACTION_BITS))||((ofs+(2L<<FRACTION_BITS))>le)){ \
                dest[i] = (sample_t)(v1 + (((v2-v1) * (ofs & FRACTION_MASK)) >> FRACTION_BITS)); \
	}else{ \
                v0 = (int32)src[(ofs>>FRACTION_BITS)-1]; \
                v3 = (int32)src[(ofs>>FRACTION_BITS)+2]; \
                ofsd = (ofs & FRACTION_MASK) + (1L << FRACTION_BITS); \
                v1 = v1*ofsd>>FRACTION_BITS; \
                v2 = v2*ofsd>>FRACTION_BITS; \
                v3 = v3*ofsd>>FRACTION_BITS; \
                ofsd -= (1L << FRACTION_BITS); \
                v0 = v0*ofsd>>FRACTION_BITS; \
                v2 = v2*ofsd>>FRACTION_BITS; \
                v3 = v3*ofsd>>FRACTION_BITS; \
                ofsd -= (1L << FRACTION_BITS); \
                v0 = v0*ofsd>>FRACTION_BITS; \
                v1 = v1*ofsd>>FRACTION_BITS; \
                v3 = v3*ofsd; \
                ofsd -= (1L << FRACTION_BITS); \
                v0 = (v3 - v0*ofsd)/(6L << FRACTION_BITS); \
                v1 = (v1 - v2)*ofsd>>(FRACTION_BITS+1); \
		v1 += v0; \
		dest[i] = (v1 > 32767)? 32767: ((v1 < -32768)? -32768: v1); \
	}
#elif defined(LINEAR_INTERPOLATION)
#   define RESAMPLATION_CACHE \
      v1=src[ofs>>FRACTION_BITS];\
      v2=src[(ofs>>FRACTION_BITS)+1];\
      dest[i] = (sample_t)(v1 + (((v2-v1) * (ofs & FRACTION_MASK)) >> FRACTION_BITS));
#  define INTERPVARS_CACHE int32 v1, v2;
#else
/* Earplugs recommended for maximum listening enjoyment */
#  define RESAMPLATION_CACHE dest[i]=src[ofs>>FRACTION_BITS];
#  define INTERPVARS_CACHE
#endif

static struct
{
    int32 on[128];
    struct cache_hash *cache[128];
} channel_note_table[MAX_CHANNELS];

void resamp_cache_reset(void)
{
    if(cache_data == NULL)
    {
	cache_data =
	    (sample_t *)safe_large_malloc(CACHE_DATA_LEN * sizeof(sample_t));
	init_mblock(&hash_entry_pool);
    }
    cache_data_len = 0;
    memset(cache_hash_table, 0, sizeof(cache_hash_table));
    memset(channel_note_table, 0, sizeof(channel_note_table));
    reuse_mblock(&hash_entry_pool);
}

#define sp_hash(sp, note) ((unsigned int)(sp) + (unsigned int)(note))

struct cache_hash *resamp_cache_fetch(Sample *sp, int note)
{
    unsigned int addr;
    struct cache_hash *p;

    if(sp->vibrato_control_ratio ||
       (sp->modes & MODES_PINGPONG) ||
       (sp->sample_rate == play_mode->rate &&
        sp->root_freq == freq_table[sp->note_to_use]))
	    return NULL;

    addr = sp_hash(sp, note) % HASH_TABLE_SIZE;
    p = cache_hash_table[addr];
    while(p && (p->note != note || p->sp != sp))
	p = p->next;
    if(p && p->resampled != NULL)
	return p;
    return NULL;
}

void resamp_cache_refer_on(Voice *vp, int32 sample_start)
{
    unsigned int addr;
    struct cache_hash *p;
    int note, ch;

    ch = vp->channel;

    if(vp->vibrato_control_ratio ||
       channel[ch].portamento ||
       (vp->sample->modes & MODES_PINGPONG) ||
       vp->orig_frequency != vp->frequency ||
       (vp->sample->sample_rate == play_mode->rate &&
        vp->sample->root_freq == freq_table[vp->sample->note_to_use]))
	    return;

    note = vp->note;

    if(channel_note_table[ch].cache[note])
	resamp_cache_refer_off(ch, note, sample_start);

    addr = sp_hash(vp->sample, note) % HASH_TABLE_SIZE;
    p = cache_hash_table[addr];
    while(p && (p->note != note || p->sp != vp->sample))
	p = p->next;

    if(!p)
    {
	p = (struct cache_hash *)
	    new_segment(&hash_entry_pool, sizeof(struct cache_hash));
	p->cnt = 0;
	p->note = vp->note;
	p->sp = vp->sample;
	p->resampled = NULL;
	p->next = cache_hash_table[addr];
	cache_hash_table[addr] = p;
    }
    channel_note_table[ch].cache[note] = p;
    channel_note_table[ch].on[note] = sample_start;
}

void resamp_cache_refer_off(int ch, int note, int32 sample_end)
{
    int32 sample_start, len;
    struct cache_hash *p;
    Sample *sp;

    p = channel_note_table[ch].cache[note];
    if(p == NULL)
	return;

    sp = p->sp;
    if(sp->sample_rate == play_mode->rate &&
       sp->root_freq == freq_table[sp->note_to_use])
	return;
    sample_start = channel_note_table[ch].on[note];

    len = sample_end - sample_start;
    if(len < 0)
    {
	channel_note_table[ch].cache[note] = NULL;
	return;
    }

    if(!(sp->modes & MODES_LOOPING))
    {
	double a;
	int32 slen;

	a = ((double)sp->root_freq * play_mode->rate) /
	    ((double)sp->sample_rate * freq_table[note]);
	slen = (int32)((sp->data_length >> FRACTION_BITS) * a);
	if(len > slen)
	    len = slen;
    }
    p->cnt += len;
    channel_note_table[ch].cache[note] = NULL;
}

void resamp_cache_refer_alloff(int ch, int32 sample_end)
{
    int i;
    for(i = 0; i < 128; i++)
	resamp_cache_refer_off(ch, i, sample_end);
}


static void loop_connect(sample_t *data, int32 start, int32 end)
{
    int i, mixlen;
    int32 t0, t1;

    mixlen = MIXLEN;
    if(start < mixlen)
	mixlen = start;
    if(end - start < mixlen)
	mixlen = end - start;
    if(mixlen <= 0)
	return;

    t0 = start - mixlen;
    t1 = end   - mixlen;

    for(i = 0; i < mixlen; i++)
    {
	double x, b;

	b = i / (double)mixlen;	/* 0 <= b < 1 */
	x = b * data[t0 + i] + (1.0 - b) * data[t1 + i];
#ifdef LOOKUP_HACK
	if(x < -128)
	    data[t1 + i] = -128;
	else if(x > 127)
	    data[t1 + i] = 127;
#else
	if(x < -32768)
	    data[t1 + i] = -32768;
	else if(x > 32767)
	    data[t1 + i] = 32767;
#endif /* LOOKUP_HACK */
	else
	    data[t1 + i] = (sample_t)x;
    }
}

static double sample_resamp_info(Sample *sp, int note,
				 uint32 *loop_start, uint32 *loop_end,
				 uint32 *data_length)
{
    uint32 xls, xle, ls, le, ll, newlen;
    double a, xxls, xxle, xn;

    a = ((double)sp->sample_rate * freq_table[note]) /
	((double)sp->root_freq * play_mode->rate);
    a = TIM_FSCALENEG((double)(int32)TIM_FSCALE(a, FRACTION_BITS),
		      FRACTION_BITS);

    xn = sp->data_length / a;
    if(xn >= INT32MAX)
    {
	/* Ignore this sample */
	*data_length = 0;
	return 0.0;
    }
    newlen = (int32)(TIM_FSCALENEG(xn, FRACTION_BITS) + 0.5);

    ls = sp->loop_start;
    le = sp->loop_end;
    ll = (le - ls);

    xxls = ls / a + 0.5;
    if(xxls >= INT32MAX)
    {
	/* Ignore this sample */
	*data_length = 0;
	return 0.0;
    }
    xls = (int32)xxls;

    xxle = le / a + 0.5;
    if(xxle >= INT32MAX)
    {
	/* Ignore this sample */
	*data_length = 0;
	return 0.0;
    }
    xle = (int32)xxle;

    if((sp->modes & MODES_LOOPING) &&
       ((xle - xls) >> FRACTION_BITS) < MIN_LOOPLEN)
    {
	int32 n;
	int32 newxle;
	double xl; /* Resampled new loop length */
	double xnewxle;

	xl = ll / a;
	if(xl >= INT32MAX)
	{
	    /* Ignore this sample */
	    *data_length = 0;
	    return 0.0;
	}

	n = (int32)(0.0001 + MIN_LOOPLEN /
		    TIM_FSCALENEG(xl, FRACTION_BITS)) + 1;
	xnewxle = le / a + n * xl + 0.5;
	if(xnewxle >= INT32MAX)
	{
	    /* Ignore this sample */
	    *data_length = 0;
	    return 0.0;
	}

	newxle = (int32)xnewxle;
	newlen += (newxle - xle)>>FRACTION_BITS;
	xle = newxle;
    }

    if(loop_start)
	*loop_start = (uint32)(xls & ~FRACTION_MASK);
    if(loop_end)
	*loop_end = (uint32)(xle & ~FRACTION_MASK);
    *data_length = newlen << FRACTION_BITS;
    return a;
}

static int cache_resampling(struct cache_hash *p)
{
    Sample *sp, *newsp;
    sample_t *src, *dest;
    uint32 newlen;
    int32 i, ofs, incr;
	uint32 le, ls, ll, xls, xle;
    double a;

    sp = p->sp;
    a = sample_resamp_info(sp, p->note, &xls, &xle, &newlen);
    if(newlen == 0)
	return CACHE_RESAMPLING_NOTOK;

    newlen >>= FRACTION_BITS;

    if(cache_data_len + newlen + 1 > CACHE_DATA_LEN)
	return CACHE_RESAMPLING_NOTOK;

    ls = sp->loop_start;
    le = sp->loop_end;

    ll = (le - ls);
    dest = cache_data + cache_data_len;
    src = sp->data;

    newsp = (Sample *)new_segment(&hash_entry_pool, sizeof(Sample));
    memcpy(newsp, sp, sizeof(Sample));
    newsp->data = dest;

    ofs = 0;
    incr = (int32)(TIM_FSCALE(a, FRACTION_BITS) + 0.5);
    if(sp->modes & MODES_LOOPING)
    {
	for(i = 0; i < newlen; i++)
	{
	    int32 j;
	    INTERPVARS_CACHE

	    if(ofs >= le)
		ofs -= ll;
	    j = ofs>>FRACTION_BITS;
	    v1 = src[j];
	    v2 = src[j + 1];
	    RESAMPLATION_CACHE
	    ofs += incr;
	}
    }
    else
    {
	for(i = 0; i < newlen; i++)
	{
	    int32 j;
	    INTERPVARS_CACHE
	    
	    j = ofs>>FRACTION_BITS;
	    v1 = src[j];
	    v2 = src[j + 1];
	    RESAMPLATION_CACHE
	    ofs += incr;
	}
    }
    newsp->loop_start = xls;
    newsp->loop_end = xle;
    newsp->data_length = (newlen << FRACTION_BITS);
    if(sp->modes & MODES_LOOPING)
	loop_connect(dest, xls>>FRACTION_BITS, xle>>FRACTION_BITS);
    dest[xle>>FRACTION_BITS] = dest[xls>>FRACTION_BITS];

/* sample_rate * freq_table[p->note]) == root_freq * play_mode->rate */
    newsp->root_freq = freq_table[p->note];
    newsp->sample_rate = play_mode->rate;

    p->resampled = newsp;
    cache_data_len += newlen + 1;

    return CACHE_RESAMPLING_OK;
}

#define SORT_THRESHOLD 20
static void insort_cache_array(struct cache_hash **data, long n)
{
    long i, j;
    struct cache_hash *x;

    for(i = 1; i < n; i++)
    {
	x = data[i];
	for(j = i - 1; j >= 0 && x->r < data[j]->r; j--)
	    data[j + 1] = data[j];
	data[j + 1] = x;
    }
}

static void qsort_cache_array(struct cache_hash **a, long first, long last)
{
    long i = first, j = last;
    struct cache_hash *x, *t;

    if(j - i < SORT_THRESHOLD)
    {
	insort_cache_array(a + i, j - i + 1);
	return;
    }

    x = a[(first + last) / 2];

    for(;;)
    {
	while(a[i]->r < x->r)
	    i++;
	while(x->r < a[j]->r)
	    j--;
	if(i >= j)
	    break;
	t = a[i];
	a[i] = a[j];
	a[j] = t;
	i++;
	j--;
    }
    if(first < i - 1)
	qsort_cache_array(a, first, i - 1);
    if(j + 1 < last)
	qsort_cache_array(a, j + 1, last);
}

void resamp_cache_create(void)
{
    int i, skip;
    int32 n, t1, t2, total;
    struct cache_hash **array;

    /* It is NP completion that solve the best cache hit rate.
     * So I thought better algorism O(n log n), but not a best solution.
     * Follows implementation takes good hit rate, and it is fast.
     */

    n = t1 = t2 = 0;
    total = 0;

    /* set size per count */
    for(i = 0; i < HASH_TABLE_SIZE; i++)
    {
	struct cache_hash *p, *q;

	q = NULL;
	p = cache_hash_table[i];
	while(p)
	{
	    struct cache_hash *tmp;

	    t1 += p->cnt;

	    tmp = p;
	    p = p->next;
	    if(tmp->cnt > 0)
	    {
		Sample *sp;
		uint32 newlen;

		sp = tmp->sp;
		sample_resamp_info(sp, tmp->note, NULL, NULL, &newlen);
		if(newlen > 0)
		{
		    total += tmp->cnt;
		    tmp->r = (double)newlen / tmp->cnt;
		    tmp->next = q;
		    q = tmp;
		    n++;
		}
	    }
	}
	cache_hash_table[i] = q;
    }

    if(n == 0)
    {
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "No pre-resampling cache hit");
	return;
    }

    array = (struct cache_hash **)new_segment(&hash_entry_pool,
					      n * sizeof(struct cache_hash *));
    n = 0;
    for(i = 0; i < HASH_TABLE_SIZE; i++)
    {
	struct cache_hash *p;
	for(p = cache_hash_table[i]; p; p = p->next)
	    array[n++] = p;
    }

    if(total > CACHE_DATA_LEN)
	qsort_cache_array(array, 0, n - 1);

    skip = 0;
    for(i = 0; i < n; i++)
    {
	if(array[i]->r != 0 &&
	   cache_resampling(array[i]) == CACHE_RESAMPLING_OK)
	    t2 += array[i]->cnt;
	else
	    skip++;
    }

    ctl->cmsg(CMSG_INFO, VERB_NOISY,
	      "Resample cache: Key %d/%d(%.1f%%) "
	      "Sample %.1f%c/%.1f%c(%.1f%%)",
	      n - skip, n, 100.0 * (n - skip) / n,
	      t2 / (t2 >= 1048576 ? 1048576.0 : 1024.0),
	      t2 >= 1048576 ? 'M' : 'K',
	      t1 / (t1 >= 1048576 ? 1048576.0 : 1024.0),
	      t1 >= 1048576 ? 'M' : 'K',
	      100.0 * t2 / t1);

    /* update cache_hash_table */
    if(skip)
    {
	for(i = 0; i < HASH_TABLE_SIZE; i++)
	{
	    struct cache_hash *p, *q;

	    q = NULL;
	    p = cache_hash_table[i];

	    while(p)
	    {
		struct cache_hash *tmp;
		tmp = p;
		p = p->next;

		if(tmp->resampled)
		{
		    tmp->next = q;
		    q = tmp;
		}
	    }
	    cache_hash_table[i] = q;
	}
    }
}
