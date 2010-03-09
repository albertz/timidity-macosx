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
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

*/

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif /* HAVE_CONFIG_H */
#include <stdio.h>
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
#include "controls.h"
#include "wrd.h"

#import <Cocoa/Cocoa.h>
#import "macosx_WrdView.h"

/***********************************************************************/
#define LINES 25
#define COLS 80
#define SIZEX 640
#define SIZEY 400

//access macro
#define	CHAR_VRAM(x,y)        (wrdEnv.char_vram[y][x])
#define	CHAR_COLOR_VRAM(x,y)  (wrdEnv.char_color_vram[y][x])
#define	MULTI_BYTE_FLAG(x,y)  (wrdEnv.multi_byte_flag[y][x])  //...Umm
#define WRD_LOCX(x)	(((x)-1)*BASE_X)
#define WRD_LOCY(y)	(((y)-1)*BASE_Y)


#define CATTR_LPART (1)
#define CATTR_16FONT (1<<1)
#define CATTR_COLORED (1<<2)
#define CATTR_BGCOLORED (1<<3) 
#define CATTR_TXTCOL_MASK_SHIFT 4
#define CATTR_TXTCOL_MASK (7<<CATTR_TXTCOL_MASK_SHIFT)

#define SET_T_RGBFORECOLOR_TMP(attr)  /*toriaezu*/

/***********************************************************************/
void wrd_draw(NSRect rect);
/***********************************************************************/

