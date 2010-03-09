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

    tables.h
*/

#ifndef ___TABLES_H_
#define ___TABLES_H_

#ifdef LOOKUP_SINE
extern FLOAT_T lookup_sine(int x);
#else
#include <math.h>
#define lookup_sine(x) (sin((2*M_PI/1024.0) * (x)))
#endif

#define SINE_CYCLE_LENGTH 1024
extern int32 freq_table[];
extern int32 freq_table2[][128];
extern FLOAT_T *vol_table;
extern FLOAT_T def_vol_table[];
extern FLOAT_T gs_vol_table[];
extern FLOAT_T *xg_vol_table; /* == gs_vol_table */
extern FLOAT_T bend_fine[];
extern FLOAT_T bend_coarse[];
extern FLOAT_T midi_time_table[], midi_time_table2[];
#ifdef LOOKUP_HACK
extern uint8 *_l2u; /* 13-bit PCM to 8-bit u-law */
extern uint8 _l2u_[]; /* used in LOOKUP_HACK */
extern int16 _u2l[];
extern int32 *mixup;
#ifdef LOOKUP_INTERPOLATION
extern int8 *iplookup;
#endif
#endif
extern uint8 reverb_macro_presets[];
extern uint8 chorus_macro_presets[];
extern uint8 delay_macro_presets[];
extern FLOAT_T delay_time_center_table[];
extern FLOAT_T pre_delay_time_table[];
extern FLOAT_T rate1_table[];
extern uint8 velocity_table[];
extern int opt_velocity_table;
extern FLOAT_T linear_vol_table[];
extern FLOAT_T log_vol_table[];
extern FLOAT_T exp_vol_table[];
extern FLOAT_T attack_vol_table[];
extern FLOAT_T envelope_coef[];
extern FLOAT_T sc_vel_table[];
extern FLOAT_T sc_vol_table[];
extern FLOAT_T sc_pan_table[];
extern FLOAT_T concave_table[];
extern FLOAT_T convex_table[];
extern FLOAT_T sb_vol_table[];
extern FLOAT_T cb_to_amp_table[];
extern int8 bitshift_table[];

extern void init_freq_table2(void);
extern void init_bend_fine(void);
extern void init_bend_coarse(void);
extern void init_tables(void);

#endif /* ___TABLES_H_ */
