/*

    TiMidity++ -- MIDI to WAVE converter and player
    Copyright (C) 1999 Masanao Izumo <mo@goice.co.jp>
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

    macosx_sherry.h

    Written by by T.Nogami	<t-nogami@happy.email.ne.jp>

*/
#ifndef MACOSX_SHERRY_H_
#define MACOSX_SHERRY_H_

#define SRY_GET_RECT(rect, charp)    {rect.left=SRY_GET_SHORT(charp);      \
                                      rect.top=SRY_GET_SHORT((charp)+2);     \
                                      rect.right=SRY_GET_SHORT((charp)+4);   \
                                      rect.bottom=SRY_GET_SHORT((charp)+6);}
#define SRY_GET_POINT(point, charp)  {point.h=SRY_GET_SHORT(charp);      \
                                      point.v=SRY_GET_SHORT((charp)+2);}

#define SRY_HASHSIZE 16
#define SRY_HASH(x) ((x)&0x000F)
#define NEO_ASV_BASE  0x00010000

struct Sry_VImage_{
	int			img_id;
	NSBitmapImageRep	*world;
	int			width,height;
	uint8			trance_pallette; /*sherry only*/
        uint8			readonly;        /*neo only*/
	struct Sry_VImage_* 	synonym;
};
typedef struct Sry_VImage_ Sry_VImage;


struct Sry_Vpalette_{
	int	pal_id;
	RGBColor	pal[256];
	struct Sry_Vpalette_*	synonym;
};
typedef struct Sry_Vpalette_ Sry_Vpalette;

extern Sry_VImage* sry_vimage_hashtbl[SRY_HASHSIZE];
extern Sry_Vpalette* sry_vpal_hashtbl[SRY_HASHSIZE];
extern int isRealPaletteChanged, isRealScreenChanged;
extern Rect	updateSrcRect, updateDestRect;
extern int 	updateScrID;


void neo_wrdt_apply(const uint8* data, int len);
Sry_VImage* sry_find_vimage(int id);

#endif /*MACOSX_SHERRY_H_*/
