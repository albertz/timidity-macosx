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

   instrum.h

   */

#ifndef ___INSTRUM_H_
#define ___INSTRUM_H_

typedef struct _Sample {
  uint32
    loop_start, loop_end, data_length;
  int32
    sample_rate, low_freq, high_freq, root_freq;
  int8 panning, note_to_use;
  int32
    envelope_rate[6], envelope_offset[6];
  FLOAT_T
    volume;
  sample_t
    *data;
  int32
    tremolo_sweep_increment, tremolo_phase_increment,
    vibrato_sweep_increment, vibrato_control_ratio;
  uint16
    tremolo_depth;
  uint8
    vibrato_depth,
    modes, data_alloced,
    low_vel, high_vel;
  int16 cutoff_freq,resonance;
  FLOAT_T resonance_dB;
  int32
    mod_envelope_rate[6], mod_envelope_offset[6];
  FLOAT_T envelope_keyf[6], envelope_velf[6];
  int8 inst_type;
} Sample;

/* Bits in modes: */
#define MODES_16BIT	(1<<0)
#define MODES_UNSIGNED	(1<<1)
#define MODES_LOOPING	(1<<2)
#define MODES_PINGPONG	(1<<3)
#define MODES_REVERSE	(1<<4)
#define MODES_SUSTAIN	(1<<5)
#define MODES_ENVELOPE	(1<<6)
#define MODES_CLAMPED	(1<<7) /* ?? (for last envelope??) */

#define INST_GUS	0
#define INST_SF2	1
#define INST_MOD	2
#define INST_PCM	3	/* %sample */

typedef struct {
  int type;
  int samples;
  Sample *sample;
  char *instname;
} Instrument;

typedef struct {
  char *name;
  char *comment;
  Instrument *instrument;
  int8 note, pan, strip_loop, strip_envelope, strip_tail, loop_timeout,
	font_preset,font_keynote,legato,tva_level;
  uint8 font_bank;
  uint8 instype; /* 0: Normal
		    1: %font
		    2: %sample
		    3-255: reserved
		    */
  int16 amp,cutoff_freq,resonance;
  int tunenum;
  float *tune;
	int envratenum, envofsnum;
	int **envrate, **envofs;
	int tremnum, vibnum;
	struct Quantity_ **trem, **vib;
} ToneBankElement;

/* A hack to delay instrument loading until after reading the
   entire MIDI file. */
#define MAGIC_LOAD_INSTRUMENT ((Instrument *)(-1))
#define MAGIC_ERROR_INSTRUMENT ((Instrument *)(-2))
#define IS_MAGIC_INSTRUMENT(ip) ((ip) == MAGIC_LOAD_INSTRUMENT || (ip) == MAGIC_ERROR_INSTRUMENT)

typedef struct _AlternateAssign {
    /* 128 bit vector:
     * bits[(note >> 5) & 0x3] & (1 << (note & 0x1F))
     */
    uint32 bits[4];
    struct _AlternateAssign* next;
} AlternateAssign;

typedef struct {
  ToneBankElement tone[128];
  AlternateAssign *alt;
} ToneBank;

typedef struct _SpecialPatch /* To be used MIDI Module play mode */
{
    int type;
    int samples;
    Sample *sample;
    char *name;
    int32 sample_offset;
} SpecialPatch;

enum instrument_mapID
{
    INST_NO_MAP = 0,
    SC_55_TONE_MAP,
    SC_55_DRUM_MAP,
    SC_88_TONE_MAP,
    SC_88_DRUM_MAP,
    SC_88PRO_TONE_MAP,
    SC_88PRO_DRUM_MAP,
    XG_NORMAL_MAP,
    XG_SFX64_MAP,
    XG_SFX126_MAP,
    XG_DRUM_MAP,
    NUM_INST_MAP
};

extern ToneBank *tonebank[], *drumset[];

extern Instrument *default_instrument;
#define NSPECIAL_PATCH 256
extern SpecialPatch *special_patch[ /* NSPECIAL_PATCH */ ];
extern int default_program[MAX_CHANNELS];
extern int antialiasing_allowed;
extern int fast_decay;
extern int free_instruments_afterwards;
extern int cutoff_allowed;

#define SPECIAL_PROGRAM -1

/* sndfont.c */
extern void add_soundfont(char *sf_file, int sf_order,
			  int cutoff_allowed, int resonance_allowed,
			  int amp);
extern void remove_soundfont(char *sf_file);
extern void init_load_soundfont(void);
extern Instrument *load_soundfont_inst(int order, int bank, int preset,
				       int keynote);
extern Instrument *extract_soundfont(char *sf_file, int bank, int preset,
				     int keynote);
extern int exclude_soundfont(int bank, int preset, int keynote);
extern int order_soundfont(int bank, int preset, int keynote, int order);
extern char *soundfont_preset_name(int bank, int preset, int keynote,
				   char **sndfile);
extern void free_soundfont_inst(void);

/* instrum.c */
extern int load_missing_instruments(int *rc);
extern void free_instruments(int reload_default_inst);
extern void free_special_patch(int id);
extern int set_default_instrument(char *name);
extern void clear_magic_instruments(void);
extern Instrument *load_instrument(int dr, int b, int prog);
extern void alloc_instrument_bank(int dr, int bankset);
extern int instrument_map(int mapID, int *set_in_out, int *elem_in_out);
extern void set_instrument_map(int mapID,
			       int set_from, int elem_from,
			       int set_to, int elem_to);
extern void free_instrument_map(void);
extern AlternateAssign *add_altassign_string(AlternateAssign *old,
					     char **params, int n);
extern AlternateAssign *find_altassign(AlternateAssign *altassign, int note);
extern void free_instrument(Instrument *ip);

extern char *default_instrument_name;
extern int progbase;

extern int32 modify_release;
#define MAX_MREL 5000
#define DEFAULT_MREL 800

#endif /* ___INSTRUM_H_ */
