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
#import "wrdt_macosx.h"
#import "macosx_WrdView.h"
#import "macosx_wrdwindow.h"
#import "macosx_mag.h"
#import "VTparse.h"

/***********************************************************************/
// macros

#define WRD_DEBUG(x)	{if(opt_wrddebug){ ctl->cmsg x;}}
//#define WRD_DEBUG(x)
//#define WRD_DEBUG(x)	{ ctl->cmsg x;}


/***********************************************************************/
// function prototype
static int wrdt_open(char *wrdt_opts);
static void wrdt_apply(int cmd, int wrd_argc, int wrd_args[]);
static void wrdt_update_events(void);
static int  wrdt_start(int);
static void wrdt_end(void);
static void wrdt_close(void);

/***********************************************************************/
// globals

#define wrdt macosx_wrdt_mode
WRDTracer wrdt =
{
    "macosx WRD tracer", 'd',
    0,
    wrdt_open,
    wrdt_apply,
#ifdef ENABLE_SHERRY
    sry_wrdt_apply,
#else
    NULL,
#endif
    wrdt_update_events,
    wrdt_start,
    wrdt_end,
    wrdt_close
};

static int inkey_flag;
struct WrdEnv wrdEnv; 

/***********************************************************************/
static Rect loc2rect(int locx1, int locy1, int locx2, int locy2)
{
    Rect	rect;
	
    if( locx1 < 1 ) locx1=1;
    if( locx2 > COLS ) locx2=COLS;
    if( locy1 < 1 ) locy1=1;
    if( locy2 > LINES ) locy2=LINES;
	
    rect.top=WRD_LOCY(locy1);
    rect.left=WRD_LOCX(locx1);
    rect.bottom=WRD_LOCY(locy2)+15;
    rect.right=WRD_LOCX(locx2+1);
    return rect;
}

/***********************************************************************/
static void dev_text_redraw(int locx1, int locy1, int locx2, int locy2)
{
    int x,y,startx, mode,color, len;

#ifdef WRD_NO_TEXT
    return;
#endif

    if( !wrdEnv.ton ) return;
	
    if( locx1<1 ) locx1=1;
    if( locx2>80 ) locx2=80;
    if( locy1<1 ) locy1=1;
    if( locy2>25 ) locy2=25;
    if( wrdEnv.ton==2 ){
	//locx1-= (locx1-1)%4;
	locx1=1;
    }
	
    //TextMode(srcOr);
    for( y=locy1; y<=locy2; y++){
	startx=locx1;
	if( startx-1>=1 && MULTI_BYTE_FLAG(startx-1,y) )
	    startx--;
	for( x=startx; x<=locx2; ){
	    if( CHAR_VRAM(x,y)==0 ){ x++; continue;}
	    SET_T_RGBFORECOLOR_TMP(CHAR_COLOR_VRAM(x,y)&CATTR_TXTCOL_MASK);
	    mode= (CHAR_COLOR_VRAM(x,y)&CATTR_BGCOLORED)? 2:1;
	    color= TCODE2INDEX(CHAR_COLOR_VRAM(x,y));
	    len= MULTI_BYTE_FLAG(x,y)? 2:1;
            
	    if( wrdEnv.ton==1 && CHAR_VRAM(x,y)==' '
		    && (CHAR_COLOR_VRAM(x,y)&CATTR_BGCOLORED) ){
		Rect rect;              //speedy draw
		rect.top=WRD_LOCY(y);
		rect.left=WRD_LOCX(x);
		rect.bottom=rect.top+BASE_Y;
		rect.right=rect.left+BASE_X;
		dev_box(wrdEnv.dispWorld, rect, color, 0xFF);
		x++;
		continue;
	    }
	    /*if( wrd_ton==2 )*/{
		char *cp;
		if( MULTI_BYTE_FLAG(x-1,y) ){
		    cp= &CHAR_VRAM(x-1,y); len=2;
		    SET_T_RGBFORECOLOR_TMP(CHAR_COLOR_VRAM(x-1,y)
					   &CATTR_TXTCOL_MASK);
		    mode= (CHAR_COLOR_VRAM(x-1,y)&CATTR_BGCOLORED)? 2:1;
		    color= TCODE2INDEX(CHAR_COLOR_VRAM(x-1,y));
		}else{
		    cp= &CHAR_VRAM(x,y);
		}
		dev_draw_text_gmode( wrdEnv.dispWorld,
				     WRD_LOCX(x), WRD_LOCY(y),
				     cp, len, 0xFF, mode,
				     color, color, wrdEnv.ton );
		x+= (wrdEnv.ton==2? len*2:len);
		continue;
	    }
	}
    }
}


static void dev_text_redraw_rect(Rect rect)
{
    dev_text_redraw(rect.left/BASE_X+1, rect.top/BASE_Y+1,
			rect.right/BASE_X+1, rect.bottom/BASE_Y+1);
}

void dev_remake_disp(Rect rect)
{    
    if( wrdEnv.gon_flag){
        MyCopyBits(wrdEnv.graphicWorld[wrdEnv.dispGraphics], wrdEnv.dispWorld,
                rect, rect, 0, 0, 0xFF, 0,0,0);
    }else{
        dev_box(wrdEnv.dispWorld, rect, 0, 0xFF); //all pal=0 color
    }

    dev_text_redraw_rect(rect);
}

void dev_redisp(Rect rect)
{
#if 0
    [wrdEnv.wrdView setNeedsDisplay:YES]; //update all.(for debug)
#else
    NSRect  r;
    
#if 0
    if(readmidi_wrd_mode == WRD_TRACE_MIMPI){
        SectRect(&rect, &portRect, &rect);
    }else{
        SectRect(&rect, &portRect, &rect);        
    }
#endif

    r.origin.x = rect.left;
    r.origin.y = 480-(rect.bottom);
    r.size.width = rect.right-rect.left+1;
    r.size.height = rect.bottom-rect.top+1;
    
    dev_make_disp32(wrdEnv.dispWorld,wrdEnv.dispWorld32,
                    rect,wrdEnv.palette[0]);
    [wrdEnv.wrdView setNeedsDisplayInRect:r];
#endif
}


/***********************************************************************/
static void dev_move_coursor(int x, int y)
{
    if( x<1 ) x=1;
    else if( x>COLS ) x=COLS;
    if( y<1 ) y=1;
    else if( y>LINES ) y=LINES;

    wrdEnv.coursor_x=x;
    wrdEnv.coursor_y=y;
}

static void dev_set_text_attr(int esccode)
{
start:
    switch(esccode){
    default:
        esccode=37; goto start;

    case 17: esccode=31; goto start;
    case 18: esccode=34; goto start;
    case 19: esccode=35; goto start;
    case 20: esccode=32; goto start;
    case 21: esccode=33; goto start;
    case 22: esccode=36; goto start;
    case 23: esccode=37; goto start;

    case 16:
    case 30:
    case 31:
    case 32:
    case 33:
    case 34:
    case 35:
    case 36:
    case 37:
        wrdEnv.text_color_attr&=~CATTR_TXTCOL_MASK;
        wrdEnv.text_color_attr|=(
                        ((esccode>=30)?(esccode-30):(esccode-16))<<
                        CATTR_TXTCOL_MASK_SHIFT);
        wrdEnv.text_color_attr|=CATTR_COLORED;
        wrdEnv.text_color_attr&=~CATTR_BGCOLORED;
        break;
    case 40:
    case 41:
    case 42:
    case 43:
    case 44:
    case 45:
    case 46:
    case 47:
        wrdEnv.text_color_attr&=~CATTR_TXTCOL_MASK;
        wrdEnv.text_color_attr|=(esccode-40)<<CATTR_TXTCOL_MASK_SHIFT;
        wrdEnv.text_color_attr|=CATTR_BGCOLORED;
        break;
    }
}

static void dev_text_clear(int locx1, int locy1, int locx2, int locy2,
                            int color, char ch, int need_update)
{						// clear (x1,y1) .... (x2,y1)
    int		y, startx,endx, width;
    
    if( COLS<locx2 ) locx2=COLS;
    if( locx1<0 || COLS<locx1  || locx2<0 ||
            locy1<0 || LINES<locy1 || locy2<0 || LINES<locy2 ) return;
    if( locx2 < locx1 ) return;
    
    if( ch==' ' && !(color & 0x08) ){ch=0;}
    width=locx2-locx1+1;
    for( y=locy1; y<=locy2; y++ ){
            startx= locx1-(MULTI_BYTE_FLAG(locx1-1,y)? 1:0);
            endx= locx2+(MULTI_BYTE_FLAG(locx2,y)? 1:0);
            width=endx-startx+1;
            memset(&CHAR_VRAM(startx,y), ch, width);
            memset(&MULTI_BYTE_FLAG(startx,y), 0, width);
            memset(&CHAR_COLOR_VRAM(startx,y), color, width);
    }
    if( need_update ){
            Rect rect=loc2rect(locx1-1, locy1, locx2+1, locy2); //take margin
            dev_remake_disp(rect);
            dev_redisp(rect);
    }
}


static void dev_text_clear_all()
{
    memset(&CHAR_VRAM(0,0), 0, sizeof(wrdEnv.char_vram));
    memset(&MULTI_BYTE_FLAG(0,0), 0, sizeof(wrdEnv.multi_byte_flag));
}

static void dev_text_output(const char* text, int n)
{	
    int i, startx=wrdEnv.coursor_x, endx=wrdEnv.coursor_x+n-1;


    if( wrdEnv.coursor_x<=0 || 81<=wrdEnv.coursor_x ||
            wrdEnv.coursor_y<=0 || 26 <=wrdEnv.coursor_y ) return;

    dev_text_clear(startx, wrdEnv.coursor_y, endx, wrdEnv.coursor_y,
		   0, 0, false);
    for( i=0; i<n; i++ ){
	if( wrdEnv.coursor_x+i<=0 || 81<=wrdEnv.coursor_x+i ||
	    wrdEnv.coursor_y<=0 || 26 <=wrdEnv.coursor_y ) continue;
	CHAR_VRAM(wrdEnv.coursor_x+i,wrdEnv.coursor_y)=text[i];
	CHAR_COLOR_VRAM(wrdEnv.coursor_x+i,wrdEnv.coursor_y)
	    = wrdEnv.text_color_attr;
	if( IS_MULTI_BYTE(text[i]) ){
	    MULTI_BYTE_FLAG(wrdEnv.coursor_x+i,wrdEnv.coursor_y)=1;
	    if( i<n ){
		i++; CHAR_VRAM(wrdEnv.coursor_x+i,wrdEnv.coursor_y)=text[i];
		MULTI_BYTE_FLAG(wrdEnv.coursor_x+i,wrdEnv.coursor_y)=0;
	    }
	}
    }
    wrdEnv.coursor_x+=n;
    if( wrdEnv.ton==2) endx+=2;//expand
    
    dev_remake_disp(loc2rect(startx-1, wrdEnv.coursor_y,
                            endx+1, wrdEnv.coursor_y));
    dev_redisp(loc2rect(startx-1, wrdEnv.coursor_y,
                          endx+1, wrdEnv.coursor_y));
}

static void dev_text_scroll(int x1, int y1, int x2, int y2, int mode,
                        int color, char ch, int num)
{
	int y,width;

	if( num<=0 ) return;
	switch(mode)
	{
	case 0: //scroll upper
		for( y=y1; y<=y2 && y<=LINES; y++ ){
			if( y-num <y1 ) continue;
			memcpy(&CHAR_VRAM(1,y-num),&CHAR_VRAM(1,y),COLS);
			memcpy(&CHAR_COLOR_VRAM(1,y-num),&CHAR_COLOR_VRAM(1,y),COLS);
			memcpy(&MULTI_BYTE_FLAG(1,y-num),&MULTI_BYTE_FLAG(1,y),COLS);
		}
		dev_text_clear(x1, y2-num+1, x2, y2, color, ch, false);
		break;
	case 1: //scroll down
		for( y=y2; y>=y1 && y>=1; y-- ){
			if( y+num> y2 ) continue;
			memcpy(&CHAR_VRAM(1,y+num),&CHAR_VRAM(1,y),COLS);
			memcpy(&CHAR_COLOR_VRAM(1,y+num),&CHAR_COLOR_VRAM(1,y),COLS);
			memcpy(&MULTI_BYTE_FLAG(1,y+num),&MULTI_BYTE_FLAG(1,y),COLS);
		}
		dev_text_clear(x1, y1, x2, y1+num-1, color, ch, false);
		break;
	case 2: //scroll right
	case 3: //scroll left
		if( mode==3 ) num*=-1;
		if( x1+num<1 ) x1=1-num;
		if( x2+num>COLS ) x2=COLS-num;
		width=x2-x1+1; if( width<=0 ) break;
		for( y=y1; y<=y2 && y<=LINES; y++ ){
			memmove(&CHAR_VRAM(x1+num,y),&CHAR_VRAM(x1,y),width);
			memmove(&CHAR_COLOR_VRAM(x1+num,y),&CHAR_COLOR_VRAM(x1,y),width);
			memmove(&MULTI_BYTE_FLAG(x1+num,y),&MULTI_BYTE_FLAG(x1,y),width);
		}
		if( mode==2 ) //right
			dev_text_clear(x1, y1, x1+num-1, y2, color, ch, false);
		else if( mode==3 )
			dev_text_clear(x2+num+1, y1, x2, y2, color, ch, false);			
		break;
	}
}

static void dev_newline()
{
    if( wrdEnv.coursor_y>=25 ){
            dev_text_scroll(1, 1, 80, 25, 0, 0, 0, 1);
            dev_remake_disp(portRect);
            dev_redisp(portRect);
            dev_move_coursor(1, 25);
    }else{
            dev_move_coursor(1, wrdEnv.coursor_y+1);
    }
}

/***********************************************************************/
static void dev_clear_graphics(int pmask)
{				//clear active bank only
    dev_box(GACTIVE_PIX, portRect, 0, pmask);
    
    if( wrdEnv.activeGraphics==wrdEnv.dispGraphics ){
            dev_remake_disp(portRect);
            dev_redisp(portRect);
    }
}


#define  CHECK_RECT(rect) {            \
	short	tmp;                       \
	if( rect.left>rect.right ){ tmp=rect.left; rect.left=rect.right; rect.right=tmp;} \
	if( rect.top>rect.bottom ){ tmp=rect.top; rect.top=rect.bottom; rect.bottom=tmp;} \
}

void dev_gmove(int x1, int y1, int x2, int y2, int xd, int yd,
		NSBitmapImageRep *srcworld, NSBitmapImageRep *destworld,
                int sw, int trans, int pmask,
		int maskx, int masky, const uint8 maskdata[])
{
    static Rect	src,dest;
    
    if( srcworld==NULL || destworld==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL, "Can't use gvram bank" );
            return;
    }

    SetRect(&src,  x1,y1,x2+1,y2+1);		CHECK_RECT(src);
    SetRect(&dest, xd,yd, xd+x2-x1+1, yd+y2-y1+1);	CHECK_RECT(dest);


    if( sw==0 ){ //simple copy
        MyCopyBits(srcworld, destworld,
                    src, dest, 0, 0, wrdEnv.gmode_mask,0,0,0); //make offscreen Graphics
    } else if(sw==1){ //exchange
        MyCopyBits(srcworld, destworld,
                    src, dest, 1, 0, wrdEnv.gmode_mask,0,0,0); //make offscreen Graphics
    } else if(sw==2){	//xor copy
    #if 0 //atode
        CopyBits(GetPortBitMapForCopyBits(srcworld), GetPortBitMapForCopyBits(destworld),
                        &src, &dest, srcXor,0); //make offscreen Graphics
    #endif
    }else if( sw & 0x10 ){ //xcopy mode
        MyCopyBits( srcworld, destworld,
                src, dest, sw, trans, pmask, maskx, masky, maskdata); //make offscreen Graphics
    }
    
    if( wrdEnv.graphicWorld[wrdEnv.dispGraphics]==destworld ){
            dev_remake_disp(dest);
            dev_redisp(dest);
    }
    if( wrdEnv.graphicWorld[wrdEnv.dispGraphics]==srcworld && sw==1 ){
                                //exchange? update src
            dev_remake_disp(src);
            dev_redisp(src);
    }
}

static void dev_gscreen(int act, int dis)
{
    if( act!=0 && act!=1 ) return;
    if( dis!=0 && dis!=1 ) return;
    
    wrdEnv.activeGraphics=act;
    if( wrdEnv.dispGraphics!=dis ){
        wrdEnv.dispGraphics=dis;
        dev_remake_disp(portRect);
        dev_redisp(portRect);
    }
}

void dev_gline(int x1, int y1, int x2, int y2, int p1, int sw, int p2,
                NSBitmapImageRep * world)
{
    Rect	rect;
    
    rect.left=x1; rect.right=x2;
    rect.top=y1; rect.bottom=y2;
    CHECK_RECT(rect);
    
    switch(sw)
    {
    case 0: //line
            if( p2==0 || p2==WRD_NOARG ) p2= 0xFF;
            dev_line(x1, y1, x2, y2, p1,p2, wrdEnv.gmode_mask_gline,
                    world );
            break;
    case 1: //rect
            if( p2==0 || p2==WRD_NOARG ) p2= 0xFF;
            dev_line(x1, y1, x2, y1, p1,p2, wrdEnv.gmode_mask_gline,world );
            dev_line(x1, y1, x1, y2, p1,p2, wrdEnv.gmode_mask_gline,world );
            dev_line(x2, y1, x2, y2, p1,p2, wrdEnv.gmode_mask_gline,world );
            dev_line(x1, y2, x2, y2, p1,p2, wrdEnv.gmode_mask_gline,world );
            break;
    case 2:	//filled rect
            if( p2==WRD_NOARG ) p2= p1;
            rect.right++; rect.bottom++;
            dev_box(world, rect, p2, wrdEnv.gmode_mask_gline);
            if( p1!=p2 ){
                    dev_line(x1, y1, x2, y1, p1,0xFF, wrdEnv.gmode_mask_gline,world );
                    dev_line(x1, y1, x1, y2, p1,0xFF, wrdEnv.gmode_mask_gline,world );
                    dev_line(x2, y1, x2, y2, p1,0xFF, wrdEnv.gmode_mask_gline,world );
                    dev_line(x1, y2, x2, y2, p1,0xFF, wrdEnv.gmode_mask_gline,world );
            }
            break;
    }

    if( wrdEnv.graphicWorld[wrdEnv.dispGraphics]==world ){
            rect.right++; rect.bottom++;
            dev_remake_disp(rect);
            if( wrdEnv.pallette_exist) dev_redisp(rect);
    }
}

static void dev_gcircle(int x, int y, int r, int p1, int sw, int p2)
{
    Rect	rect;
    
    rect.left=x-r; rect.right=x+r;
    rect.top=y-r; rect.bottom=y+r;
    
    switch(sw){
    case 0:
    case 1: //frame
        dev_circle( GACTIVE_PIX, x, y, r,
                        p1, 0, wrdEnv.gmode_mask);

        break;
    case 2:	//filled circle
        dev_circle( GACTIVE_PIX, x, y, r,
                        p2, 1, wrdEnv.gmode_mask);
        dev_circle( GACTIVE_PIX, x, y, r,
                        p1, 0, wrdEnv.gmode_mask);
        break;
    }

    if( wrdEnv.activeGraphics==wrdEnv.dispGraphics ){
            rect.right++; rect.bottom++;
            dev_remake_disp(rect);
            dev_redisp(rect);
    }
}


/***********************************************************************/
//helpers

static void mac_wrd_color(int c)
{
    dev_set_text_attr(c);
}

/*VTParse Table externals*/
#define MAXPARAM 20
#define DEFAULT -1
#define TAB_SET 8
#define MBCS 1
#define CATTR_LPART (1)
#define CATTR_16FONT (1<<1)
#define CATTR_COLORED (1<<2)
#define CATTR_BGCOLORED (1<<3) 
#define CATTR_TXTCOL_MASK_SHIFT 4
#define CATTR_TXTCOL_MASK (7<<CATTR_TXTCOL_MASK_SHIFT)
#define CATTR_INVAL (1<<31)

static void DelChar(int x, int y){}
#define ClearLine(y) dev_text_clear(1, (y), 80, (y), 0, 0, false)
#define ClearRight()	dev_text_clear(wrdEnv.coursor_x, wrdEnv.coursor_y, 80, wrdEnv.coursor_y, 0, 0, false)
#define ClearLeft()		dev_text_clear(1, wrdEnv.coursor_y, wrdEnv.coursor_x, wrdEnv.coursor_y, 0, 0, false)

static void RedrawInject(int x1, int y1, int x2, int y2, Boolean f)
{
    Rect rect;
    SetRect(&rect,x1,y1,x2,y2);
    dev_remake_disp(rect);
    dev_redisp(rect);
}


static int Parse(int c)
{
  static const int *prstbl=groundtable;
  static char mbcs;
  static int params[MAXPARAM],nparam=0;
  static int hankaku=0;
  static int savcol,savline;
  static long savattr;

  if(c==-1) {
    prstbl=groundtable;
    mbcs=0;
    nparam=0;
    hankaku=0;
    savcol=savline=0;
    return 0;
  }

  if(mbcs&&
     prstbl !=mbcstable&&
     prstbl !=scstable&&
     prstbl !=scstable){
    mbcs=0;
  }
  switch(prstbl[c]){
  case CASE_IGNORE_STATE:
    prstbl=igntable;
    break;
  case CASE_IGNORE_ESC:
    prstbl=iestable;
    break;
  case CASE_ESC:
    prstbl=esctable;
    break;
  case CASE_ESC_IGNORE:
    prstbl=eigtable;
    break;
  case CASE_ESC_DIGIT:
    if(nparam<MAXPARAM){
      if(params[nparam]==DEFAULT){
	params[nparam]=0;
      }
      if( c==' ' ){
      	c='0';
      }
      params[nparam]*=10;
      params[nparam]+=c-'0';
    }
    break;
  case CASE_ESC_SEMI:
    nparam++;
    params[nparam]=DEFAULT;
    break;
  case CASE_TAB:
    wrdEnv.coursor_x+=TAB_SET;
    wrdEnv.coursor_x&=~(TAB_SET-1);
    break;
  case CASE_BS:
    if(wrdEnv.coursor_x > 0)
      wrdEnv.coursor_x--;
#if 0 /* ^H maybe work backward character in MIMPI's screen */
    DelChar(wrdEnv.coursor_y,wrdEnv.coursor_x);
    mywin.scrnbuf[wrdEnv.coursor_y][wrdEnv.coursor_x].c=0;
    mywin.scrnbuf[wrdEnv.coursor_y][wrdEnv.coursor_x].attr=0;
#endif
    break;
  case CASE_CSI_STATE:
    nparam=0;
    params[0]=DEFAULT;
    prstbl=csitable;
    break;
  case CASE_SCR_STATE:
    prstbl=scrtable;
    mbcs=0;
    break;
  case CASE_MBCS:
    hankaku=0;
    prstbl=mbcstable;
    mbcs=MBCS;
    break;
  case CASE_SCS_STATE:
    if(mbcs)
      prstbl=smbcstable;
    else
      prstbl=scstable;
    break;
  case CASE_GSETS:
    wrdEnv.text_color_attr=(mbcs)?(wrdEnv.text_color_attr|CATTR_16FONT):
      (wrdEnv.text_color_attr&~(CATTR_16FONT));
    if(!mbcs){
      hankaku=(c=='I')?1:0;
    }
    prstbl=groundtable;
    break;
  case CASE_DEC_STATE:
    prstbl =dectable;
    break;
  case CASE_SS2:
  case CASE_SS3:
    /*These are ignored because this will not accept SS2 SS3 charset*/
  case CASE_GROUND_STATE:
    prstbl=groundtable;
    break;
  case CASE_CR:
    wrdEnv.coursor_x=1;
    prstbl=groundtable;
    break;
  case CASE_IND:
  case CASE_VMOT:
    wrdEnv.coursor_y++;
    wrdEnv.coursor_x=1;
    prstbl=groundtable;
    break;
  case CASE_CUP:
    wrdEnv.coursor_y=(params[0]<1)?0:params[0];
    if(nparam>=1)
      wrdEnv.coursor_x=(params[1]<1)?0:params[1];
    else
      wrdEnv.coursor_x=0;
    prstbl=groundtable;
    break;
  case CASE_PRINT:
    if(wrdEnv.text_color_attr&CATTR_16FONT){
      if(!(wrdEnv.text_color_attr&CATTR_LPART)&&(wrdEnv.coursor_x==COLS)){
	wrdEnv.coursor_x++;
	return 1;
      }
      wrdEnv.text_color_attr^=CATTR_LPART;
    }
    else
      wrdEnv.text_color_attr&=~CATTR_LPART;
    DelChar(wrdEnv.coursor_y,wrdEnv.coursor_x);
    if(hankaku==1)
      c|=0x80;
    //mywin.scrnbuf[wrdEnv.coursor_y][wrdEnv.coursor_x].attr=wrdEnv.text_color_attr;
    //mywin.scrnbuf[wrdEnv.coursor_y][wrdEnv.coursor_x].c=c;
    wrdEnv.coursor_x++;
    break;
  case CASE_CUU:
    wrdEnv.coursor_y-=((params[0]<1)?1:params[0]);
    prstbl=groundtable;
    break;
  case CASE_CUD:
    wrdEnv.coursor_y+=((params[0]<1)?1:params[0]);
    prstbl=groundtable;
    break;
  case CASE_CUF:
    wrdEnv.coursor_x+=((params[0]<1)?1:params[0]);
    prstbl=groundtable;
    break;
  case CASE_CUB:
    wrdEnv.coursor_x-=((params[0]<1)?1:params[0]);
  	if( wrdEnv.coursor_x<1 ) wrdEnv.coursor_x=1;
    prstbl=groundtable;
    break;
  case CASE_ED:
    switch(params[0]){
    case DEFAULT:
    case 0:
      {
	int j;
	  ClearRight();
	for(j=wrdEnv.coursor_y+1;j<=LINES;j++)
	  ClearLine(j);	
      }
      break;
    case 1:
      {
	int j;
	  ClearLeft();
	for(j=1;j<wrdEnv.coursor_y;j++)
	  ClearLine(j);	
      }
      break;
    case 2:
      {
	//int j;
	//for(j=0;j<LINES;j++){
	//  free(mywin.scrnbuf[j]);
	//  mywin.scrnbuf[j]=NULL;
	//}
	dev_text_clear_all();
	wrdEnv.coursor_y=1;
	wrdEnv.coursor_x=1;
	break;
      }
    }
    RedrawInject(0,0,SIZEX,SIZEY,false);
    prstbl=groundtable;
    break;
  case CASE_DECSC:
    savcol=wrdEnv.coursor_x;
    savline=wrdEnv.coursor_y;
    savattr=wrdEnv.text_color_attr;
    prstbl=groundtable;
  case CASE_DECRC:
    wrdEnv.coursor_x=savcol;
    wrdEnv.coursor_y=savline;
    wrdEnv.text_color_attr=savattr;
    prstbl=groundtable;
    break;
  case CASE_SGR:
    {
      int i;
      for(i=0;i<nparam+1;i++)
		dev_set_text_attr(params[i]);
    }
    prstbl=groundtable;
    break;
  case CASE_EL:
    switch(params[0]){
    case DEFAULT:
    case 0:
      ClearRight();
      break;
    case 1:
      ClearLeft();
      break;
    case 2:
      ClearLine(wrdEnv.coursor_y);
      break;
    }
    RedrawInject(0,0,SIZEX,SIZEY,false);
    prstbl=groundtable;
    break;
  case CASE_NEL:
    wrdEnv.coursor_y++;
    wrdEnv.coursor_x=1;
    wrdEnv.coursor_y=(wrdEnv.coursor_y<LINES)?wrdEnv.coursor_y:LINES;
    break;
/*Graphic Commands*/
  case CASE_MY_GRAPHIC_CMD:
    //GrphCMD(params,nparam);
    prstbl=groundtable;
    break;
  case CASE_DL:
	dev_text_scroll(1, wrdEnv.coursor_y+params[0], COLS, LINES, 0, 0, 0, params[0]);
    RedrawInject(0,0,SIZEX,SIZEY,false);
	prstbl=groundtable;
	break;
/*Unimpremented Command*/
  case CASE_ICH:
  case CASE_IL:
  case CASE_DCH:
  case CASE_DECID:
  case CASE_DECKPAM:
  case CASE_DECKPNM:
  //case CASE_IND:
  case CASE_HP_BUGGY_LL:
  case CASE_HTS:
  case CASE_RI:
  case CASE_DA1:
  case CASE_CPR:
  case CASE_DECSET:
  case CASE_RST:
  case CASE_DECSTBM:
  case CASE_DECREQTPARM:
  case CASE_OSC:
  case CASE_RIS:
  case CASE_HP_MEM_LOCK:
  case CASE_HP_MEM_UNLOCK:
  case CASE_LS2:
  case CASE_LS3:
  case CASE_LS3R:
  case CASE_LS2R:
  case CASE_LS1R:
    ctl->cmsg(CMSG_INFO,VERB_VERBOSE,"NOT IMPREMENTED:%d\n",prstbl[c]);
    prstbl=groundtable;
    break;
  case CASE_BELL:
  case CASE_IGNORE:
  default:
    break;
  }
  if( prstbl==groundtable ) return 1;
  return 0;
}


static void mac_wrd_DrawText(const char *str, int len)
{
    int i;
    
    
    for( i=0; i<=len; ){
	if( str[i]==0 || i==len ){
	    dev_text_output(str, i);
	    break;
	}else if( wrdEnv.coursor_x+i>80 ){
	    dev_text_output(str, i);
	    dev_newline();
	    str+=i; len-=i; i=0;		
	}else if( str[i]=='\x1b' ){ //esc sequence
	    if( i ){
		dev_text_output(str, i);
		str+=i; len-=i; i=0;
	    }
	    for(;;i++){
		if( Parse(str[i]) ){
		    break; //esc sequence ended
		}
	    }
	    i++;
	    str+=i; len-=i; i=0;			
	}else if (str[i]=='\t' ){ //tab space
	    int newx;
	    dev_text_output(str, i);
	    newx=((wrdEnv.coursor_x-1)|7)+2;
	    dev_text_clear(wrdEnv.coursor_x, wrdEnv.coursor_y, newx-1,
			   wrdEnv.coursor_y, 0, 0, true);
	    dev_move_coursor(newx,wrdEnv.coursor_y);
	    i++;
	    str+=i; len-=i; i=0;
	}else{
	    i++;
	}
    }
}

static void mac_wrd_doESC(const char* code )
{
	char	str[20]="\33[";
	strcat(str, code);
	mac_wrd_DrawText(str, strlen(str));
}

static void mac_wrd_event_esc(int esc)
{	
	mac_wrd_doESC(event2string(esc)+1);
}

static void mac_wrd_pal(int pnum, int wrd_args[])
{
    int code;
    RGBColor color;
    
    for( code=0; code<16; code++ ){
        color.red=((wrd_args[code] >> 8) & 0x000F) * 0x1111;
        color.green=((wrd_args[code] >> 4) & 0x000F) * 0x1111;
        color.blue=(wrd_args[code] & 0x000F) * 0x1111;
        wrdEnv.palette[pnum][code]=color;
        if( pnum==0 ){
            dev_change_1_palette(code, color);
        }
    }

    if( pnum==0 ){
        dev_redisp(portRect);
    }
}

static void wrd_fadestep(int nowstep, int maxstep)
{
    RGBColor	pal[16];
    int code;
    //static unsigned long	lasttick=0;
    static int	skip_num;
    
    //if( nowstep!=1 && nowstep!=maxstep /*&& (nowstep%4)==0*/ && lasttick==TickCount() ){
    //	return;  //too fast fade. skip fading.
    //}
    
    if( nowstep==1 ){
            skip_num=0;
    }

#if 0
    if( nowstep!=maxstep && !mac_flushing_flag){	//consider skipping
            const int	skip_threshold[11]={99,99,8,6,4, 2,1,1,1,0,0};
            int	usedq=0, allq=100;
            int	threshold;
            
            play_mode->acntl(PM_REQ_GETFILLABLE,&allq);
            play_mode->acntl(PM_REQ_GETFILLED,&usedq);
#if   1
            threshold= skip_threshold[ (int)(aq_filled_ratio()*10) ];
#else
            threshold= skip_threshold[ usedq*10/allq ];
#endif
            if( skip_num<threshold ){
                    skip_num++;
                    return;     // system is busy
            }
    }
#endif

    skip_num=0;
    for( code=0; code<16; code++ ){
            pal[code].red=
                    (wrdEnv.palette[wrdEnv.startpal][code].red*(maxstep-nowstep) +
                            wrdEnv.palette[wrdEnv.endpal][code].red*nowstep)/maxstep;
            pal[code].green=
                    (wrdEnv.palette[wrdEnv.startpal][code].green*(maxstep-nowstep) +
                            wrdEnv.palette[wrdEnv.endpal][code].green*nowstep)/maxstep;
            pal[code].blue=
                    ((uint32)wrdEnv.palette[wrdEnv.startpal][code].blue*(maxstep-nowstep) +
                            (uint32)wrdEnv.palette[wrdEnv.endpal][code].blue*nowstep)/maxstep;
    }
    dev_change_palette(pal);
    dev_redisp(portRect);
    if( nowstep==maxstep ) wrdEnv.fading=false;
    //lasttick=TickCount();
}

static void mac_wrd_fade(int p1, int p2, int speed)
{
	wrdEnv.startpal=p1; wrdEnv.endpal=p2;
	if( wrdEnv.fading ){	//double fade command
		wrd_fadestep(1, 1);
	}
	if(speed==0){
		dev_change_palette( wrdEnv.palette[p2]);
		dev_redisp(portRect);
	}else{
		wrdEnv.fading=true;
	}
}

static void dev_gon(int gon)
{
    wrdEnv.gon_flag=gon;
    dev_remake_disp(portRect);
    dev_redisp(portRect);
}

static void dev_palrev(int paln )
{
    int code;
    for( code=0; code<16; code++ ){
            wrdEnv.palette[paln][code].red   ^= 0xFFFF;
            wrdEnv.palette[paln][code].green ^= 0xFFFF;
            wrdEnv.palette[paln][code].blue  ^= 0xFFFF;
    }
    if( paln==0 ){
            dev_change_palette(wrdEnv.palette[0]);
            dev_redisp(portRect);
    }
}

static int wrd_mag(char* filename, int x1, int y1, int s, int p)
{			//ok 0
                        //NG -1
    MagImage* magimg = macosx_mag_load(filename);
    int       x,y,i;
    
    if( ! magimg ){
        ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "macosx_mag_load NG");
        return -1;
    }
    
    if( x1==WRD_NOARG ){ x1=magimg->header.x1; }
    if( y1==WRD_NOARG ){ y1=magimg->header.y1; }
    if( s==WRD_NOARG ){ s=1; }
    if( p==WRD_NOARG ){ p=0; }
    
    
    //copy to buffer
    if( p==0 || p==2 ){
        for(i=0; i<16; i++){
            wrdEnv.palette[0][i] = magimg->palette[i];
        }
    }
    
    for(i=0; i<16; i++){
        wrdEnv.palette[17][i] = magimg->palette[i];
    }

    if( wrdEnv.activeGraphics==wrdEnv.dispGraphics ){
        for(i=0; i<16; i++){
            wrdEnv.palette[18][i] = magimg->palette[i];
        }
    }else{
        for(i=0; i<16; i++){
            wrdEnv.palette[19][i] = magimg->palette[i];
        }
    }

    if( p==0 || p==1 ){
        for( y=0; y<magimg->hight && y<480; y++ ){
            unsigned char *p=[wrdEnv.graphicWorld[wrdEnv.activeGraphics] bitmapData]
                                + (y1+y)*640;
            for( x=0; x<magimg->width && x<640; x++){
                p[x1+x] = magimg->data[ y*magimg->rowBytes +x ];
            }
        }
    }
    macosx_mag_free(magimg);
    
    //display
    dev_remake_disp(portRect);
    dev_redisp(portRect);
    return 0;
}

static int wrd_pho(char* filename)
{
    //char	fullpath[255];
    
    mac_pho_load(filename, GACTIVE_PIX);

    
    if( wrdEnv.activeGraphics==wrdEnv.dispGraphics ){
            dev_remake_disp(portRect);
            dev_redisp(portRect);
    }
    return 0; //no error
}
/***********************************************************************/
void dev_init(int version)
{
    int i;
    
    inkey_flag = 0;
    wrdEnv.gon_flag=1;
    dev_set_text_attr(37); //white
    //dev_change_1_palette(0, black);
    //dev_change_1_palette(16, black); //for gon(0)
    
    wrdEnv.gmode_mask=0xF;
    portRect.bottom = 480; //for cleaning
    dev_init_text_color();

    for(i=0; i<wrdEnv.gworld_num; i++){
        dev_gscreen(i, wrdEnv.dispGraphics); dev_clear_graphics(0xFF);
    }
    dev_gscreen(0, 0);

    dev_text_clear_all();
    wrdEnv.ton=1;
    dev_remake_disp(portRect);
    dev_redisp(portRect);

    dev_move_coursor(1,1);
    //startpal=endpal=0;
    //pallette_exist=true;
    //fading=false;
    Parse(-1); //initialize parser

    if(readmidi_wrd_mode == WRD_TRACE_MIMPI){
        portRect.bottom = 400;
    }else{
        portRect.bottom = 480;
    }
    wrd_init_path();
}

static OSErr get_vsscreen()
{
    if( (wrdEnv.graphicWorld[wrdEnv.gworld_num] = [NSBitmapImageRep alloc])==NULL ){
        return 1;
    }
    wrdEnv.graphicWorld[wrdEnv.gworld_num] = 
        [wrdEnv.graphicWorld[wrdEnv.gworld_num] initWithBitmapDataPlanes:NULL
            pixelsWide:640
            pixelsHigh:480
            bitsPerSample:8
            samplesPerPixel:1
            hasAlpha:NO
            isPlanar:NO
            colorSpaceName:NSCalibratedWhiteColorSpace
            bytesPerRow:0
            bitsPerPixel:0 ];
    if( wrdEnv.graphicWorld[wrdEnv.gworld_num]==NULL ){
        return 1;
    }

    WRD_DEBUG((CMSG_INFO, VERB_NORMAL, "get gvram bank %d",wrdEnv.gworld_num ));
    wrdEnv.gworld_num++;
    return 0;
}

static OSErr dev_vsget(int num)
{
    OSErr	err;
    int i;
    if(num+2>MAX_GWORLD){
        WRD_DEBUG((CMSG_INFO, VERB_NORMAL, "Too many vsget. %d",num ));
        return 1;
    }
    for( i=wrdEnv.gworld_num; i<2+num; i++ ){
            err=get_vsscreen();
            if( err ) return err;
    }
    return 0;
}

static OSErr dev_setup()	//return value: 0->noerr
{                               //	        other->err
    static OSErr	err=0;
    //int		i;
    Rect		destRect;
    
    if( err ) return err; // once errored, do not retry
    
    destRect.top=destRect.left=0;
    destRect.right=640;
    destRect.bottom=480;
    wrdEnv.gworld_num=0;
    
    //dispWorld32
    if( (wrdEnv.dispWorld32 = [NSBitmapImageRep alloc])==NULL ){
        return 1;
    }
    wrdEnv.dispWorld32 = [wrdEnv.dispWorld32 initWithBitmapDataPlanes:NULL
            pixelsWide:640
            pixelsHigh:480
            bitsPerSample:8
            samplesPerPixel:4
            hasAlpha:YES
            isPlanar:NO
            colorSpaceName:NSCalibratedRGBColorSpace
            bytesPerRow:0
            bitsPerPixel:0 ];
    if( wrdEnv.dispWorld32==NULL ){
        return 1;
    }
    
    //dispWorld
    if( (wrdEnv.dispWorld = [NSBitmapImageRep alloc])==NULL ){
        return 1;
    }
    wrdEnv.dispWorld = [wrdEnv.dispWorld initWithBitmapDataPlanes:NULL
            pixelsWide:640
            pixelsHigh:480
            bitsPerSample:8
            samplesPerPixel:1
            hasAlpha:NO
            isPlanar:NO
            colorSpaceName:NSCalibratedWhiteColorSpace
            bytesPerRow:0
            bitsPerPixel:0 ];
    if( wrdEnv.dispWorld==NULL ){
        return 1;
    }

    //graphicWorld[0]
    if( (wrdEnv.graphicWorld[0] = [NSBitmapImageRep alloc])==NULL ){
        return 1;
    }
    wrdEnv.graphicWorld[0] = [wrdEnv.graphicWorld[0] initWithBitmapDataPlanes:NULL
            pixelsWide:640
            pixelsHigh:480
            bitsPerSample:8
            samplesPerPixel:1
            hasAlpha:NO
            isPlanar:NO
            colorSpaceName:NSCalibratedWhiteColorSpace
            bytesPerRow:0
            bitsPerPixel:0 ];
    if( wrdEnv.graphicWorld[0]==NULL ){
        return 1;
    }
    //graphicWorld[1]
    if( (wrdEnv.graphicWorld[1] = [NSBitmapImageRep alloc])==NULL ){
        return 1;
    }
    wrdEnv.graphicWorld[1] = [wrdEnv.graphicWorld[1] initWithBitmapDataPlanes:NULL
            pixelsWide:640
            pixelsHigh:480
            bitsPerSample:8
            samplesPerPixel:1
            hasAlpha:NO
            isPlanar:NO
            colorSpaceName:NSCalibratedWhiteColorSpace
            bytesPerRow:0
            bitsPerPixel:0 ];
    if( wrdEnv.graphicWorld[1]==NULL ){
        return 1;
    }
    
    wrdEnv.gworld_num=2;
    
    {
        NSFont *fontAttr = [[ NSFont fontWithName : @"Osaka-Mono" size : 14 ] screenFont];
        wrdEnv.dicAttr=[ [ NSMutableDictionary alloc ] init ];
        [ wrdEnv.dicAttr setObject : [NSColor whiteColor  ]
                forKey : NSForegroundColorAttributeName ];
        [ wrdEnv.dicAttr setObject : [NSColor blackColor ]
                forKey : NSBackgroundColorAttributeName ];
        [ wrdEnv.dicAttr setObject : fontAttr
                forKey : NSFontAttributeName ]; 
    }
        
    //for( i=0; i<=1; i++){
    //	err=get_vsscreen();
    //	if( err ) return err;
    //}
    
    
    //mac_setfont(dispWorld, WRD_FONTNAME);

    dev_init(-1);
    wrdt.opened = 1;
    inkey_flag = 0;
    wrdEnv.charBufImage = [ [NSImage alloc] initWithSize:NSMakeSize( BASE_X*4, BASE_Y ) ];
    wrdEnv.charBufImage_bm = [NSBitmapImageRep alloc];
    return 0; //noErr
}

/***********************************************************************/

/*ARGSUSED*/
static int wrdt_open(char *wrdt_opts)
{
    OSErr  err;

    err=dev_setup();
    if( err ) return err;


    return 0;
}

static void wrdt_update_events(void)
{
    //ctl->cmsg(CMSG_INFO, VERB_VERBOSE,"update");
    //dev_remake_disp(portRect);
    //dev_redisp(portRect);
}

static int wrdt_start(int wrdflag)
{
    if( wrdflag ){
        int	i;
        err_to_stop=0;
        dev_init(-1);
        for( i=0; i<256; i++){
                //toriaezu
                //dev_change_1_palette(i, black);
        }
        wrdEnv.gmode_mask_gline=wrdEnv.gmode_mask=0xFF;
#ifdef ENABLE_SHERRY
        sry_start();
        neo_start();
#endif
        ctl->cmsg(CMSG_INFO, VERB_VERBOSE,
                    "WRD START");
    }
    return 0;
}

static void wrdt_end(void)
{
    inkey_flag = 0;
#ifdef ENABLE_SHERRY
    sry_end();
    neo_end();
#endif
    ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "WRD END");
}

static void wrdt_close(void)
{
    wrdt.opened = 0;
    inkey_flag = 0;
}

static char *wrd_event2string(int img_id)
{
    char *name;

    name = event2string(img_id);
    if(name != NULL)
	return name + 1;
    return "";
}

static void wrd_load_default_image()
{
    char	filename[256], *p;
    
    strcpy(filename, current_file_info->filename);
    p= strrchr( filename, '.' );
    if( p==0 ) return;
    strcpy( p, ".mag" );
    WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
                "@DEFAULT_LOAD_MAG(%s)", filename));

    if( wrd_mag(filename, WRD_NOARG, WRD_NOARG, 1,0)==0 ) //no err
            return;
            //retry pho file
    strcpy(filename, current_file_info->filename);
    p= strrchr( filename, '.' );
    if( p==0 ) return;
    strcpy( p, ".pho" );
    wrd_pho(filename);
}

static void print_ecmd(char *cmd, int *args, int narg)
{
    char *p;

    p = (char *)new_segment(&tmpbuffer, MIN_MBLOCK_SIZE);
    sprintf(p, "^%s(", cmd);

    if(*args == WRD_NOARG)
	strcat(p, "*");
    else
	sprintf(p + strlen(p), "%d", *args);
    args++;
    narg--;
    while(narg > 0)
    {
	if(*args == WRD_NOARG)
	    strcat(p, ",*");
	else
	    sprintf(p + strlen(p), ",%d", *args);
	args++;
	narg--;
    }
    strcat(p, ")");
    ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "%s", p);
    reuse_mblock(&tmpbuffer);
}

/***********************************************************************/
static void wrdt_apply(int cmd, int wrd_argc, int wrd_args[])
{
    char *p;
    char *text;
    int i, len;


    if(cmd == WRD_MAGPRELOAD)
	return; /* Load MAG file */
    if(cmd == WRD_PHOPRELOAD)
	return; /* Load PHO file - Not implemented */

    if(inkey_flag)
	printf("* ");
    switch(cmd)
    {
      case WRD_NL:
        WRD_DEBUG((CMSG_INFO, VERB_VERBOSE, "newline"));
      case WRD_LYRIC:
        if(cmd == WRD_NL)
                text = "\n";
        else{
                p = wrd_event2string(wrd_args[0]);
                len = strlen(p);
                text = (char *)new_segment(&tmpbuffer, SAFE_CONVERT_LENGTH(len));
                code_convert(p, text, SAFE_CONVERT_LENGTH(len), NULL, NULL);
        }
        len = strlen(text);
        WRD_DEBUG((CMSG_INFO, VERB_VERBOSE, "%s", text));
        if( len ){
            mac_wrd_DrawText(text, text[len-1]=='\n'? len-1:len);
            if( text[len-1]=='\n' ){
                dev_newline();
            }
        }
        reuse_mblock(&tmpbuffer);
	break;

      case WRD_COLOR:
        mac_wrd_color(wrd_args[0]);
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE, "@COLOR(%d)", wrd_args[0]));
	break;
      case WRD_END: /* Never call */
	break;
      case WRD_ESC:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@ESC(%s)", wrd_event2string(wrd_args[0])));
      	mac_wrd_event_esc(wrd_args[0]);
	break;
      case WRD_EXEC:
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE,
		  "@EXEC(%s)", wrd_event2string(wrd_args[0]));
	break;
      case WRD_FADE:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@FADE(%d,%d,%d)", wrd_args[0], wrd_args[1], wrd_args[2]));
	mac_wrd_fade(wrd_args[0], wrd_args[1], wrd_args[2]);
	break;
      case WRD_FADESTEP:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@FADESTEP(%d/%d)", wrd_args[0], WRD_MAXFADESTEP));
	wrd_fadestep(wrd_args[0], WRD_MAXFADESTEP);
	break;
      case WRD_GCIRCLE:
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE,
		  "@GCIRCLE(%d,%d,%d,%d,%d,%d)",
		  wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3],
		  wrd_args[4], wrd_args[5]);
	dev_gcircle(wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3],
		  wrd_args[4], wrd_args[5]);
	break;
      case WRD_GCLS:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@GCLS(%d)", wrd_args[0]));
	dev_clear_graphics(wrd_args[0]? wrd_args[0]:0xFF);
	break;
      case WRD_GINIT:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE, "@GINIT()"));
        dev_gscreen(0,0);
        dev_gon(1);
	break;
      case WRD_GLINE:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@GLINE(%d,%d,%d,%d,%d,%d,%d)",
	       wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3], wrd_args[4],
	       wrd_args[5], wrd_args[6]));
	dev_gline(wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3], wrd_args[4],
	       wrd_args[5], wrd_args[6],wrdEnv.graphicWorld[wrdEnv.activeGraphics]);
	break;
      case WRD_GMODE:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@GMODE(%d)", wrd_args[0]));
	DEV_SET_GMODE(wrd_args[0]);
	break;
      case WRD_GMOVE:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@GMOVE(%d,%d, %d,%d, %d,%d, %d,%d,%d)",
	       wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3], wrd_args[4],
	       wrd_args[5], wrd_args[6], wrd_args[7], wrd_args[8]));
	wrd_args[0] &= ~0x7;  wrd_args[4] &= ~0x7;  
	wrd_args[2] |= 0x7;
	if( wrd_args[6]==WRD_NOARG ){ wrd_args[6]=0; }
	if( wrd_args[7]==WRD_NOARG ){ wrd_args[7]=0; }
	if( wrd_args[8]==WRD_NOARG ){ wrd_args[8]=0; }
	dev_gmove(wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3], wrd_args[4],
	       wrd_args[5], wrdEnv.graphicWorld[wrd_args[6]],
               wrdEnv.graphicWorld[wrd_args[7]],
	       wrd_args[8], 0, wrdEnv.gmode_mask, 0,0,0);
	break;
      case WRD_GON:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@GON(%d)", wrd_args[0]));
        dev_gon(wrd_args[0]);
	break;
      case WRD_GSCREEN:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@GSCREEN(%d,%d)", wrd_args[0], wrd_args[1]));
	dev_gscreen(wrd_args[0], wrd_args[1]);
	break;
      case WRD_INKEY:
	inkey_flag = 1;
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "@INKEY - begin");
	break;
      case WRD_OUTKEY:
	inkey_flag = 0;
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "@INKEY - end");
	break;
      case WRD_LOCATE:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@LOCATE(%d,%d)", wrd_args[0], wrd_args[1]));
        dev_move_coursor(wrd_args[0], wrd_args[1]);
	break;
      case WRD_LOOP: /* Never call */
	break;
      case WRD_MAG:
	p = (char *)new_segment(&tmpbuffer, MIN_MBLOCK_SIZE);
	strcpy(p, "@MAG(");
	strcat(p, wrd_event2string(wrd_args[0]));
	strcat(p, ",");
	for(i = 1; i < 3; i++)
	{
	    if(wrd_args[i] == WRD_NOARG)
		strcat(p, "*,");
	    else
		sprintf(p + strlen(p), "%d,", wrd_args[i]);
	}
	sprintf(p + strlen(p), "%d,%d)", wrd_args[3], wrd_args[4]);
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "%s", p);
	reuse_mblock(&tmpbuffer);
        wrd_mag(wrd_event2string(wrd_args[0]), wrd_args[1], wrd_args[2],
                                        wrd_args[3], wrd_args[4]);
	break;
      case WRD_MIDI: /* Never call */
	break;
      case WRD_OFFSET: /* Never call */
	break;
      case WRD_PAL:
      	mac_wrd_pal( wrd_args[0], &wrd_args[1]);
	p = (char *)new_segment(&tmpbuffer, MIN_MBLOCK_SIZE);
	sprintf(p, "@PAL(%03x", wrd_args[0]);
	for(i = 1; i < 17; i++)
	    sprintf(p + strlen(p), ",%03x", wrd_args[i]);
	strcat(p, ")");
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "%s", p);
	reuse_mblock(&tmpbuffer);
	break;
      case WRD_PALCHG:
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE,
		  "@PALCHG(%s)", wrd_event2string(wrd_args[0]));
	break;
      case WRD_PALREV:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@PALREV(%d)", wrd_args[0]));
	dev_palrev(wrd_args[0]);
	break;
      case WRD_PATH:
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE,
		  "@PATH(%s)", wrd_event2string(wrd_args[0]));
	break;
      case WRD_PLOAD:
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE,
		  "@PLOAD(%s)", wrd_event2string(wrd_args[0]));
   	wrd_pho(wrd_event2string(wrd_args[0]));
	break;
      case WRD_REM:
	p = wrd_event2string(wrd_args[0]);
	len = strlen(p);
	text = (char *)new_segment(&tmpbuffer, SAFE_CONVERT_LENGTH(len));
	code_convert(p, text, SAFE_CONVERT_LENGTH(len), NULL, NULL);
	ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "@REM %s", text);
	reuse_mblock(&tmpbuffer);
	break;
      case WRD_REMARK:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@REMARK(%s)", wrd_event2string(wrd_args[0])));
	break;
      case WRD_REST: /* Never call */
	break;
      case WRD_SCREEN: /* Not supported */
	break;
      case WRD_SCROLL:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@SCROLL(%d,%d,%d,%d,%d,%d,%d)",
		  wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3],
		  wrd_args[4], wrd_args[5], wrd_args[6]));
	dev_text_scroll(wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3],
					wrd_args[4], wrd_args[5], wrd_args[6], 1);
	dev_remake_disp(portRect);
	dev_redisp(portRect);
	break;
      case WRD_STARTUP:
	inkey_flag = 0;
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@STARTUP(%d)", wrd_args[0]));
        if( wrd_args[0]<=0 || (380<=wrd_args[0] && wrd_args[0]<=399))
                        wrdEnv.gmode_mask_gline=0x7;  //change gline behavier
        else    wrdEnv.gmode_mask_gline=0xFF;
	wrd_load_default_image();
	break;
      case WRD_STOP: /* Never call */
	break;
      case WRD_TCLS:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@TCLS(%d,%d,%d,%d,%d,%d,%d)",
		  wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3],
		  wrd_args[4], wrd_args[5]));
	dev_text_clear(wrd_args[0], wrd_args[1], wrd_args[2],
                        wrd_args[3],wrd_args[4],wrd_args[5], true);
	break;
      case WRD_TON:
	WRD_DEBUG((CMSG_INFO, VERB_VERBOSE,
		  "@TON(%d)", wrd_args[0]));
        wrdEnv.ton=wrd_args[0];
	dev_remake_disp(portRect);
	dev_redisp(portRect);
	break;
      case WRD_WAIT: /* Never call */
	break;
      case WRD_WMODE: /* Never call */
	break;

	/* Ensyutsukun */
      case WRD_eFONTM:
	print_ecmd("FONTM", wrd_args, 1);
	break;
      case WRD_eFONTP:
	print_ecmd("FONTP", wrd_args, 4);
	break;
      case WRD_eFONTR:
	print_ecmd("FONTR", wrd_args, 17);
	break;
      case WRD_eGSC:
	print_ecmd("GSC", wrd_args, 1);
	break;
      case WRD_eLINE:
	print_ecmd("LINE", wrd_args, 1);
	break;
      case WRD_ePAL:
	print_ecmd("PAL", wrd_args, 2);
	break;
      case WRD_eREGSAVE:
	print_ecmd("REGSAVE", wrd_args, 17);
	break;
      case WRD_eSCROLL:
	print_ecmd("SCROLL",wrd_args, 2);
	break;
      case WRD_eTEXTDOT:
	print_ecmd("TEXTDOT", wrd_args, 1);
	break;
      case WRD_eTMODE:
	print_ecmd("TMODE", wrd_args, 1);
	break;
      case WRD_eTSCRL:
	print_ecmd("TSCRL", wrd_args, 0);
	break;
      case WRD_eVCOPY:
	print_ecmd("VCOPY", wrd_args, 9);
	wrd_args[0] &= ~0x7;  wrd_args[4] &= ~0x7;  
	wrd_args[2] |= 0x7;
	dev_gmove(wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3],
		wrd_args[4],wrd_args[5],
	        wrdEnv.graphicWorld[wrd_args[6]+(wrd_args[8]? 2:0)],
	       wrdEnv.graphicWorld[wrd_args[7]+ (wrd_args[8]? 0:2)],
               0/*normal copy*/,0,wrdEnv.gmode_mask,
	       0,0,0 );
			//ignore mode in this version, always EMS->GVRAM
	break;
      case WRD_eVSGET:
	print_ecmd("VSGE", wrd_args, 4);
	dev_vsget(wrd_args[0]);
	break;
      case WRD_eVSRES:
	print_ecmd("VSRES", wrd_args, 0);
	break;
      case WRD_eXCOPY:
	print_ecmd("XCOPY", wrd_args, 14);
	dev_gmove(wrd_args[0], wrd_args[1], wrd_args[2], wrd_args[3], wrd_args[4],
	     		wrd_args[5],
                        wrdEnv.graphicWorld[wrd_args[6]],
                        wrdEnv.graphicWorld[wrd_args[7]],
	     		  wrd_args[8]+0x10, 0/*trans*/, wrdEnv.gmode_mask, 0,0,0 );	
	break;
#ifdef ENABLE_SHERRY
      case WRD_SHERRY_UPDATE:
      	if( neowrd_flg ){
            neo_update();
        }else{
            sry_update();
        }
        break;
#endif

      default:
	break;
    }
    wrd_argc = 0;
}
