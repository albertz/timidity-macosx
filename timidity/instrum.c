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

   instrum.c

   Code to load and unload GUS-compatible instrument patches.

*/

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif /* HAVE_CONFIG_H */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#ifndef NO_STRING_H
#include <string.h>
#else
#include <strings.h>
#endif

#include "timidity.h"
#include "common.h"
#include "instrum.h"
#include "playmidi.h"
#include "readmidi.h"
#include "output.h"
#include "controls.h"
#include "resample.h"
#include "tables.h"
#include "filter.h"
#include "quantity.h"

#define INSTRUMENT_HASH_SIZE 128
struct InstrumentCache
{
    char *name;
    int panning, amp, note_to_use, strip_loop, strip_envelope, strip_tail;
    Instrument *ip;
    struct InstrumentCache *next;
};
static struct InstrumentCache *instrument_cache[INSTRUMENT_HASH_SIZE];

/* Some functions get aggravated if not even the standard banks are
   available. */
static ToneBank standard_tonebank, standard_drumset;
ToneBank
  *tonebank[128]={&standard_tonebank},
  *drumset[128]={&standard_drumset};

/* This is a special instrument, used for all melodic programs */
Instrument *default_instrument=0;
SpecialPatch *special_patch[NSPECIAL_PATCH];
int progbase = 0;
struct inst_map_elem
{
    int set, elem, mapped;
};

static struct inst_map_elem *inst_map_table[NUM_INST_MAP][128];

/* This is only used for tracks that don't specify a program */
int default_program[MAX_CHANNELS];

char *default_instrument_name = NULL;

int antialiasing_allowed=0;
#ifdef FAST_DECAY
int fast_decay=1;
#else
int fast_decay=0;
#endif

/*Pseudo Reverb*/
int32 modify_release;

/** below three functinos are imported from sndfont.c **/

/* convert from 8bit value to fractional offset (15.15) */
static int32 to_offset(int offset)
{
	return (int32)offset << (7+15);
}

/* calculate ramp rate in fractional unit;
 * diff = 8bit, time = msec
 */
static int32 calc_rate(int diff, double msec)
{
    double rate;

    if(msec < 6)
	msec = 6;
    if(diff == 0)
	diff = 255;
    diff <<= (7+15);
    rate = ((double)diff / play_mode->rate) * control_ratio * 1000.0 / msec;
    if(fast_decay)
	rate *= 2;
    return (int32)rate;
}
/*End of Pseudo Reverb*/

void free_instrument(Instrument *ip)
{
  Sample *sp;
  int i;
  if (!ip) return;

  for (i=0; i<ip->samples; i++)
    {
      sp=&(ip->sample[i]);
      if(sp->data_alloced)
	  free(sp->data);
    }
  free(ip->sample);
  free(ip);
}

void clear_magic_instruments(void)
{
    int i, j;

    for(j = 0; j < 128; j++)
    {
	if(tonebank[j])
	{
	    ToneBank *bank = tonebank[j];
	    for(i = 0; i < 128; i++)
		if(IS_MAGIC_INSTRUMENT(bank->tone[i].instrument))
		    bank->tone[i].instrument = NULL;
	}
	if(drumset[j])
	{
	    ToneBank *bank = drumset[j];
	    for(i = 0; i < 128; i++)
		if(IS_MAGIC_INSTRUMENT(bank->tone[i].instrument))
		    bank->tone[i].instrument = NULL;
	}
    }
}

static int32 convert_envelope_rate(uint8 rate)
{
  int32 r;

  r=3-((rate>>6) & 0x3);
  r*=3;
  r = (int32)(rate & 0x3f) << r; /* 6.9 fixed point */

  /* 15.15 fixed point. */
  return (((r * 44100) / play_mode->rate) * control_ratio)
    << ((fast_decay) ? 10 : 9);
}

static int32 convert_envelope_offset(uint8 offset)
{
  /* This is not too good... Can anyone tell me what these values mean?
     Are they GUS-style "exponential" volumes? And what does that mean? */

  /* 15.15 fixed point */
  return offset << (7+15);
}

static int32 convert_tremolo_sweep(uint8 sweep)
{
  if (!sweep)
    return 0;

  return
    ((control_ratio * SWEEP_TUNING) << SWEEP_SHIFT) /
      (play_mode->rate * sweep);
}

static int32 convert_vibrato_sweep(uint8 sweep, int32 vib_control_ratio)
{
  if (!sweep)
    return 0;

  return (int32)(TIM_FSCALE((double) (vib_control_ratio)
			    * SWEEP_TUNING, SWEEP_SHIFT)
		 / (double)(play_mode->rate * sweep));

  /* this was overflowing with seashore.pat

      ((vib_control_ratio * SWEEP_TUNING) << SWEEP_SHIFT) /
      (play_mode->rate * sweep); */
}

static int32 convert_tremolo_rate(uint8 rate)
{
  return
    ((SINE_CYCLE_LENGTH * control_ratio * rate) << RATE_SHIFT) /
      (TREMOLO_RATE_TUNING * play_mode->rate);
}

static int32 convert_vibrato_rate(uint8 rate)
{
  /* Return a suitable vibrato_control_ratio value */
  return
    (VIBRATO_RATE_TUNING * play_mode->rate) /
      (rate * 2 * VIBRATO_SAMPLE_INCREMENTS);
}

static void reverse_data(int16 *sp, int32 ls, int32 le)
{
  int16 s, *ep=sp+le;
  int32 i;
  sp+=ls;
  le-=ls;
  le/=2;
  for(i = 0; i < le; i++)
  {
      s=*sp;
      *sp++=*ep;
      *ep--=s;
  }
}

static int name_hash(char *name)
{
    unsigned int addr = 0;

    while(*name)
	addr += *name++;
    return addr % INSTRUMENT_HASH_SIZE;
}

static Instrument *search_instrument_cache(char *name,
				int panning, int amp, int note_to_use,
				int strip_loop, int strip_envelope,
				int strip_tail)
{
    struct InstrumentCache *p;

    for(p = instrument_cache[name_hash(name)]; p != NULL; p = p->next)
    {
	if(strcmp(p->name, name) != 0)
	    return NULL;
	if(p->panning == panning &&
	   p->amp == amp &&
	   p->note_to_use == note_to_use &&
	   p->strip_loop == strip_loop &&
	   p->strip_envelope == strip_envelope &&
	   p->strip_tail == strip_tail)
	    return p->ip;
    }
    return NULL;
}

static void store_instrument_cache(Instrument *ip,
				   char *name,
				   int panning, int amp, int note_to_use,
				   int strip_loop, int strip_envelope,
				   int strip_tail)
{
    struct InstrumentCache *p;
    int addr;

    addr = name_hash(name);
    p = (struct InstrumentCache *)safe_malloc(sizeof(struct InstrumentCache));
    p->next = instrument_cache[addr];
    instrument_cache[addr] = p;
    p->name = name;
    p->panning = panning;
    p->amp = amp;
    p->note_to_use = note_to_use;
    p->strip_loop = strip_loop;
    p->strip_envelope = strip_envelope;
    p->strip_tail = strip_tail;
    p->ip = ip;
}

static int
adjust_tune_freq(int val, float tune)
{
  if (!tune)
    return val;
  return (int)(val / pow(2.0, tune / 12.0));
}

static int32 to_rate(int rate)
{
	return (rate) ? (int32) (0x200 * pow(2.0, rate / 17.0)
			* 44100 / play_mode->rate * control_ratio) << fast_decay : 0;
}

static int32 to_control(int control)
{
	return (int32) (0x2000 / pow(2.0, control / 31.0));
}

static void apply_bank_parameter(Instrument *ip, ToneBankElement *tone)
{
	int i, j;
	Sample *sp;
	
	if (tone->tunenum)
		for (i = 0; i < ip->samples; i++) {
			sp = &ip->sample[i];
			if (tone->tunenum == 1) {
				sp->low_freq = adjust_tune_freq(sp->low_freq, tone->tune[0]);
				sp->high_freq = adjust_tune_freq(sp->high_freq, tone->tune[0]);
				sp->root_freq = adjust_tune_freq(sp->root_freq, tone->tune[0]);
			} else if (i < tone->tunenum) {
				sp->low_freq = adjust_tune_freq(sp->low_freq, tone->tune[i]);
				sp->high_freq = adjust_tune_freq(sp->high_freq, tone->tune[i]);
				sp->root_freq = adjust_tune_freq(sp->root_freq, tone->tune[i]);
			}
		}
	if (tone->envratenum)
		for (i =0; i < ip->samples; i++) {
			sp = &ip->sample[i];
			if (tone->envratenum == 1) {
				for (j =0; j < 6; j++)
					if (tone->envrate[0][j] >= 0)
						sp->envelope_rate[j] = to_rate(tone->envrate[0][j]);
			} else if (i < tone->envratenum) {
				for (j =0; j < 6; j++)
					if (tone->envrate[i][j] >= 0)
						sp->envelope_rate[j] = to_rate(tone->envrate[i][j]);
			}
		}
	if (tone->envofsnum)
		for (i =0; i < ip->samples; i++) {
			sp = &ip->sample[i];
			if (tone->envofsnum == 1) {
				for (j =0; j < 6; j++)
					if (tone->envofs[0][j] >= 0)
						sp->envelope_offset[j] = to_offset(tone->envofs[0][j]);
			} else if (i < tone->envofsnum) {
				for (j =0; j < 6; j++)
					if (tone->envofs[i][j] >= 0)
						sp->envelope_offset[j] = to_offset(tone->envofs[i][j]);
			}
		}
	if (tone->tremnum)
		for (i =0; i < ip->samples; i++) {
			sp = &ip->sample[i];
			if (tone->tremnum == 1) {
				if (IS_QUANTITY_DEFINED(tone->trem[0][0]))
					sp->tremolo_sweep_increment =
							quantity_to_int(&tone->trem[0][0], 0);
				if (IS_QUANTITY_DEFINED(tone->trem[0][1]))
					sp->tremolo_phase_increment = quantity_to_int(&tone->trem[0][1], 0);
				if (IS_QUANTITY_DEFINED(tone->trem[0][2]))
					sp->tremolo_depth = quantity_to_int(&tone->trem[0][2], 0) << 1;
			} else if (i < tone->tremnum) {
				if (IS_QUANTITY_DEFINED(tone->trem[i][0]))
					sp->tremolo_sweep_increment =
							quantity_to_int(&tone->trem[i][0], 0);
				if (IS_QUANTITY_DEFINED(tone->trem[i][1]))
					sp->tremolo_phase_increment = quantity_to_int(&tone->trem[i][1], 0);
				if (IS_QUANTITY_DEFINED(tone->trem[i][2]))
					sp->tremolo_depth = quantity_to_int(&tone->trem[i][2], 0) << 1;
			}
		}
	if (tone->vibnum)
		for (i =0; i < ip->samples; i++) {
			sp = &ip->sample[i];
			if (tone->vibnum == 1) {
				if (IS_QUANTITY_DEFINED(tone->vib[0][1]))
					sp->vibrato_control_ratio = quantity_to_int(&tone->vib[0][1], 0);
				if (IS_QUANTITY_DEFINED(tone->vib[0][0]))
					sp->vibrato_sweep_increment =
							quantity_to_int(&tone->vib[0][0],
							sp->vibrato_control_ratio);
				if (IS_QUANTITY_DEFINED(tone->vib[0][2]))
					sp->vibrato_depth = quantity_to_int(&tone->vib[0][2], 0);
			} else if (i < tone->vibnum) {
				if (IS_QUANTITY_DEFINED(tone->vib[i][1]))
					sp->vibrato_control_ratio = quantity_to_int(&tone->vib[i][1], 0);
				if (IS_QUANTITY_DEFINED(tone->vib[i][0]))
					sp->vibrato_sweep_increment =
							quantity_to_int(&tone->vib[i][0],
							sp->vibrato_control_ratio);
				if (IS_QUANTITY_DEFINED(tone->vib[i][2]))
					sp->vibrato_depth = quantity_to_int(&tone->vib[i][2], 0);
			}
		}
}

/*
   If panning or note_to_use != -1, it will be used for all samples,
   instead of the sample-specific values in the instrument file.

   For note_to_use, any value <0 or >127 will be forced to 0.

   For other parameters, 1 means yes, 0 means no, other values are
   undefined.

   TODO: do reverse loops right */
static Instrument *load_gus_instrument(char *name,
				       ToneBank *bank,
				       int dr, int prog,
				       char *infomsg)
{
  Instrument *ip;
  Sample *sp;
  struct timidity_file *tf;
  uint8 tmp[1024];
  int i,j,noluck=0;
  int panning, amp, note_to_use, strip_loop, strip_envelope, strip_tail;
  ToneBankElement *tone;

#ifdef PATCH_EXT_LIST
  static char *patch_ext[] = PATCH_EXT_LIST;
#endif

  if (!name) return 0;

  if(infomsg != NULL)
      ctl->cmsg(CMSG_INFO, VERB_NOISY, "%s: %s", infomsg, name);
  else
      ctl->cmsg(CMSG_INFO, VERB_NOISY, "Loading instrument %s", name);

  if(bank)
  {
      tone = &bank->tone[prog];
      panning = tone->pan;
      amp = tone->amp;
      note_to_use = (tone->note != -1) ? tone->note : (dr ? prog : -1);
      strip_loop = (tone->strip_loop!=-1) ? tone->strip_loop : (dr ? 1 : -1);
      strip_envelope = (tone->strip_envelope != -1) ? tone->strip_envelope : (dr ? 1 : -1);
      strip_tail = tone->strip_tail;
  }
  else
  {
      panning = amp = note_to_use = -1;
      strip_loop = strip_envelope = strip_tail = 0;
      tone = NULL;
  }

	if (tone && tone->tunenum == 0
			&& tone->envratenum == 0 && tone->envofsnum == 0
			&& tone->tremnum == 0 && tone->vibnum == 0) {
    if((ip = search_instrument_cache(name, panning, amp, note_to_use,
				     strip_loop, strip_envelope, strip_tail))
       != NULL)
      {
	ctl->cmsg(CMSG_INFO, VERB_DEBUG, " * Cached");
	return ip;
      }
  }

  /* Open patch file */
  if (!(tf=open_file(name, 2, OF_NORMAL)))
    {
      int name_len, ext_len;
      noluck=1;
#ifdef PATCH_EXT_LIST
      name_len = strlen(name);
      /* Try with various extensions */
      for (i=0; patch_ext[i]; i++)
	{
	  ext_len = strlen(patch_ext[i]);
	  if (name_len + ext_len < 1024)
	    {
	      if(name_len >= ext_len &&
		 strcmp(name + name_len - ext_len, patch_ext[i]) == 0)
		  continue; /* duplicated ext. */
	      strcpy((char *)tmp, name);
	      strcat((char *)tmp, patch_ext[i]);
	      if ((tf=open_file((char *)tmp, 1, OF_NORMAL)))
		{
		  noluck=0;
		  break;
		}
	    }
	}
#endif
    }

  if (noluck)
    {
      ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
		"Instrument `%s' can't be found.", name);
      return 0;
    }

  /* Read some headers and do cursory sanity checks. There are loads
     of magic offsets. This could be rewritten... */

  tmp[0] = tf_getc(tf);
  if(tmp[0] == '\0') {
      /* for Mac binary */
      skip(tf, 127);
      tmp[0] = tf_getc(tf);
  }

  if ((238 != tf_read(tmp + 1, 1, 238, tf)) ||
      (memcmp(tmp, "GF1PATCH110\0ID#000002", 22) &&
       memcmp(tmp, "GF1PATCH100\0ID#000002", 22))) /* don't know what the
						      differences are */
    {
      ctl->cmsg(CMSG_ERROR, VERB_NORMAL, "%s: not an instrument", name);
      close_file(tf);
      return 0;
    }

  if (tmp[82] != 1 && tmp[82] != 0) /* instruments. To some patch makers,
				       0 means 1 */
    {
      ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	   "Can't handle patches with %d instruments", tmp[82]);
      close_file(tf);
      return 0;
    }

  if (tmp[151] != 1 && tmp[151] != 0) /* layers. What's a layer? */
    {
      ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	   "Can't handle instruments with %d layers", tmp[151]);
      close_file(tf);
      return 0;
    }

  ip = (Instrument *)safe_malloc(sizeof(Instrument));
  ip->type = INST_GUS;
  ip->samples = tmp[198];
  ip->sample = (Sample *)safe_malloc(sizeof(Sample) * ip->samples);
  memset(ip->sample, 0, sizeof(Sample) * ip->samples);
  for (i=0; i<ip->samples; i++)
    {
      uint8 fractions;
      int32 tmplong;
      uint16 tmpshort;
      uint8 tmpchar;

#define READ_CHAR(thing) \
      if (1 != tf_read(&tmpchar, 1, 1, tf)) goto fail; \
      thing = tmpchar;
#define READ_SHORT(thing) \
      if (1 != tf_read(&tmpshort, 2, 1, tf)) goto fail; \
      thing = LE_SHORT(tmpshort);
#define READ_LONG(thing) \
      if (1 != tf_read(&tmplong, 4, 1, tf)) goto fail; \
      thing = LE_LONG(tmplong);

      skip(tf, 7); /* Skip the wave name */

      if (1 != tf_read(&fractions, 1, 1, tf))
	{
	fail:
	  ctl->cmsg(CMSG_ERROR, VERB_NORMAL, "Error reading sample %d", i);
	  for (j=0; j<i; j++)
	    free(ip->sample[j].data);
	  free(ip->sample);
	  free(ip);
	  close_file(tf);
	  return 0;
	}

      sp=&(ip->sample[i]);

      sp->low_vel = 0;
      sp->high_vel = 127;

      READ_LONG(sp->data_length);
      READ_LONG(sp->loop_start);
      READ_LONG(sp->loop_end);
      READ_SHORT(sp->sample_rate);
      READ_LONG(sp->low_freq);
      READ_LONG(sp->high_freq);
      READ_LONG(sp->root_freq);

      skip(tf, 2); /* Why have a "root frequency" and then "tuning"?? */
      READ_CHAR(tmp[0]);
      ctl->cmsg(CMSG_INFO, VERB_DEBUG, "Rate/Low/Hi/Root = %d/%d/%d/%d",
		sp->sample_rate, sp->low_freq, sp->high_freq, sp->root_freq);

      if (panning==-1)
        {
          /* 0x07 and 0x08 are both center panning */
          if (tmp[0] <= 7)
            sp->panning = 64 + ((tmp[0] - 7) * 63) / 7;
          else if (tmp[0] >= 8)
            sp->panning = 64 + ((tmp[0] - 8) * 63) / 7;
	}
      else
	sp->panning=(uint8)(panning & 0x7F);

      /* envelope, tremolo, and vibrato */
      if (18 != tf_read(tmp, 1, 18, tf)) goto fail;

      if (!tmp[13] || !tmp[14])
	{
	  sp->tremolo_sweep_increment=
	    sp->tremolo_phase_increment=sp->tremolo_depth=0;
	  ctl->cmsg(CMSG_INFO, VERB_DEBUG, " * no tremolo");
	}
      else
	{
	  sp->tremolo_sweep_increment=convert_tremolo_sweep(tmp[12]);
	  sp->tremolo_phase_increment=convert_tremolo_rate(tmp[13]);
	  sp->tremolo_depth=tmp[14];
	  ctl->cmsg(CMSG_INFO, VERB_DEBUG,
	       " * tremolo: sweep %d, phase %d, depth %d",
	       sp->tremolo_sweep_increment, sp->tremolo_phase_increment,
	       sp->tremolo_depth);
	}

      if (!tmp[16] || !tmp[17])
	{
	  sp->vibrato_sweep_increment=
	    sp->vibrato_control_ratio=sp->vibrato_depth=0;
	  ctl->cmsg(CMSG_INFO, VERB_DEBUG, " * no vibrato");
	}
      else
	{
	  sp->vibrato_control_ratio=convert_vibrato_rate(tmp[16]);
	  sp->vibrato_sweep_increment=
	    convert_vibrato_sweep(tmp[15], sp->vibrato_control_ratio);
	  sp->vibrato_depth=tmp[17];
	  ctl->cmsg(CMSG_INFO, VERB_DEBUG,
	       " * vibrato: sweep %d, ctl %d, depth %d",
	       sp->vibrato_sweep_increment, sp->vibrato_control_ratio,
	       sp->vibrato_depth);
	}

      READ_CHAR(sp->modes);
      ctl->cmsg(CMSG_INFO, VERB_DEBUG, " * mode: 0x%02x", sp->modes);

      skip(tf, 40); /* skip the useless scale frequency, scale factor
		       (what's it mean?), and reserved space */

      /* Mark this as a fixed-pitch instrument if such a deed is desired. */
      if (note_to_use!=-1)
	sp->note_to_use=(uint8)(note_to_use);
      else
	sp->note_to_use=0;

      /* seashore.pat in the Midia patch set has no Sustain. I don't
         understand why, and fixing it by adding the Sustain flag to
         all looped patches probably breaks something else. We do it
         anyway. */

      if (sp->modes & MODES_LOOPING)
	sp->modes |= MODES_SUSTAIN;

      /* Strip any loops and envelopes we're permitted to */
      if ((strip_loop==1) &&
	  (sp->modes & (MODES_SUSTAIN | MODES_LOOPING |
			MODES_PINGPONG | MODES_REVERSE)))
	{
	  ctl->cmsg(CMSG_INFO, VERB_DEBUG, " - Removing loop and/or sustain");
	  sp->modes &=~(MODES_SUSTAIN | MODES_LOOPING |
			MODES_PINGPONG | MODES_REVERSE);
	}

      if (strip_envelope==1)
	{
	  if (sp->modes & MODES_ENVELOPE)
	    ctl->cmsg(CMSG_INFO, VERB_DEBUG, " - Removing envelope");
	  sp->modes &= ~MODES_ENVELOPE;
	}
      else if (strip_envelope != 0)
	{
	  /* Have to make a guess. */
	  if (!(sp->modes & (MODES_LOOPING | MODES_PINGPONG | MODES_REVERSE)))
	    {
	      /* No loop? Then what's there to sustain? No envelope needed
		 either... */
	      sp->modes &= ~(MODES_SUSTAIN|MODES_ENVELOPE);
	      ctl->cmsg(CMSG_INFO, VERB_DEBUG,
			" - No loop, removing sustain and envelope");
	    }
	  else if (!memcmp(tmp, "??????", 6) || tmp[11] >= 100)
	    {
	      /* Envelope rates all maxed out? Envelope end at a high "offset"?
		 That's a weird envelope. Take it out. */
	      sp->modes &= ~MODES_ENVELOPE;
	      ctl->cmsg(CMSG_INFO, VERB_DEBUG,
			" - Weirdness, removing envelope");
	    }
	  else if (!(sp->modes & MODES_SUSTAIN))
	    {
	      /* No sustain? Then no envelope.  I don't know if this is
		 justified, but patches without sustain usually don't need the
		 envelope either... at least the Gravis ones. They're mostly
		 drums.  I think. */
	      sp->modes &= ~MODES_ENVELOPE;
	      ctl->cmsg(CMSG_INFO, VERB_DEBUG,
			" - No sustain, removing envelope");
	    }
	}

      for (j=0; j<6; j++)
	{
	  sp->envelope_rate[j]=
	    convert_envelope_rate(tmp[j]);
	  sp->envelope_offset[j]=
	    convert_envelope_offset(tmp[6+j]);
	}

      /* this envelope seems to give reverb like effects to most patches */
      /* use the same method as soundfont */
      if (modify_release){
	

	sp->envelope_offset[3] = to_offset(5);
	sp->envelope_rate[3] = calc_rate(255, modify_release);

	sp->envelope_offset[4] = to_offset(4);
	sp->envelope_rate[4] = to_offset(200);

	sp->envelope_offset[5] = to_offset(4);
	sp->envelope_rate[5] = to_offset(200);
      }

      /* Then read the sample data */
      sp->data = (sample_t *)safe_malloc(sp->data_length+2);
      sp->data_alloced = 1;
      if ((j = tf_read(sp->data, 1, sp->data_length, tf)) != sp->data_length)
      {
	  ctl->cmsg(CMSG_ERROR, VERB_NORMAL, "Too small this patch length: %d < %d", j, sp->data_length);
	  goto fail;
      }

      if (!(sp->modes & MODES_16BIT)) /* convert to 16-bit data */
	{
	  int32 i = sp->data_length, j;
	  uint8 *cp = (uint8 *)sp->data;
	  uint16 *tmp, *new;
	  tmp = new = (uint16 *)safe_malloc(sp->data_length*2+2);
	  for(j = 0; j < i; j++)
	      tmp[j] = (uint16)(cp[j]) << 8;
	  cp=(uint8 *)(sp->data);
	  sp->data = (sample_t *)new;
	  free(cp);
	  sp->data_length *= 2;
	  sp->loop_start *= 2;
	  sp->loop_end *= 2;
	}
#ifndef LITTLE_ENDIAN
      else
	/* convert to machine byte order */
	{
	  int32 i=sp->data_length/2, j;
	  int16 *tmp=(int16 *)sp->data,s;
	  for(j = 0; j < i; j++)
	    {
	      s = LE_SHORT(tmp[j]);
	      tmp[j] = s;
	    }
	}
#endif

      if (sp->modes & MODES_UNSIGNED) /* convert to signed data */
	{
	  int32 i=sp->data_length/2;
	  int16 *tmp=(int16 *)sp->data;
	  while (i--)
	    *tmp++ ^= 0x8000;
	}

      /* Reverse reverse loops and pass them off as normal loops */
      if (sp->modes & MODES_REVERSE)
	{
	  int32 t;
	  /* The GUS apparently plays reverse loops by reversing the
	     whole sample. We do the same because the GUS does not SUCK. */

	  ctl->cmsg(CMSG_WARNING, VERB_NORMAL, "Reverse loop in %s", name);
	  reverse_data((int16 *)sp->data, 0, sp->data_length/2);

	  t=sp->loop_start;
	  sp->loop_start=sp->data_length - sp->loop_end;
	  sp->loop_end=sp->data_length - t;

	  sp->modes &= ~MODES_REVERSE;
	  sp->modes |= MODES_LOOPING; /* just in case */
	}

      /* If necessary do some anti-aliasing filtering  */
      if (antialiasing_allowed)
	  antialiasing((int16 *)sp->data, sp->data_length / 2,
		       sp->sample_rate,
		       play_mode->rate);

#ifdef ADJUST_SAMPLE_VOLUMES
      if (amp!=-1)
	sp->volume=(double)(amp) / 100.0;
      else
	{
	  /* Try to determine a volume scaling factor for the sample.
	     This is a very crude adjustment, but things sound more
	     balanced with it. Still, this should be a runtime option. */
	  int32 i=sp->data_length/2, j;
	  int32 maxamp=0,a;
	  int16 *tmp=(int16 *)sp->data;
	  for(j = 0; j < i; j++)
	    {
	      a=tmp[j];
	      if (a<0) a=-a;
	      if (a>maxamp)
		maxamp=a;
	    }
	  sp->volume=32768.0 / (double)(maxamp);
	  ctl->cmsg(CMSG_INFO, VERB_DEBUG, " * volume comp: %f", sp->volume);
	}
#else
      if (amp!=-1)
	sp->volume=(double)(amp) / 100.0;
      else
	sp->volume=1.0;
#endif

      sp->data_length /= 2; /* These are in bytes. Convert into samples. */
      sp->loop_start /= 2;
      sp->loop_end /= 2;

      /* The sample must be padded out by 1 extra sample, so that
         round off errors in the offsets used in interpolation will not
         cause a "pop" by reading random data beyond data_length */
      sp->data[sp->data_length] = sp->data[sp->data_length-1];

      /* Then fractional samples */
      sp->data_length <<= FRACTION_BITS;
      sp->loop_start <<= FRACTION_BITS;
      sp->loop_end <<= FRACTION_BITS;

      /* Adjust for fractional loop points. This is a guess. Does anyone
	 know what "fractions" really stands for? */
      sp->loop_start |=
	(fractions & 0x0F) << (FRACTION_BITS-4);
      sp->loop_end |=
	((fractions>>4) & 0x0F) << (FRACTION_BITS-4);

      /* If this instrument will always be played on the same note,
	 and it's not looped, we can resample it now. */
      if (sp->note_to_use && !(sp->modes & MODES_LOOPING))
	pre_resample(sp);

#ifdef LOOKUP_HACK
      /* Squash the 16-bit data into 8 bits. */
      {
	uint8 *gulp,*ulp;
	int16 *swp;
	int l=sp->data_length >> FRACTION_BITS;
	gulp = ulp = (uint8 *)safe_malloc(l + 1);
	swp=(int16 *)sp->data;
	while(l--)
	  *ulp++ = (*swp++ >> 8) & 0xFF;
	free(sp->data);
	sp->data=(sample_t *)gulp;
      }
#endif

      if (strip_tail==1)
	{
	  /* Let's not really, just say we did. */
	  ctl->cmsg(CMSG_INFO, VERB_DEBUG, " - Stripping tail");
	  sp->data_length = sp->loop_end;
	}
    }

  close_file(tf);
  store_instrument_cache(ip, name, panning, amp, note_to_use,
			 strip_loop, strip_envelope, strip_tail);
  return ip;
}

Instrument *load_instrument(int dr, int b, int prog)
{
    ToneBank *bank=((dr) ? drumset[b] : tonebank[b]);
    Instrument *ip;
    char infomsg[256];
    int font_bank, font_preset, font_keynote;

    if(bank->tone[prog].instype == 1
	|| bank->tone[prog].instype == 2)
    {
	if (bank->tone[prog].instype == 1)
	{
	    /* Font extention */
	    font_bank = bank->tone[prog].font_bank;
	    font_preset = bank->tone[prog].font_preset;
	    font_keynote = bank->tone[prog].font_keynote;
	    ip = extract_soundfont(bank->tone[prog].name,
			       font_bank, font_preset, font_keynote);
	}
	else
	{
	    /* Sample extension */
		extern Instrument *extract_sample_file(char *);
		
	    ip = extract_sample_file(bank->tone[prog].name);
	}
	if(ip != NULL && bank->tone[prog].amp != -1)	/* amp tuning */
	{
	    int i;
		FLOAT_T volume_max = 0;
		for(i = 0; i < ip->samples; i++) {
			if(ip->sample[i].volume > volume_max) {volume_max = ip->sample[i].volume;}
		}
		if(volume_max != 0) {
			for(i = 0; i < ip->samples; i++) {
				/*ip->sample[i].volume = bank->tone[prog].amp / 100.0;*/
				ip->sample[i].volume = (ip->sample[i].volume * (FLOAT_T)bank->tone[prog].amp) * 0.01 / volume_max;
			}
		}
	}
	if(ip != NULL && bank->tone[prog].pan != -1)	/* panning */
	{
	    int i, pan, panning;

		pan = ((int)bank->tone[prog].pan & 0x7F) - 64;

		for(i = 0; i < ip->samples; i++) {
			panning = (int)ip->sample[i].panning + pan;
			if(panning < 0) {panning = 0;}
			else if(panning > 127) {panning = 127;}
			ip->sample[i].panning = panning;
		}
	}
	if(ip != NULL && bank->tone[prog].note != -1)	/* note to use */
	{
	    int i;
		for(i = 0; i < ip->samples; i++) {
			ip->sample[i].root_freq = freq_table[bank->tone[prog].note & 0x7F];
		}
	}
	if(ip != NULL && bank->tone[prog].strip_tail == 1)	/* strip tail */
	{
	    int i;
		for(i = 0; i < ip->samples; i++) {
			ip->sample[i].data_length = ip->sample[i].loop_end;
		}
	}
	/* #extension cutoff / resonance */
	if(opt_resonance && ip != NULL) {
		int i,cutoff_freq = 0,resonance = 0;
		for(i = 0; i < ip->samples; i++) {
			if(cutoff_freq < ip->sample[i].cutoff_freq) {
				cutoff_freq = ip->sample[i].cutoff_freq;
			}/* else if(ip->sample[i].cutoff_freq == 0) {
				cutoff_freq = 0;
				resonance = 0;
				break;
			}*/
			if(ip->sample[i].resonance != 0) {
				if(resonance == 0) {resonance = ip->sample[i].resonance;}
				else if(resonance > ip->sample[i].resonance) {
					resonance = ip->sample[i].resonance;
				}
			}
		}	
		if(bank->tone[prog].cutoff_freq == 0) {
			bank->tone[prog].cutoff_freq = cutoff_freq;
		}
		if(bank->tone[prog].resonance == 0) {
			bank->tone[prog].resonance = resonance;
		}
	}
	if (ip != NULL) {
	  int i;
	  i = (dr ? 0 : prog);
	  if (bank->tone[i].comment)
	    free(bank->tone[i].comment);
	  bank->tone[i].comment = safe_strdup(ip->instname);
		apply_bank_parameter(ip, &bank->tone[prog]);
	}
	return ip;
    }

    if(dr)
    {
	font_bank = 128;
	font_preset = b;
	font_keynote = prog;
    }
    else
    {
	font_bank = b;
	font_preset = prog;
	font_keynote = -1;
    }

    /* preload soundfont */
    ip = load_soundfont_inst(0, font_bank, font_preset, font_keynote);
    if (ip != NULL) {
      if (bank->tone[prog].comment)
	free(bank->tone[prog].comment);
      bank->tone[prog].comment = safe_strdup(ip->instname);
    }

    if(ip == NULL)
    {
	/* load GUS/patch file */
	if(dr)
	    sprintf(infomsg, "Drumset %d %d(%s)", b + progbase, prog,
		    note_name[prog % 12]);
	else
	    sprintf(infomsg, "Tonebank %d %d", b, prog + progbase);

	ip = load_gus_instrument(bank->tone[prog].name, bank, dr, prog,
				 infomsg);

	if(ip == NULL) { /* no patch; search soundfont again */
	    ip = load_soundfont_inst(1, font_bank, font_preset, font_keynote);
            if (ip != NULL) {
	      if (bank->tone[0].comment)
		free(bank->tone[0].comment);
	      bank->tone[0].comment = safe_strdup(ip->instname);
	    }
	}
    }

	if (ip != NULL)
		apply_bank_parameter(ip, &bank->tone[prog]);
    return ip;
}

static int fill_bank(int dr, int b, int *rc)
{
    int i, errors = 0;
    ToneBank *bank=((dr) ? drumset[b] : tonebank[b]);

    if(rc != NULL)
	*rc = RC_NONE;

    for(i = 0; i < 128; i++)
    {
	if(bank->tone[i].instrument == MAGIC_LOAD_INSTRUMENT)
	{
	    if(!(bank->tone[i].name))
	    {
		bank->tone[i].instrument = load_instrument(dr, b, i);
		if(bank->tone[i].instrument == NULL)
		{
		    ctl->cmsg(CMSG_WARNING,
			      (b != 0) ? VERB_VERBOSE : VERB_NORMAL,
			      "No instrument mapped to %s %d, program %d%s",
			      dr ? "drum set" : "tone bank",
			      dr ? b+progbase : b,
			      dr ? i : i+progbase,
			      (b != 0) ? "" :
			      " - this instrument will not be heard");
		    if(b != 0)
		    {
			/* Mark the corresponding instrument in the default
			   bank / drumset for loading (if it isn't already) */
			if(!dr)
			{
			    if(!(standard_tonebank.tone[i].instrument))
				standard_tonebank.tone[i].instrument =
				    MAGIC_LOAD_INSTRUMENT;
			}
			else
			{
			    if(!(standard_drumset.tone[i].instrument))
				standard_drumset.tone[i].instrument =
				    MAGIC_LOAD_INSTRUMENT;
			}
			bank->tone[i].instrument = 0;
		    }
		    else
			bank->tone[i].instrument = MAGIC_ERROR_INSTRUMENT;
		    errors++;
		}
	    }
	    else
	    {
		if(rc != NULL)
		{
		    *rc = check_apply_control();
		    if(RC_IS_SKIP_FILE(*rc))
			return errors;
		}

		bank->tone[i].instrument = load_instrument(dr, b, i);
		if(!bank->tone[i].instrument)
		{
		    ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
			      "Couldn't load instrument %s "
			      "(%s %d, program %d)", bank->tone[i].name,
			      dr ? "drum set" : "tone bank",
			      dr ? b+progbase : b,
			      dr ? i : i+progbase);
		    errors++;
		}
	    }
	}
    }
    return errors;
}

int load_missing_instruments(int *rc)
{
  int i=128,errors=0;
  if(rc != NULL)
      *rc = RC_NONE;
  while (i--)
    {
      if (tonebank[i])
	errors+=fill_bank(0,i,rc);
      if(rc != NULL && RC_IS_SKIP_FILE(*rc))
	  return errors;
      if (drumset[i])
	errors+=fill_bank(1,i,rc);
      if(rc != NULL && RC_IS_SKIP_FILE(*rc))
	  return errors;
    }
  return errors;
}

void free_instruments(int reload_default_inst)
{
    int i=128, j;
    struct InstrumentCache *p;
    ToneBank *bank;
    Instrument *ip;
    struct InstrumentCache *default_entry;
    int default_entry_addr;

    clear_magic_instruments();

    /* Free soundfont instruments */
    while(i--)
    {
	/* Note that bank[*]->tone[j].instrument may pointer to
	   bank[0]->tone[j].instrument. See play_midi_load_instrument()
	   at playmidi.c for the implementation */

	if((bank = tonebank[i]) != NULL)
	    for(j = 127; j >= 0; j--)
	    {
		ip = bank->tone[j].instrument;
		if(ip != NULL && ip->type == INST_SF2 &&
		   (i == 0 || ip != tonebank[0]->tone[j].instrument))
		    free_instrument(ip);
		bank->tone[j].instrument = NULL;
	    }
	if((bank = drumset[i]) != NULL)
	    for(j = 127; j >= 0; j--)
	    {
		ip = bank->tone[j].instrument;
		if(ip != NULL && ip->type == INST_SF2 &&
		   (i == 0 || ip != drumset[0]->tone[j].instrument))
		    free_instrument(ip);
		bank->tone[j].instrument = NULL;
	    }
    }

    /* Free GUS/patch instruments */
    default_entry = NULL;
    default_entry_addr = 0;
    for(i = 0; i < INSTRUMENT_HASH_SIZE; i++)
    {
	p = instrument_cache[i];
	while(p != NULL)
	{
	    if(!reload_default_inst && p->ip == default_instrument)
	    {
		default_entry = p;
		default_entry_addr = i;
		p = p->next;
	    }
	    else
	    {
		struct InstrumentCache *tmp;

		tmp = p;
		p = p->next;
		free_instrument(tmp->ip);
		free(tmp);
	    }
	}
	instrument_cache[i] = NULL;
    }

    if(reload_default_inst)
	set_default_instrument(NULL);
    else if(default_entry)
    {
	default_entry->next = NULL;
	instrument_cache[default_entry_addr] = default_entry;
    }
}

void free_special_patch(int id)
{
    int i, j, start, end;

    if(id >= 0)
	start = end = id;
    else
    {
	start = 0;
	end = NSPECIAL_PATCH - 1;
    }

    for(i = start; i <= end; i++)
	if(special_patch[i] != NULL)
	{
	    Sample *sp;
	    int n;

	    if(special_patch[i]->name != NULL)
		free(special_patch[i]->name);
	    n = special_patch[i]->samples;
	    sp = special_patch[i]->sample;
	    if(sp)
	    {
		for(j = 0; j < n; j++)
		    if(sp[j].data_alloced && sp[j].data)
			free(sp[j].data);
		free(sp);
	    }
	    free(special_patch[i]);
	    special_patch[i] = NULL;
	}
}

int set_default_instrument(char *name)
{
    Instrument *ip;
    int i;
    static char *last_name;

    if(name == NULL)
    {
	name = last_name;
	if(name == NULL)
	    return 0;
    }

    if(!(ip = load_gus_instrument(name, NULL, 0, 0, NULL)))
	return -1;
    if(default_instrument)
	free_instrument(default_instrument);
    default_instrument = ip;
    for(i = 0; i < MAX_CHANNELS; i++)
	default_program[i] = SPECIAL_PROGRAM;
    last_name = name;

    return 0;
}

void alloc_instrument_bank(int dr, int bk)
{
    ToneBank *b;

    if(dr)
    {
	if((b = drumset[bk]) == NULL)
	{
	    b = drumset[bk] = (ToneBank *)safe_malloc(sizeof(ToneBank));
	    memset(b, 0, sizeof(ToneBank));
	}
    }
    else
    {
	if((b = tonebank[bk]) == NULL)
	{
	    b = tonebank[bk] = (ToneBank *)safe_malloc(sizeof(ToneBank));
	    memset(b, 0, sizeof(ToneBank));
	}
    }
}


/* Instrument alias map - Written by Masanao Izumo */

int instrument_map(int mapID, int *set, int *elem)
{
    int s, e;
    struct inst_map_elem *p;

    if(mapID == INST_NO_MAP)
	return 0; /* No map */

    s = *set;
    e = *elem;
    p = inst_map_table[mapID][s];
    if(p != NULL && p[e].mapped)
    {
	*set = p[e].set;
	*elem = p[e].elem;
	return 1;
    }

    if(s != 0)
    {
	p = inst_map_table[mapID][0];
	if(p != NULL && p[e].mapped)
	{
	    *set = p[e].set;
	    *elem = p[e].elem;
	}
	return 2;
    }
    return 0;
}

void set_instrument_map(int mapID,
			int set_from, int elem_from,
			int set_to, int elem_to)
{
    struct inst_map_elem *p;

    p = inst_map_table[mapID][set_from];
    if(p == NULL)
    {
		p = (struct inst_map_elem *)
	    safe_malloc(128 * sizeof(struct inst_map_elem));
	    memset(p, 0, 128 * sizeof(struct inst_map_elem));
		inst_map_table[mapID][set_from] = p;
    }
    p[elem_from].set = set_to;
    p[elem_from].elem = elem_to;
	p[elem_from].mapped = 1;
}

void free_instrument_map(void)
{
  int i, j;

  for (i = 0; i < NUM_INST_MAP; i++) {
    for (j = 0; j < 128; j++) {
      struct inst_map_elem *map;
      map = inst_map_table[i][j];
      if (map) {
	free(map);
	inst_map_table[i][j] = NULL;
      }
    }
  }
}

/* Alternate assign - Written by Masanao Izumo */

AlternateAssign *add_altassign_string(AlternateAssign *old,
				      char **params, int n)
{
    int i, j;
    char *p;
    int beg, end;
    AlternateAssign *alt;

    if(n == 0)
	return old;
    if(!strcmp(*params, "clear")) {
	while(old) {
	    AlternateAssign *next;
	    next = old->next;
	    free(old);
	    old = next;
	}
	params++;
	n--;
	if(n == 0)
	    return NULL;
    }

    alt = (AlternateAssign *)safe_malloc(sizeof(AlternateAssign));
    memset(alt, 0, sizeof(AlternateAssign));
    for(i = 0; i < n; i++) {
	p = params[i];
	if(*p == '-') {
	    beg = 0;
	    p++;
	} else
	    beg = atoi(p);
	if((p = strchr(p, '-')) != NULL) {
	    if(p[1] == '\0')
		end = 127;
	    else
		end = atoi(p + 1);
	} else
	    end = beg;
	if(beg > end) {
	    int t;
	    t = beg;
	    beg = end;
	    end = t;
	}
	if(beg < 0)
	    beg = 0;
	if(end > 127)
	    end = 127;
	for(j = beg; j <= end; j++)
	    alt->bits[(j >> 5) & 0x3] |= 1 << (j & 0x1F);
    }
    alt->next = old;
    return alt;
}

AlternateAssign *find_altassign(AlternateAssign *altassign, int note)
{
    AlternateAssign *p;
    uint32 mask;
    int idx;

    mask = 1 << (note & 0x1F);
    idx = (note >> 5) & 0x3;
    for(p = altassign; p != NULL; p = p->next)
	if(p->bits[idx] & mask)
	    return p;
    return NULL;
}
