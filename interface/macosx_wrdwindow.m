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
#import "macosx_wrdwindow.h"

Rect portRect ={0,0,480,640};
int err_to_stop;
int  opt_wrddebug=0;

/***********************************************************************/
void dev_change_1_palette(int code, RGBColor color)
{
    wrdEnv.palette[0][code]=color;
    wrdEnv.pallette_exist |= color.red;
    wrdEnv.pallette_exist |= color.green;
    wrdEnv.pallette_exist |= color.blue;
}

void dev_change_palette(RGBColor pal[16])
{					// don't update graphics
    int i;
    wrdEnv.pallette_exist=0;
    
    for( i=0; i<16; i++ ){
        dev_change_1_palette( i, pal[i]);
    }
}

void dev_init_text_color()
{
    const RGBColor gcolor[16]={  //???maybe???
        {0x0000, 0x0000, 0x0000}, //0:black
        {0x0000, 0x0000, 0xFFFF}, //blue
        {0xFFFF, 0x0000, 0x0000}, //red
        {0xFFFF, 0x0000, 0xFFFF}, //purple
        
        {0x0000, 0xFFFF, 0x0000},
        {0x0000, 0xFFFF, 0xFFFF}, //5:cyan
        {0xFFFF, 0xFFFF, 0x0000},
        {0xFFFF, 0xFFFF, 0xFFFF},
        
        {0x4444, 0x4444, 0x4444},
        {0x4444, 0x4444, 0xCCCC},
        {0xCCCC, 0x4444, 0x4444},
        {0xCCCC, 0x4444, 0xCCCC},
        
        {0x4444, 0xCCCC, 0x4444},
        {0x4444, 0xCCCC, 0xCCCC},
        {0xCCCC, 0xCCCC, 0x4444},
        {0xCCCC, 0xCCCC, 0xCCCC}
    };
    const RGBColor textcolor[8]
	={{0x0000,0x0000,0x0000},	//0: black
	{0xFFFF,0x0000,0x0000},	//1:red
	{0x0000,0xFFFF,0x0000},	//2:green
	{0xFFFF,0xFFFF,0x0000},	//3:yellow
	{0x0000,0x0000,0xFFFF},	//4:blue
	{0xFFFF,0x0000,0xFFFF},	//5:purpl
	{0x0000,0xFFFF,0xFFFF},	//6:mizuiro
	{0xFFFF,0xFFFF,0xFFFF} }; //7:white

    int code;
    for( code=0; code<=7; code++){
        wrdEnv.palette[0][code] = gcolor[code];
    }
    for( code=0; code<=7; code++){
            wrdEnv.palette[0][TCOLOR_INDEX_SHIFT+code]=textcolor[code];
    }
    wrdEnv.pallette_exist=1;
}

/***********************************************************************/
void dev_draw_text_gmode(NSBitmapImageRep *img, int x0, int y0, const char* s,
                         int len,int pmask, int mode,
                         int fgcolor, int bgcolor, int ton_mode)
{			//pixmap must be already locked
    NSString *sMessage= [NSString stringWithCString:s length:len];

    [ wrdEnv.charBufImage lockFocus ];

    //clear charbuf
    [ [NSColor blackColor] set ]; // 色を作成してセット
     [[ NSGraphicsContext currentContext] setShouldAntialias : NO ];
     NSRectFill( NSMakeRect(0,0,16,16) );           // 矩形の塗りつぶし
     [ sMessage drawAtPoint : NSMakePoint(0,1)
            withAttributes : wrdEnv.dicAttr ];
     [wrdEnv.charBufImage_bm initWithFocusedViewRect:NSMakeRect(0,0,16,16) ];
    [ wrdEnv.charBufImage unlockFocus ]; 

    //[ sMessage release];

    {
        int 	srcrowbytes = [wrdEnv.charBufImage_bm bytesPerRow],
                dstrowbytes = [img bytesPerRow];
        unsigned char 	*srcdata = [wrdEnv.charBufImage_bm bitmapData],
                        *dstdata = [img bitmapData];
        int              byteperpixel = [wrdEnv.charBufImage_bm bitsPerPixel]/8;
        int x,y;
        
        if( wrdEnv.ton==1 ){
            for( y=0; y<16; y++ ){
                uint8   *srcp = srcdata + y*srcrowbytes,
                        *dstp = dstdata + (y0+y)*dstrowbytes+x0;
                for( x=0; x<len*8; x++,srcp+=byteperpixel,dstp++ ){
                    if( *srcp>128 ){ //on
                        if( mode&1 ){
                            *dstp = fgcolor;
                        }
                    }else{ //off
                        if( mode&2 ){
                            *dstp = bgcolor;
                        }
                    }
                }
            }
        }else if(wrdEnv.ton==2){
            for( y=0; y<16; y++ ){
                uint8   *srcp = srcdata + y*srcrowbytes,
                        *dstp = dstdata + (y0+y)*dstrowbytes+x0;
                for( x=0; x<len*8; x++,srcp+=byteperpixel,dstp+=2 ){
                    if( *srcp>128 ){ //on
                        if( mode&1 ){
                            * dstp   = fgcolor;
                            *(dstp+1)= fgcolor;
                        }
                    }else{ //off
                        if( mode&2 ){
                            * dstp   = bgcolor;
                            *(dstp+1)= bgcolor;
                        }
                    }
                }
            }
        }
        
    }
    //[ img lockFocus ]; 
    // [wrdEnv.charBufImage compositeToPoint:NSMakePoint(x, 480-y)
    //    fromRect:NSMakeRect(0,0, BASE_X*len, BASE_Y )
    //    operation:NSCompositeSourceOver];
    //[ img unlockFocus ];



#if 0 /*toriaezu*/
    EraseRect(&rect);
    
    color= ( (mode&1)? fgcolor:trans );
    macwrd_textcolor=color;
    TextMode(srcOr);
    MoveTo(0,13);
    DrawText(s,0,len);
    if( ton_mode==2 ){
            expand_horizontality(charbuf_pixmap,
                                    len*8, 16);
    }
    
    width= len*8;
    if( ton_mode==2 ) width*=2;
    
    rect.right=width;
    destrect.left=x; destrect.top=y;
    destrect.right=x+width; destrect.bottom=destrect.top+16;
    
    dev_draw_text_gmode_copy( charbuf_pixmap,
                                pixmap,
                                x, y, width,
                                mode,fgcolor,bgcolor,pmask);
#endif
}

/***********************************************************************/
/***********************************************************************/
#define PMASK_COPY(s,d,pmask) ((d)=((d)&~(pmask))|((s)&(pmask)))

static void BlockMoveData_gmode(const void* srcPtr, void *destPtr,
                                        Size 	byteCount)
{
	int i;
	const char*	src= (char*)srcPtr;
	char*		dest= (char*)destPtr;
	
	if( srcPtr>destPtr ){
		for( i=0; i<byteCount; i++){
			PMASK_COPY(src[i],dest[i], wrdEnv.gmode_mask);
		}
	}else{
		for( i=byteCount-1; i>=0; i--){
			PMASK_COPY(src[i],dest[i], wrdEnv.gmode_mask);
		}
	}
}

static void BlockMoveData_swap(void* srcPtr, void *destPtr,
                                        Size 	byteCount)
{
    int i;
    char*	src= (char*)srcPtr;
    char*	dest= (char*)destPtr;
    char      	tmp;
    
    for( i=0; i<byteCount; i++){
        tmp=dest[i];
        dest[i]=src[i];
        src[i]=tmp;
        
    }
}
/***********************************************************************/
static void BlockMoveData_masktrans(const uint8*	srcPtr,	 uint8 *destPtr,
			Size 	byteCount, int trans, int maskx, const uint8 maskdata[])
{
#define  BITON(x, data) (data[(x)/8]&(0x80>>((x)%8)))
	int i;

	if( srcPtr>destPtr ){
		for( i=0; i<byteCount; i++){
			if(  srcPtr[i]!=trans  && BITON(i%maskx, maskdata)  ){
				PMASK_COPY(srcPtr[i],destPtr[i], wrdEnv.gmode_mask);
			}
		}
	}else{
		for( i=byteCount-1; i>=0; i--){
			if( BITON(i%maskx, maskdata)  ){
				PMASK_COPY(srcPtr[i],destPtr[i], wrdEnv.gmode_mask);
			}
		}
	}
}

/***********************************************************************/
static void BlockMoveData_transparent(const unsigned char* srcPtr, unsigned char *destPtr,
				Size byteCount, int pmask, int trans)
{
	int i, tmp;
	
	if( srcPtr>destPtr ){
		for( i=0; i<byteCount; i++, srcPtr++, destPtr++){
			if( *srcPtr !=trans ){
				tmp= *destPtr;
				tmp &= ~pmask;
				tmp |= ( (*srcPtr) & pmask);
				*destPtr= tmp;
			}
		}
	}else{
                i = byteCount-1;
                srcPtr  += byteCount-1;
                destPtr += byteCount-1;
		for( ; i>=0; i--, srcPtr--, destPtr--){
			if( *srcPtr !=trans ){
				tmp = *destPtr;
				tmp &= ~pmask;
				tmp |= ( (*srcPtr) & pmask);
				*destPtr = tmp;
			}
		}
	}
}

/***********************************************************************/
void MyCopyBits(NSBitmapImageRep* srcPixmap, NSBitmapImageRep* dstPixmap,
		Rect srcRect, Rect dstRect, short mode, int trans, int pmask,
		int maskx, int masky, const uint8 maskdata[])
{				   //I ignore destRect.right,bottom
    int srcRowBytes=  [srcPixmap bytesPerRow],
	destRowBytes= [dstPixmap bytesPerRow],
	y1, y2, width,hight, cut, dy, maskwidth;
    unsigned char  *srcAdr= [srcPixmap bitmapData],
                   *dstAdr= [dstPixmap bitmapData];	
    Rect	srcBounds={0,0,[srcPixmap pixelsHigh],[srcPixmap pixelsWide]},
                dstBounds={0,0,[dstPixmap pixelsHigh],[dstPixmap pixelsWide]};
	
  //check params
  //chech src top
    if( srcRect.top<srcBounds.top ){
	cut= srcBounds.top-srcRect.top;
	srcRect.top+=cut; dstRect.top+=cut;
    }
    if( srcRect.top>srcBounds.bottom ) return;
    //check left
    if( srcRect.left  <srcBounds.left ){
	cut= srcBounds.left-srcRect.left;
	srcRect.left+= cut; dstRect.left+=cut;
    }
    if( srcRect.left>srcBounds.right ) return;
    //chech src bottom
    if( srcRect.bottom>srcBounds.bottom ){
	cut= srcRect.bottom-srcBounds.bottom;
	srcRect.bottom-= cut; dstRect.bottom-=cut;
    }
    if( srcRect.bottom<srcBounds.top ) return;
    //check right
    if( srcRect.right >srcBounds.right ){
	cut= srcRect.right-srcBounds.right;
	srcRect.right-= cut; srcBounds.right-= cut;
    }
    if( srcRect.right<srcBounds.left ) return;
	
    width=srcRect.right-srcRect.left;
    hight=srcRect.bottom-srcRect.top;
	
	//check dest
	//check top
    if( dstRect.top  <dstBounds.top ){
	cut= dstBounds.top-dstRect.top;
	srcRect.top+=cut; dstRect.top+=cut;
    }
    if( dstRect.top>dstBounds.bottom ) return;
    //check hight
    if( dstRect.top+hight>dstBounds.bottom ){	
	hight=dstBounds.bottom-dstRect.top;
	srcRect.bottom=srcRect.top+hight;
    }
    //check left
    if( dstRect.left <dstBounds.left ){
	cut= dstBounds.left-dstRect.left;
	srcRect.left+= cut; dstRect.left+=cut;
    }
    if( dstRect.left>dstBounds.right ) return;
    //check width
    if( dstRect.left+width>dstBounds.right )
	width=dstBounds.right-dstRect.left;
	
    switch( mode ){
    case 0://srcCopy
    case 0x10:
	{
	    pascal void (*func)(const void* srcPtr, void *	destPtr,Size byteCount);
	    if( pmask==0xFF ) func=BlockMoveData;
	     else func= BlockMoveData_gmode;
	    if( srcRect.top >= dstRect.top ){
		for( y1=srcRect.top, y2=dstRect.top; y1<srcRect.bottom; y1++,y2++ ){
		    func( &(srcAdr[y1*srcRowBytes+srcRect.left]),
			  &(dstAdr[y2*destRowBytes+dstRect.left]), width);
		}
	    }else{
		for( y1=srcRect.bottom-1, y2=dstRect.top+hight-1;
                        y1>=srcRect.top;
                        y1--, y2-- ){
		    func( &(srcAdr[y1*srcRowBytes+srcRect.left]),
			  &(dstAdr[y2*destRowBytes+dstRect.left]), width);
		}
	    }
	}
	break;
        
    case 0x01://xor
	{
	    if( srcRect.top >= dstRect.top ){
		for( y1=srcRect.top, y2=dstRect.top; y1<srcRect.bottom; y1++,y2++ ){
		    BlockMoveData_swap( &(srcAdr[y1*srcRowBytes+srcRect.left]),
			  &(dstAdr[y2*destRowBytes+dstRect.left]), width);
		}
	    }else{
		for( y1=srcRect.bottom-1, y2=dstRect.top+hight-1;
                        y1>=srcRect.top;
                        y1--, y2-- ){
		    BlockMoveData_swap( &(srcAdr[y1*srcRowBytes+srcRect.left]),
			  &(dstAdr[y2*destRowBytes+dstRect.left]), width);
		}
	    }
	}
        break;
        
    case 0x11://transparent
	if( srcRect.top >= dstRect.top ){
	    for( y1=srcRect.top, y2=dstRect.top; y1<srcRect.bottom; y1++,y2++ ){
		BlockMoveData_transparent( &(srcAdr[y1*srcRowBytes+srcRect.left]),
					   &(dstAdr[y2*destRowBytes+dstRect.left]),
                                            width, pmask, trans);
	    }
	}else{
	    for( y1=srcRect.bottom-1, y2=dstRect.top+hight-1; y1>=srcRect.top; y1--, y2-- ){
		BlockMoveData_transparent( &(srcAdr[y1*srcRowBytes+srcRect.left]),
					   &(dstAdr[y2*destRowBytes+dstRect.left]),
                                            width, pmask, trans);
	    }
	}
	break;
        
    case 0x30:
    case 0x31: // masking & transparent //sherry op=0x62
	if( maskx<=0 ) break;
	maskwidth= ((maskx+7)& ~0x07)/8; //kiriage
	if( srcRect.top >= dstRect.top ){
	    for( y1=srcRect.top, y2=dstRect.top, dy=0; y1<srcRect.bottom;
            		y1++,y2++,dy++,dy%=masky ){
		BlockMoveData_masktrans( &(srcAdr[y1*srcRowBytes+srcRect.left]),
					 &(dstAdr[y2*destRowBytes+dstRect.left]),
                                          width, trans,
					 maskx, &maskdata[maskwidth*dy]);
	    }
	}else{
	    for( y1=srcRect.bottom-1, y2=dstRect.top+hight-1,dy=hight-1;
                    y1>=srcRect.top; y1--, y2--,dy+=masky-1, dy%=masky ){
		BlockMoveData_masktrans( &(srcAdr[y1*srcRowBytes+srcRect.left]),
					 &(dstAdr[y2*destRowBytes+dstRect.left]),
                                          width, trans,
					 maskx, &maskdata[maskwidth*dy]);
	    }
	}
	break;
    }
}

void dev_line(int x1, int y1, int x2, int y2, int color, int style,
	int pmask, NSBitmapImageRep *pixmap )
{
    int	i, dx, dy, s, step;
    int	rowBytes= [pixmap bytesPerRow];
    uint8*	baseAdr= [pixmap bitmapData];
    Rect	bounds={0,0,[pixmap pixelsHigh],[pixmap pixelsWide]};
    Point	pt;
    static const uint mask[8]={0x80,0x40,0x20,0x10, 0x08,0x04,0x02,0x01};
    int	style_count=0;

#define DOT(x,y,col) {uint8 *p=&baseAdr[(y)*rowBytes+(x)]; pt.h=(x);pt.v=(y); \
            if(PtInRect(pt,&bounds)){(*p)&=~pmask; (*p)|=col;} }
    
    color &= pmask;
    step= ( (x1<x2)==(y1<y2) ) ? 1:-1;
    dx= abs(x2-x1); dy=abs(y2-y1);
    
    if( dx>dy ){
            if( x1>x2 ){ x1=x2; y1=y2; }
            if(style & mask[style_count]){ DOT(x1,y1,color); }
                                    //else { DOT(x1,y1,0); }
            style_count= (style_count+1)%8;
            s= dx/2;
            for(i=x1+1; i<=x1+dx; i++){
                    s-= dy;
                    if( s<0 ){ s+=dx; y1+=step;}
                    if(style & mask[style_count]){ DOT(i,y1,color); }
                                            //else{ DOT(i,y1,0); }
                    style_count= (style_count+1)%8;
            }
    }else{
            if( y1>y2 ){ x1=x2; y1=y2; }
            if(style & mask[style_count]){ DOT(x1,y1,color); }
                                    //else{ DOT(x1,y1,0); }
            style_count= (style_count+1)%8;
            s= dy/2;
            for(i=y1+1; i<=y1+dy; i++){
                    s-= dx;
                    if( s<0 ){ s+=dy; x1+=step;}
                    if(style & mask[style_count]){ DOT(x1,i,color); }
                                            //else{ DOT(x1,i,0); }
                    style_count= (style_count+1)%8;
            }
    }
}

void dev_box(NSBitmapImageRep *pixmap, Rect rect, int color, int pmask)
{
    int	rowBytes= [pixmap bytesPerRow],
            x, y1, width,hight, tmp;
    uint8*	baseAdr= [pixmap bitmapData];
    Rect	bounds={0,0,[pixmap pixelsHigh],[pixmap pixelsWide]};
    
    //check params
    //chech src top
    if( rect.top<bounds.top ){
            rect.top=bounds.top;
    }
    if( rect.top>bounds.bottom ) return;
    //check left
    if( rect.left  <bounds.left ){
            rect.left= bounds.left;
    }
    if( rect.left>bounds.right ) return;
    //chech src bottom
    if( rect.bottom>bounds.bottom ){
            rect.bottom= bounds.bottom;
    }
    if( rect.bottom<bounds.top ) return;
    //check right
    if( rect.right >bounds.right ){
            rect.right= bounds.right;
    }
    if( rect.right<bounds.left ) return;
    
    width=rect.right-rect.left;
    hight=rect.bottom-rect.top;
    color &= pmask;

    for( y1=rect.top; y1<rect.bottom; y1++ ){
        for( x=rect.left; x<rect.right; x++){
            tmp=baseAdr[y1*rowBytes+x];
            tmp &= ~pmask;
            tmp |= color;
            baseAdr[y1*rowBytes+x]=tmp;
        }
    }
}

#define HOL_LINE(x0,x1,y,color) {   \
    int i;                          \
    for(i=(x0);i<=(x1);i++){        \
        DOT(i,(y),(color));         \
    }                               \
}

void dev_circle(NSBitmapImageRep *pixmap, int cx, int cy, int r,
		int color, int fill_flg, int pmask)
{
    int	dx, dy, s;
    int	rowBytes= [pixmap bytesPerRow];
    uint8*	baseAdr= [pixmap bitmapData];
    Rect	bounds={0,0,[pixmap pixelsHigh],[pixmap pixelsWide]};
    Point	pt;
	
    color &= pmask;

    dx = r;
    dy = 0;
    s = r;
    
    while( dx >= dy ){

	if( fill_flg ){
	    HOL_LINE(cx-dx,cx+dx,cy+dy,color);
	    HOL_LINE(cx-dx,cx+dx,cy-dy,color);
	    HOL_LINE(cx-dy,cx+dy,cy+dx,color);
	    HOL_LINE(cx-dy,cx+dy,cy-dx,color);
	}else{
	    DOT(cx+dx,cy+dy,color);
	    DOT(cx+dx,cy-dy,color);
	    DOT(cx-dx,cy+dy,color);
	    DOT(cx-dx,cy-dy,color);

	    DOT(cx+dy,cy+dx,color);
	    DOT(cx+dy,cy-dx,color);
	    DOT(cx-dy,cy+dx,color);
	    DOT(cx-dy,cy-dx,color);
	}
	s += -dy*2-1;
	dy++;
	if( s<0 ){
	    s += (dx-1)*2;
	    dx--;
	}
    }
}

/***********************************************************************/
void dev_make_disp32(NSBitmapImageRep *world8,NSBitmapImageRep *world32,
            Rect updaterect, RGBColor pal[256])
{
    int srcRowBytes=  [world8  bytesPerRow],
	destRowBytes= [world32 bytesPerRow];
    uint8	*srcAdr= [world8  bitmapData],
                *dstAdr= [world32 bitmapData];	
    Rect  	rect;
    Rect	srcBounds={0,0,[world8  pixelsHigh],[world8  pixelsWide]},
                dstBounds={0,0,[world32 pixelsHigh],[world32 pixelsWide]};
    int		x,y, pidx;
    uint32	palpix[256];

    if( ! SectRect(&srcBounds, &dstBounds, &rect) ){
	return;
    }
    if( ! SectRect(&updaterect, &rect, &rect) ){
	return;
    }
    
    for( pidx=0; pidx<256; pidx++ ){
    	palpix[pidx]= ((uint32)(pal[pidx].red>>8)<<24)
                  +((uint32)(pal[pidx].green>>8)<<16)
    		  + ((uint32)(pal[pidx].blue>>8)<<8)
                  +0xFF;
    }
    for( y=rect.top; y<rect.bottom; y++ ){
        uint8 *srcget=&srcAdr[y*srcRowBytes+rect.left],
              *dstput=&dstAdr[y*destRowBytes+rect.left*4];
	for( x=rect.left; x<rect.right; x++ ){
	    pidx = *srcget++;
	    #if 0
	    *(dstput+0)=pal[pidx].red>>8;
	    *(dstput+1)=pal[pidx].green>>8;
	    *(dstput+2)=pal[pidx].blue>>8;
	    *(dstput+3)=0xFF;
	    #else
	    *(uint32*)dstput = palpix[pidx];
	    #endif
	    dstput+=4;
	}
    }
}


