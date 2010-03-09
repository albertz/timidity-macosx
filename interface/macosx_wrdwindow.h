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
#define BASE_X	8
#define	BASE_Y	16
#define TCOLOR_INDEX_SHIFT	32
#define TCODE2INDEX(attr)      ((((attr)&CATTR_TXTCOL_MASK)>>   \
                                 CATTR_TXTCOL_MASK_SHIFT)+TCOLOR_INDEX_SHIFT)
#define MAX_GWORLD   8

#define	GACTIVE_PIX	(wrdEnv.graphicWorld[wrdEnv.activeGraphics])
#define	GDISP_PIX	(wrdEnv.graphicWorld[wrdEnv.dispGraphics])
#define			DEV_SET_GMODE(mask)   \
                    (wrdEnv.gmode_mask=wrdEnv.gmode_mask_gline=(mask))

#define IS_MULTI_BYTE(c)    ( ((c)&0x80) && ((0x1 <= ((c)&0x7F) &&    \
                                                ((c)&0x7F) <= 0x1f) ||\
                              (0x60 <= ((c)&0x7F) && ((c)&0x7F) <= 0x7c)))

extern Rect portRect;

/***********************************************************************/
struct WrdEnv{
    WrdView	*wrdView;
    
    /*----------------*/
    /* buffers        */
    /*----------------*/
    NSBitmapImageRep 	*dispWorld32;
    NSBitmapImageRep 	*dispWorld;
    
    NSImage		*charBufImage;
    NSBitmapImageRep	*charBufImage_bm;
    NSBitmapImageRep	*graphicWorld[MAX_GWORLD];
    int             gworld_num;
    
    /*----------------*/
    /* graphics       */
    /*----------------*/
    int		    gmode_mask, gmode_mask_gline, gon_flag,
                    activeGraphics, dispGraphics,
                    dev_redrawflag;
    RGBColor        palette[20][256];
    int		    pallette_exist,
                    fading,startpal, endpal; //for @FADE
    NSMutableDictionary *dicAttr;
    /*----------------*/
    /* text           */
    /*----------------*/
    char	char_vram[30+1][80+2];
    char	char_color_vram[25+1][80+1];
    char	multi_byte_flag[25+1][80+1];
    int 	coursor_x, coursor_y;
    int 	text_color_attr, ton;
};

extern struct WrdEnv wrdEnv; 
extern int err_to_stop;
extern int  opt_wrddebug;


/***********************************************************************/
void dev_change_1_palette(int code, RGBColor color);
void dev_change_palette(RGBColor pal[16]);
void dev_draw_text_gmode(NSBitmapImageRep *img, int x, int y, const char* s,
                         int len,int pmask, int mode,
                         int fgcolor, int bgcolor, int ton_mode);
void dev_init_text_color();
void dev_gmove(int x1, int y1, int x2, int y2, int xd, int yd,
		NSBitmapImageRep *srcworld, NSBitmapImageRep *destworld,
                int sw, int trans, int pmask,
		int maskx, int masky, const uint8 maskdata[]);
void MyCopyBits(NSBitmapImageRep* srcPixmap, NSBitmapImageRep* dstPixmap,
		Rect srcRect, Rect dstRect, short mode, int trans, int pmask,
		int maskx, int masky, const uint8 maskdata[]);
void dev_gline(int x1, int y1, int x2, int y2, int p1, int sw, int p2,
                NSBitmapImageRep * world);
void dev_line(int x1, int y1, int x2, int y2, int color, int style,
	int pmask, NSBitmapImageRep *pixmap );
void dev_box(NSBitmapImageRep *pixmap, Rect rect, int color, int pmask);
void dev_circle(NSBitmapImageRep *pixmap, int cx, int cy, int r,
		int color, int fill_flg, int pmask);

void dev_make_disp32(NSBitmapImageRep *world8,NSBitmapImageRep *world32,
            Rect updaterect, RGBColor pal[256]);
void dev_redisp(Rect rect);

#ifdef ENABLE_SHERRY
void sry_start();
void sry_end();
void sry_update();
void sry_wrdt_apply( uint8* data, int len);
#import "png.h"
int mac_loadpng_pre( png_structp *png_ptrp, png_infop *info_ptrp,
		     struct timidity_file * tf);
int mac_loadpng(png_structp png_ptr, png_infop info_ptr,
		NSBitmapImageRep *world, RGBColor pal[256] );
void mac_loadpng_post(png_structp png_ptr, png_infop info_ptr);

void neo_start();
void neo_end();
void neo_update();
#endif
