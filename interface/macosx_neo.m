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

    macosx_neo.c

    Written by by T.Nogami	<t-nogami@happy.email.ne.jp>

*/

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif /* HAVE_CONFIG_H */

#ifdef ENABLE_SHERRY

#include <stdlib.h>
#include <string.h>

#include "timidity.h"
#include "common.h"
#include "controls.h"
#include "instrum.h"
#include "playmidi.h"
#include "readmidi.h"
#include "aq.h"

#import "macosx_wrdwindow.h"
#include "macosx_sherry.h"


#define NEO_DEBUG(x)		{if(opt_wrddebug){ctl->cmsg x;}} 
//#define NEO_DEBUG(x)		{ctl->cmsg x;}
//#define NEO_DEBUG(x)		/*nothing*/
#define NEO_BPP  4 //byte per pixel

#define NEO_GET_COLOR(charp)  ( ((charp)[0]<<8) + ((charp)[1]<<16)  \
                            + ((charp)[2]<<24) + (charp)[3] ) 


uint32 neo_colormask[16]={
    0x00000000,
    0x0000FF00,
    0x00FF0000,
    0x00FFFF00,
    
    0xFF000000,
    0xFF00FF00,
    0xFFFF0000,
    0xFFFFFF00,
    
    0x000000FF,
    0x0000FFFF,
    0x00FF00FF,
    0x00FFFFFF,
    
    0xFF0000FF,
    0xFF00FFFF,
    0xFFFF00FF,
    0xFFFFFFFF
};

uint8  updateComBuf[1024];
int    updateComLen=0;  // 0 means no buffering.


/***********************************************************************/
/* DRCT inf                                                            */
/***********************************************************************/
//class NEO_DRCT_inf
struct NEO_DRCT_inf_
{
//public:
    uint16   defid;
    uint16   viid;
    Rect     rect;
    uint32   mask;
    uint32   extcolor;
    uint32   extmask;
    struct NEO_DRCT_inf_ *synonym;
};
typedef struct NEO_DRCT_inf_ NEO_DRCT_inf;

NEO_DRCT_inf* initWithCommand(const uint8* cmddata)
{
    NEO_DRCT_inf  *new_inf = (NEO_DRCT_inf*)malloc(sizeof(NEO_DRCT_inf));
    
    if( new_inf==NULL ){ return NULL; }
    new_inf->defid = SRY_GET_SHORT(cmddata);
    new_inf->viid  = SRY_GET_SHORT(cmddata+2);
    SRY_GET_RECT(new_inf->rect,cmddata+4);
    new_inf->mask = neo_colormask[cmddata[12]];
    new_inf->extcolor = NEO_GET_COLOR(cmddata+13);
    new_inf->extmask  = neo_colormask[cmddata[17]];
    new_inf->synonym = NULL;
    
    return new_inf;
}


static NEO_DRCT_inf *neo_drct_pool_top=NULL;

static void add_drct_inf(NEO_DRCT_inf *inf)
{
    inf->synonym=neo_drct_pool_top;
    neo_drct_pool_top = inf;
}

static NEO_DRCT_inf* find_drct(uint16 defid)
{
    NEO_DRCT_inf *inf=neo_drct_pool_top;
    while(inf){
        if(inf->defid==defid){
            return inf; //found.
        }else{
            inf = inf->synonym;
        }
    }
    return NULL; //not found.
}

static void neo_drct_allfree()
{
    NEO_DRCT_inf *inf=neo_drct_pool_top, *synonym;
    while(inf){
        synonym = inf->synonym;
        free(inf);
        inf = synonym;
    }
    neo_drct_pool_top=NULL;
}


/***********************************************************************/
/* utilitys                                                            */
/***********************************************************************/

static void copyBBLT( const uint8 *srcPtr, uint8 *destPtr, size_t numPixels, uint32 mask,
                    uint32 hoge1, uint32 hoge2)
{
    if( mask==0xFFFFFFFF ){
        memmove( destPtr, srcPtr, numPixels*NEO_BPP);
    }else{
        if( srcPtr>destPtr ){
            unsigned int i;
            for( i=0; i<numPixels; i++, srcPtr+=4,destPtr+=4){
                *(uint32*)destPtr &= ~mask;
                *(uint32*)destPtr |= (*(uint32*)srcPtr & mask);
            }
        }else{
            int i;
            srcPtr += (numPixels-1)*4;
            destPtr += (numPixels-1)*4;        
            for( i=numPixels-1; i>=0; i--, srcPtr-=4,destPtr-=4 ){
                *(uint32*)destPtr &= ~mask;
                *(uint32*)destPtr |= (*(uint32*)srcPtr & mask);
            }
        }
    }
}

static void copyBBLT_ablend( const uint8 *srcPtr, uint8 *destPtr, size_t numPixels,
                        uint32 mask, uint32 hoge1, uint32 hoge2)
{
    unsigned int i;
    uint8 r,g,b,a,R,G,B,A;
    uint8 tmp[4];
    
    if( srcPtr>destPtr ){
        for( i=0; i<numPixels; i++, srcPtr+=4,destPtr+=4){
            if( mask==0xFFFFFFFF && srcPtr[3]==0xFF ){
                *(uint32*)destPtr = *(uint32*)srcPtr; continue;
            }
            if(srcPtr[3]==0){continue;}
            R = srcPtr[0];
            G = srcPtr[1];
            B = srcPtr[2];
            A = srcPtr[3];
            r = destPtr[0];
            g = destPtr[1];
            b = destPtr[2];
            a = destPtr[3];
            tmp[0] = ((R*A)+(r*(255-A)))/255;
            tmp[1] = ((G*A)+(g*(255-A)))/255;
            tmp[2] = ((B*A)+(b*(255-A)))/255;
            tmp[3] = (255*255- (255-A)*(255-a))/255;
            *(uint32*)tmp &= mask;
            *(uint32*)destPtr &= ~mask;
            *(uint32*)destPtr |= *(uint32*)tmp;
        }
    }else{
        srcPtr += (numPixels-1)*4;
        destPtr += (numPixels-1)*4;        
        for( i=numPixels-1; i>=0; i--, srcPtr-=4,destPtr-=4 ){
            if( mask==0xFFFFFFFF && srcPtr[3]==0xFF ){
                *(uint32*)destPtr = *(uint32*)srcPtr; continue;
            }
            if(srcPtr[3]==0){continue;}
            R = srcPtr[0];
            G = srcPtr[1];
            B = srcPtr[2];
            A = srcPtr[3];
            r = destPtr[0];
            g = destPtr[1];
            b = destPtr[2];
            a = destPtr[3];
            tmp[0] = ((R*A)+(r*(255-A)))/255;
            tmp[1] = ((G*A)+(g*(255-A)))/255;
            tmp[2] = ((B*A)+(b*(255-A)))/255;
            tmp[3] = (255*255- (255-A)*(255-a))/255;
            *(uint32*)tmp &= mask;
            *(uint32*)destPtr &= ~mask;
            *(uint32*)destPtr |= *(uint32*)tmp;
        }
    }
}

static void copyBBLT_RBLT( const uint8 *srcPtr, uint8 *destPtr, size_t numPixels, uint32 mask,
                    uint32 extcolor, uint32 extmask)
{
    unsigned int i;
    for( i=0; i<numPixels; i++, srcPtr+=4,destPtr+=4){
        if( (*(uint32*)srcPtr&extmask) != (extcolor&extmask) ){
            *(uint32*)destPtr &= ~mask;
            *(uint32*)destPtr |= (*(uint32*)srcPtr & mask);
        }
    }
}


typedef void (*neo_cpyfunc_type)( const uint8 *srcPtr, uint8 *destPtr, size_t numPixels,
                    uint32 mask, uint32 extcolor, uint32 extmask ); 

static void neoCopy(NSBitmapImageRep* src, NSBitmapImageRep* dst,
                    uint32 mask, Rect srcRect, Point dstPoint,
                    uint32 extcolor, uint32 extmask, neo_cpyfunc_type cpyfunc)
{
    int	    srcRowBytes=  [src bytesPerRow],
	    destRowBytes= [dst bytesPerRow],
            y1,y2,width,hight, cut;
    unsigned char  *srcAdr= [src bitmapData],
                   *dstAdr= [dst bitmapData];
    Rect    dstRect = {dstPoint.v, dstPoint.h,
                    dstPoint.v+srcRect.bottom-srcRect.top,
                    dstPoint.h+srcRect.right-srcRect.left };
    Rect    srcBounds={0,0,[src pixelsHigh]-1,[src pixelsWide]-1},
            dstBounds={0,0,[dst pixelsHigh]-1,[dst pixelsWide]-1};
    //void (*cpyfunc)( const char *srcPtr, char *destPtr, size_t numPixels,
    //                uint32 mask );
    
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
	
    width=srcRect.right-srcRect.left+1;
    hight=srcRect.bottom-srcRect.top+1;

	//check dest
	//check top
    if( dstRect.top  <dstBounds.top ){
	cut= dstBounds.top-dstRect.top;
	srcRect.top+=cut; dstRect.top+=cut;
    }
    if( dstRect.top>dstBounds.bottom ) return;
    //check hight
    if( dstRect.top+hight-1>dstBounds.bottom ){	
	hight=dstBounds.bottom-dstRect.top+1;
	srcRect.bottom=srcRect.top+hight-1;
    }
    //check left
    if( dstRect.left <dstBounds.left ){
	cut= dstBounds.left-dstRect.left;
	srcRect.left+= cut; dstRect.left+=cut;
    }
    if( dstRect.left>dstBounds.right ) return;
    //check width
    if( dstRect.left+width-1>dstBounds.right )
	width=dstBounds.right-dstRect.left+1;


    if( srcRect.top >= dstRect.top ){
        for( y1=srcRect.top, y2=dstRect.top; y1<=srcRect.bottom; y1++,y2++ ){
            cpyfunc( &(srcAdr[y1*srcRowBytes+srcRect.left*NEO_BPP]),
                    &(dstAdr[y2*destRowBytes+dstRect.left*NEO_BPP]), width,
                        mask,extcolor,extmask);
        }
    }else{
        for( y1=srcRect.bottom-1, y2=dstRect.top+hight-1;
                y1>=srcRect.top;
                y1--, y2-- ){
            cpyfunc( &(srcAdr[y1*srcRowBytes+srcRect.left*NEO_BPP]),
                    &(dstAdr[y2*destRowBytes+dstRect.left*NEO_BPP]),
                     width, mask,extcolor,extmask);
        }
    }
    
}

static void neo_draw_box_core(NSBitmapImageRep* world, uint32 color, uint32 mask, Rect rect)
{
    int	    destRowBytes= [world bytesPerRow],
            x,y;
    unsigned char  *dstAdr= [world bitmapData], *dstp;

    if(rect.left<0){ rect.left=0; }
    if(rect.top<0){ rect.top=0; }
    if(rect.right>=[world pixelsWide]-1){ rect.right=[world pixelsWide]-1; }
    if(rect.bottom>=[world pixelsHigh]-1){ rect.bottom=[world pixelsHigh]-1; }
    color &= mask;
    
    for( y=rect.top; y<=rect.bottom; y++){
        dstp = &dstAdr[y*destRowBytes + rect.left*NEO_BPP];
        for( x=rect.left; x<=rect.right; x++,dstp+=4 ){
            *(int*)dstp &= ~mask;
            *(int*)dstp |= color;
            //*(int*)dstp = 0;
        }
    }
}

static void neo_add_alpha(NSBitmapImageRep* src, NSBitmapImageRep* dst)
{
    /* src and dst must be same width and height*/
    int	    srcRowBytes=  [src bytesPerRow],
	    destRowBytes= [dst bytesPerRow],
            x,y;
    unsigned char  *srcAdr= [src bitmapData], *srcp,
                   *dstAdr= [dst bitmapData], *dstp;
    Rect    srcBounds={0,0,[src pixelsHigh]-1,[src pixelsWide]-1};
            
    for( y=0; y<=srcBounds.bottom; y++){
        srcp = &srcAdr[y*srcRowBytes];
        dstp = &dstAdr[y*destRowBytes];
        for( x=0; x<=srcBounds.right; x++, srcp+=3, dstp+=4 ){
            unsigned char buf[4] = {srcp[0],srcp[1],srcp[2],0xFF};
            *(int*)dstp = *(int*)buf;
        }
    }
}

static void neo_8gray_32full(NSBitmapImageRep* src, NSBitmapImageRep* dst)
{
    /* src and dst must be same width and height*/
    int	    srcRowBytes=  [src bytesPerRow],
	    destRowBytes= [dst bytesPerRow],
            x,y;
    unsigned char  *srcAdr= [src bitmapData], *srcp,
                   *dstAdr= [dst bitmapData], *dstp;
    Rect    srcBounds={0,0,[src pixelsHigh]-1,[src pixelsWide]-1};
            
    for( y=0; y<=srcBounds.bottom; y++){
        srcp = &srcAdr[y*srcRowBytes];
        dstp = &dstAdr[y*destRowBytes];
        for( x=0; x<=srcBounds.right; x++, srcp++, dstp+=4 ){
            unsigned char buf[4] = {srcp[0],srcp[0],srcp[0],0xFF};
            *(int*)dstp = *(int*)buf;
        }
    }
}

static void  neo_loadpic_aread(NSBitmapImageRep* world)
{
    int	    rowBytes=  [world bytesPerRow],
            x,y;
    int     width = [world pixelsWide],
            heitht = [world pixelsHigh];
    uint8  *bitmap= [world bitmapData], *p;
    
    for( y=0; y<heitht; y++){
        p = &bitmap[y*rowBytes];
        for( x=0; x<width; x++, p+=4 ){
            uint8 buf[4]={0,0,0,p[2]};
            *(int*)p=*(int*)buf;
        }
    }
}


#define DOT(x,y,col) {uint32 *p=(uint32*)&baseAdr[(y)*rowBytes+(x)*NEO_BPP]; \
            pt.h=(x);pt.v=(y); \
            if(PtInRect(pt,&bounds)){(*p)&=~mask; (*p)|=col;} }

static void neo_draw_line_core(NSBitmapImageRep* dst, uint32 color, uint32 mask,
    int x1, int y1, int x2, int y2 )
{
    int			i, dx, dy, s, step;
    int			rowBytes= [dst bytesPerRow];
    unsigned char*	baseAdr= [dst bitmapData];
    Point		pt;

    //int	    destRowBytes= [world bytesPerRow],
    Rect	bounds={0,0,[dst pixelsHigh]-1,[dst pixelsWide]-1};


    
    color &= mask;
    step= ( (x1<x2)==(y1<y2) ) ? 1:-1;
    dx= abs(x2-x1); dy=abs(y2-y1);
    
    if( dx>dy ){
        if( x1>x2 ){ x1=x2; y1=y2; }
        DOT(x1,y1,color);
        s= dx/2;
        for(i=x1+1; i<=x1+dx; i++){
            s-= dy;
            if( s<0 ){ s+=dx; y1+=step;}
            DOT(i,y1,color);
        }
    }else{
        if( y1>y2 ){ x1=x2; y1=y2; }
        DOT(x1,y1,color);
        s= dy/2;
        for(i=y1+1; i<=y1+dy; i++){
            s-= dx;
            if( s<0 ){ s+=dy; x1+=step;}
            DOT(x1,i,color);
        }
    }
}

void neo_draw_text_core(NSBitmapImageRep *img, int x0, int y0,
        uint32 color, uint32 mask, const char* s, int len )
{
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


    {
        int 	srcrowbytes = [wrdEnv.charBufImage_bm bytesPerRow],
                dstrowbytes = [img bytesPerRow];
        unsigned char 	*srcdata = [wrdEnv.charBufImage_bm bitmapData],
                        *dstdata = [img bitmapData];
        int              byteperpixel = [wrdEnv.charBufImage_bm bitsPerPixel]/8;
        int x,y;
        
        for( y=0; y<16; y++ ){
            uint8   *srcp = srcdata + y*srcrowbytes,
                    *dstp = dstdata + (y0+y)*dstrowbytes+x0*NEO_BPP;
            for( x=0; x<len*8; x++,srcp+=byteperpixel,dstp+=NEO_BPP ){
                if( *srcp>128 ){ //on
                    *(uint32*)dstp = color;
                }
            }
        }
    }

}

/***********************************************************************/
/* commands                                                            */
/***********************************************************************/

#pragma mark -

#pragma mark -

static void neo_regVImage(int img_id, Sry_VImage* vimage )
{
	int hash= SRY_HASH(img_id);
	vimage->synonym= sry_vimage_hashtbl[hash];
	sry_vimage_hashtbl[hash]= vimage;    
}

static Sry_VImage* neo_new_gworld_core(int img_id, int width, int height,
                                       int readonly )
{
	NSBitmapImageRep	*new_world;
	Rect		destRect;
	Sry_VImage	*vimage;
        
        
        if( width ==0 ){ width= 65536; }
        if( height==0 ){ height=65536; }
        
	destRect.top=destRect.left=0;
	destRect.right= width;
	destRect.bottom= height;
	
	vimage= (Sry_VImage*)malloc(sizeof(Sry_VImage));
	if( vimage==0 ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY GET WORLD : id=%d cannot allocated.", img_id);
            err_to_stop=1;
            return NULL;
        }
	
        if( (new_world = [NSBitmapImageRep alloc])==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY GET WORLD : id=%d cannot allocated.", img_id);
            err_to_stop=1;
            free( vimage );
            return NULL;
        }
        new_world=[new_world initWithBitmapDataPlanes:NULL
                pixelsWide:(destRect.right - destRect.left)+1
                pixelsHigh:(destRect.bottom - destRect.top)+1
                bitsPerSample:8
                samplesPerPixel:4
                hasAlpha:YES
                isPlanar:NO
                colorSpaceName:NSCalibratedRGBColorSpace
                bytesPerRow:0
                bitsPerPixel:0 ];
        if( new_world==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY GET WORLD : id=%d cannot allocated.", img_id);
            err_to_stop=1;
            free( vimage );
            return NULL;
        }
        
	vimage->img_id= img_id;
	vimage->world= new_world;
	vimage->width= width;
	vimage->height= height;
        vimage->readonly = readonly;

	neo_regVImage( img_id, vimage );
        

	//clear
        neo_draw_box_core(vimage->world, 0x00000000, 0xFFFFFFFF, destRect);
        
	NEO_DEBUG((CMSG_INFO, VERB_NORMAL,
		"SHERRY GET WORLD : id=%d(%d,%d) allocated successfully.",
		img_id, width, height));
	return vimage;
}

static void neo_new_gworld(const uint8* data, int len) /*0x25*/
{
    int	i;
    
    for( i=1; i<len; i+=6 ){
        neo_new_gworld_core(
                SRY_GET_SHORT(data+i), SRY_GET_SHORT(data+i+2),
                SRY_GET_SHORT(data+i+4), false);
    }
    return;
}


static void neo_load_pic(const uint8 *data) /*0x27*/
{
    int	        img_id= SRY_GET_SHORT(data+1);
    int         flg= data[3];
    Sry_VImage*	vimage;
    char	*filename= (char*)data+4;
    char	fullpath[256], *p;

                    
    strcpy(fullpath, current_file_info->filename); //a little danger
    p= strrchr( fullpath, PATH_SEP );
    if( p==0 ) return;
    strcpy( p+1, filename );
    NEO_DEBUG((CMSG_INFO, VERB_NOISY,
                    "PNG27: try to load %s", fullpath));
    {
        struct timidity_file *tf;
        NSBitmapImageRep  *img;
        NSMutableData     *imgdata;
        
        tf= wrd_open_file(filename);
        if ( tf == NULL ){
                ctl->cmsg(CMSG_ERROR, VERB_NORMAL, "%s: open fail.", filename);
                err_to_stop=1;
                return;
        }
        
        img = [NSBitmapImageRep alloc];
        if( img==NULL ){
            ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"neo_load_pic:NSBitmapImageRep alloc: cannot allocated.",
                              img_id);
            err_to_stop=1;
            goto exit;
        }
        
        {
            uint8              buf[1024];
            long               read_bytes;
            imgdata = [NSMutableData dataWithCapacity:0];
            while( (read_bytes=tf_read(buf, 1, 1024, tf))!=0 ){
                [ imgdata appendBytes:buf length:read_bytes ];
            }
            img = [img initWithData:imgdata ];
            if( img==NULL ){
                ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
                            "neo_load_pic:initWithData: cannot allocated.", img_id);
                err_to_stop=1;
                return;            
            }
        }
        
        
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"bitsPerPixel=%d", [img bitsPerPixel]);
        if( [img bitsPerPixel]==32 ){
            vimage= (Sry_VImage*)malloc(sizeof(Sry_VImage));
            if( vimage==0 ){
                    ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
                            "SHERRY GET WORLD : id=%d cannot allocated.", img_id);
                goto exit;  // ? leak?
                return;
            }
            vimage->img_id= img_id;
            vimage->world= img;
            vimage->width=  [img pixelsWide];
            vimage->height= [img pixelsHigh];
            vimage->readonly = ((flg&0x01)?1:0);
            neo_regVImage( img_id, vimage );
            
        }else if( [img bitsPerPixel]==8 && [img colorSpaceName]==NSCalibratedWhiteColorSpace){
            vimage = neo_new_gworld_core( img_id,
                        [img pixelsWide], [img pixelsHigh], ((flg&0x01)?1:0) );
            if( vimage==NULL ){
                [img release];
                return;
            }
            neo_8gray_32full(img,vimage->world);
            [img release];
        }else if( [img bitsPerPixel]==24 ){
            vimage = neo_new_gworld_core( img_id,
                        [img pixelsWide], [img pixelsHigh], ((flg&0x01)?1:0) );
            if( vimage==NULL ){
                [img release];
                return;
            }
            neo_add_alpha(img,vimage->world);
            [img release];
        }

        if(flg&0x02){
            neo_loadpic_aread(vimage->world);
        }
        
      exit:
        close_file(tf);
    }
}

static void neo_alphasave(const uint8 *data, int len) /*0x2a*/
{
    int img_id = SRY_GET_SHORT(data+3);
    Sry_VImage	*from_vimage=sry_find_vimage(img_id),
                *to_vimage;


    if( from_vimage==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
            "neo_alphasave: %d not allocated.",img_id );
        err_to_stop=1;
        return;
    }
    to_vimage = neo_new_gworld_core( SRY_GET_SHORT(data+1)|NEO_ASV_BASE,
                [from_vimage->world pixelsWide],
                [from_vimage->world pixelsHigh], false);
    if( to_vimage==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
            "neo_alphasave: cannot not allocated." );
        err_to_stop=1;
        return;
    }
    {
        Rect rect = {0,0,[from_vimage->world pixelsHigh]-1,
                        [from_vimage->world pixelsWide]-1};
        Point p = {0,0};
        neoCopy(from_vimage->world, to_vimage->world,
                0x000000FF, rect, p,0,0, copyBBLT);
    }
}

static void neo_alphaload(const uint8 *data, int len) /*0x2b*/
{
    int from_id = SRY_GET_SHORT(data+1)|NEO_ASV_BASE,
        to_id   = SRY_GET_SHORT(data+3);
    Sry_VImage	*from_vimage=sry_find_vimage(from_id),
                *to_vimage=sry_find_vimage(to_id);
    int  scale = data[5];
    
    if( from_vimage==NULL || to_vimage==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
            "neo_alphaload: not allocated." );
        err_to_stop=1;
        return;
    }
    
    {
        NSBitmapImageRep  *src=from_vimage->world,
                            *dst=to_vimage->world;
        int	srcRowBytes=  [src bytesPerRow],
                destRowBytes= [dst bytesPerRow],
                x,y;
        unsigned char  *srcAdr= [src bitmapData], *srcp,
                    *dstAdr= [dst bitmapData], *dstp;
        Rect    srcBounds={0,0,[src pixelsHigh]-1,[src pixelsWide]-1};
                
        for( y=0; y<=srcBounds.bottom; y++){
            srcp = &srcAdr[y*srcRowBytes];
            dstp = &dstAdr[y*destRowBytes];
            for( x=0; x<=srcBounds.right; x++, srcp+=4, dstp+=4 ){
                unsigned char buf[4] = {dstp[0],dstp[1],dstp[2],
                                        (srcp[3]*scale)/255};
                *(int*)dstp = *(int*)buf;
            }
        }
    }
}


// ******************************************************************************
#pragma mark -

void neo_start()
{
    updateComLen=0;
}

void neo_end()
{
    neo_drct_allfree();
}


// ***************************************************************
#pragma mark -


static void neo_trans_partial_real_core(const uint8 *data, int len)
{
    int		img_id,  i;
    Rect	src;
    Point       dest;
    
    for( i=1; i<len; i+=14){
        img_id=SRY_GET_SHORT(data+i);
        src.left= SRY_GET_SHORT(data+i+2);
        src.top= SRY_GET_SHORT(data+i+4);
        src.right= SRY_GET_SHORT(data+i+6);
        src.bottom= SRY_GET_SHORT(data+i+8);
        
        dest.h= SRY_GET_SHORT(data+i+10);
        dest.v= SRY_GET_SHORT(data+i+12);
        
        NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
                "NEO TRANS : %d(%d,%d)-(%d,%d)->(%d,%d)", img_id,
                        src.left,src.top, src.right, src.bottom,
                        dest.h, dest.v ));
        {
        Sry_VImage	*vimage_src= sry_find_vimage(img_id);
	if( vimage_src==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"NEO TRANS : id=%d not allocated.", img_id);
		err_to_stop=1;
		return;
	}

        neoCopy(vimage_src->world, wrdEnv.dispWorld32, 0xFFFFFFFF,
                src, dest,0,0, copyBBLT_ablend);

        }
    }

    {
        NSRect  r;
        r.origin.x = 0;
        r.origin.y = 0;
        r.size.width = 640;
        r.size.height = 480;
        [wrdEnv.wrdView setNeedsDisplayInRect:r];
    }
}

void neo_update()
{
    if( err_to_stop ){ return; }
    if(updateComLen==0){ return; }
    if( aq_filled_ratio() < 0.25){ return; }
    
    NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
                "neo_update"));
    //if( isRealScreenChanged==YES ){
        neo_trans_partial_real_core(updateComBuf, updateComLen);
    //    isRealScreenChanged=NO;
    //}
}

static void neo_trans_partial_real_regist(const uint8 *data, int len)	/*0x39*/
{
    memcpy(updateComBuf, data, len);
    updateComLen = len;
    isRealScreenChanged=YES;
}

static void neo_drawtext(const uint8 *data, int len) /*0x51*/
{
    int		img_id= SRY_GET_SHORT(data+1);
    Sry_VImage*	vimage= sry_find_vimage(img_id);
    int     	x=SRY_GET_SHORT(data+3),y=SRY_GET_SHORT(data+5);
    uint32      color= NEO_GET_COLOR(data+7);
    uint32	mask= neo_colormask[data[11]];
    int         i;

    if( vimage==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
            "neo_drawtext: %d not allocated.",img_id );
        err_to_stop=1;
        return;
    }
    for( i=12; i<len; ){
            int dlen;
            dlen= (IS_MULTI_BYTE(data[i])? 2:1);
            //dev_draw_text_gmode(vimage->world, x+i*8, y,
              //      &data[i], dlen,
                //    pmask, mode, fore, back, 1 );
            neo_draw_text_core(vimage->world,  x,  y,
                    color, mask, &data[i], dlen );
            i+= dlen;
            x+= dlen*8;
    }
}


static void neo_draw_box(const uint8 *data, int len) /*52*/
{
    int	img_id= SRY_GET_SHORT(data+1);
    Sry_VImage*	vimage= sry_find_vimage(img_id);
    uint32      color= NEO_GET_COLOR(data+3);
    uint32	mask= neo_colormask[data[7]];
    int         i;

    
    if( vimage==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
            "neo_draw_box: %d not allocated.",img_id );
        err_to_stop=1;
        return;
    }
    for(i=8; i<len; i+=8){
        Rect rect;
        rect.left= SRY_GET_SHORT(data+i);
        rect.top= SRY_GET_SHORT(data+i+2);
        rect.right= SRY_GET_SHORT(data+i+4);
        rect.bottom= SRY_GET_SHORT(data+i+6);
        NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
            "box52 : id%d (%d,%d)-(%d,%d)", img_id,
                    rect.left,rect.top,
                    rect.right,rect.bottom));
        neo_draw_box_core(vimage->world,color,mask,rect);
    }
    
    //dev_gline(SRY_GET_SHORT(data+4),SRY_GET_SHORT(data+6),
      //      SRY_GET_SHORT(data+8),SRY_GET_SHORT(data+10),
        //                color, 2, color, vimage->world);
}

static void neo_draw_line(const uint8 *data, int len) /*0x55*/
{
    int	img_id= SRY_GET_SHORT(data+1);
    Sry_VImage*	vimage= sry_find_vimage(img_id);
    uint32      color = NEO_GET_COLOR(data+3);
    uint32      mask=neo_colormask[data[7]];
    int i;
    
    if( vimage==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
            "neo_draw_line: %d not allocated.",img_id );
        err_to_stop=1;
        return;
    }
    for(i=8; i<len; i+=8){
        int x1=SRY_GET_SHORT(data+i),
            y1=SRY_GET_SHORT(data+i+2),
            x2=SRY_GET_SHORT(data+i+4),
            y2=SRY_GET_SHORT(data+i+6);
        neo_draw_line_core(vimage->world, color, mask, x1,y1,x2,y2);
    }
}

static void neo_ColorReplace_core(NSBitmapImageRep* world, Rect rect,
        uint32 prev_color, uint32 prev_mask,
        uint32 aft_color, uint32 aft_mask)
{
    int	    destRowBytes= [world bytesPerRow],
            x,y;
    unsigned char  *dstAdr= [world bitmapData], *dstp;
    uint32  srch_color = prev_color&prev_mask,
            replace_color = aft_color&aft_mask;
    Rect    bounds={0,0,[world pixelsHigh]-1,[world pixelsWide]-1};
    
    
    SectRect (&bounds, &rect, &rect);
    for(y=rect.top; y<=rect.bottom; y++){
        dstp = &dstAdr[y*destRowBytes+rect.left*NEO_BPP];
        for(x=rect.left; x<=rect.right; x++, dstp+=NEO_BPP ){
            
            if( (*(uint32*)dstp & prev_mask)==srch_color ){
                *(uint32*)dstp = replace_color;
            }
        }
    }
}

static void neo_ColorReplace(const uint8 *data, int len) /*5a*/
{
    int	img_id= SRY_GET_SHORT(data+1);
    Sry_VImage*	vimage= sry_find_vimage(img_id);
    Rect rect;
    int  i;


    if( vimage==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
            "neo_ColorReplace: %d not allocated.",img_id );
        err_to_stop=1;
        return;
    }
    rect.left= SRY_GET_SHORT(data+3);
    rect.top= SRY_GET_SHORT(data+5);
    rect.right= SRY_GET_SHORT(data+7);
    rect.bottom= SRY_GET_SHORT(data+9);
    
    for( i=11; i<len; i+=10 ){
        neo_ColorReplace_core(vimage->world, rect,
                NEO_GET_COLOR(data+i), neo_colormask[data[i+4]],
                NEO_GET_COLOR(data+i+5), neo_colormask[data[i+9]] );
    }
    
}

static void neo_trans_partial(const uint8 *data, int len)	/*0x61,0x62*/
{
	int		srcid =SRY_GET_SHORT(data+1),
			destid= SRY_GET_SHORT(data+3);
	Sry_VImage	*vimage_src= sry_find_vimage(srcid),
			*vimage_dest= sry_find_vimage(destid);
	uint32		mask= neo_colormask[data[5]];
	int		maskx, masky;
	const uint8	*maskdata;
	int		i;
	
	if( vimage_src==NULL || vimage_src==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY TRANS 0x%02x: %d->%d not allocated.",data[0], srcid, destid );
		err_to_stop=1;
		return;
	}
	
	for( i=6; i<len; i+=12 ){
            Rect  rect={SRY_GET_SHORT(data+i+2),SRY_GET_SHORT(data+i),
                        SRY_GET_SHORT(data+i+6),SRY_GET_SHORT(data+i+4)};
            Point point={SRY_GET_SHORT(data+i+10),SRY_GET_SHORT(data+i+8)};
        
            neoCopy(vimage_src->world, vimage_dest->world,
                    mask, rect, point,0,0, copyBBLT );
        }
        
#if 0	
	if( mask!=0xFF ){
		NEO_DEBUG((CMSG_ERROR, VERB_NORMAL, "masking: 0x%02x, trans=%d",pmask,trans_flag));
	}



	if( maskingflg ){
		sw |= 0x20; //masking on
		maskx= data[19];
		masky= data[20];
		maskdata= data+21;
		/*if(  pmask!=0xFF ){
			ctl->cmsg(CMSG_ERROR, VERB_NORMAL, "masking & gmode, not supported yet");
			//err_to_stop=1;
		}
		if( trans_flag ){
			ctl->cmsg(CMSG_ERROR, VERB_NORMAL, "masking & trans, not supported yet");
			//err_to_stop=1;
		}*/
	}else{
		maskx = masky = 0;
		maskdata= NULL;
	}

	NEO_DEBUG((CMSG_INFO, VERB_NOISY,
	  		"SHERRY TRANS 62: %d->%d sw%d mask0x%x.",data[0], srcid, destid, sw, pmask ));
	dev_gmove(SRY_GET_SHORT(data+7), SRY_GET_SHORT(data+9),
			SRY_GET_SHORT(data+11), SRY_GET_SHORT(data+13),
			SRY_GET_SHORT(data+15), SRY_GET_SHORT(data+17),
			vimage_src->world, vimage_dest->world,
			sw, trance_pallette, pmask, maskx, masky, maskdata);
#endif
}

static void neo_DRCT(const uint8 *data, int len) /*0x41*/
{
    NEO_DRCT_inf  *new_inf = initWithCommand(&data[1]);
    
    if( new_inf==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
                "NEO DRCT : fail." );
        err_to_stop=1;
        return;
    }
    add_drct_inf(new_inf);
}

static void neo_RBLT(const uint8 *data, int len) /*0x6f*/
{
    int		destid =SRY_GET_SHORT(data+1);
    Sry_VImage	*image_src, *image_dest= sry_find_vimage(destid);

    int i;


    if( image_dest==NULL ){
        ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
                "NEO RBLT 0x%02x: %d not allocated.",data[0], destid );
        err_to_stop=1;
        return;
    }
    
    for( i=3; i<len; i+=6 ){
        Point          point;
        int            defid=SRY_GET_SHORT(&data[i]);
        NEO_DRCT_inf  *inf;
        
        inf=find_drct(defid);
        if(inf==NULL){
            ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
                    "NEO RBLT 0x%02x: %d not defined.",data[0], defid );
            err_to_stop=1;
            return;
        }
        image_src = sry_find_vimage(inf->viid);
        if( image_src==NULL ){
            ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
                    "NEO RBLT 0x%02x: %d not allocated.",data[0], inf->viid );
            err_to_stop=1;
            return;
        }
        SRY_GET_POINT(point, &data[i+2]);
        neoCopy(image_src->world, image_dest->world, inf->mask,
                inf->rect, point, inf->extcolor, inf->extmask, copyBBLT_RBLT);

    }
}

// ******************************************************************************
#pragma mark -


void neo_wrdt_apply(const uint8* data, int len)
{
	int skip_bit;
	
	if( err_to_stop ) return;
	
        {
            char  buf[1024]="NEO OP= ", buf2[256];
            int i;
            for( i=0; i<len; i++){
                snprintf( buf2, 256, "%02X ", data[i]);
                strncat(buf,buf2,1024);
            }
            NEO_DEBUG((CMSG_ERROR, VERB_NORMAL,buf));
	}
        
	skip_bit = data[0] & 0x80;
	if(skip_bit && aq_filled_ratio() < 0.2)
		return;

  	switch( data[0] & 0x7F ){ //ignore skip bit
        case 0x25:
            NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"get gworld 25 len=%d",len));
            neo_new_gworld(data,len);
            break;
  	case 0x27:
  		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"load PIC 27 %s", &data[4] ));
	  	neo_load_pic(data);
		break;
        case 0x2a:
  		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"ASV 2a" ));
                neo_alphasave(data,len);
                break;
        case 0x2b:
  		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"ALD 2b" ));
                neo_alphaload(data,len);
                break;
        case 0x2c:
                break;
                
  	case 0x39:
  		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"image copy 39 %d(%d,%d)",SRY_GET_SHORT(data+1),
	  			SRY_GET_SHORT(data+5),SRY_GET_SHORT(data+6)  ));
	  	neo_trans_partial_real_regist(data,len);
  		break;
        case 0x41:
                neo_DRCT(data,len);
                break;
	case 0x51:
		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"text 51 %d",SRY_GET_SHORT(data+1)));
		neo_drawtext(data,len);
		break;
	case 0x52:
		neo_draw_box(data,len);
		break;
        case 0x55:
		neo_draw_line(data,len);
		break;
        case 0x5a:
                neo_ColorReplace(data,len);
                break;
	case 0x61:
		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"BBLT 61(%d->%d)",
	  		SRY_GET_SHORT(data+1),SRY_GET_SHORT(data+3)));
		neo_trans_partial(data, len );
		break;
        case 0x6f:
                neo_RBLT(data,len);
                break;
#if 0
  	case 0x35:
		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"image copy 35(%d,%d)",
	  			SRY_GET_SHORT(data+3),SRY_GET_SHORT(data+5)  ));
	  	sry_trans_all(data);
  		break;
	case 0x51:
		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"text 51 %d",
				SRY_GET_SHORT(data+1)));
		sry_text(data);
		break;
	case 0x53:
		sry_draw_vline(data);
		break;
	case 0x54:
		sry_draw_hline(data);
		break;
	case 0x55:
		sry_draw_line(data);
		break;
	case 0x61:
		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"image copy 61(%d->%d)",
	  		SRY_GET_SHORT(data+1),SRY_GET_SHORT(data+3)));
		sry_trans_partial(data, 0 /*no mask*/);
		break;
	case 0x62:
		NEO_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"image copy 62(%d,%d)",
				SRY_GET_SHORT(data+7),SRY_GET_SHORT(data+9),data+11 ));
		sry_trans_partial(data, 1 /*mask on*/);
		break;
		
	case 0:
		//dev_set_height(480);
		break;
	case 0x63:
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
  			"(not supported, stop sherring)", data[0]);
  		err_to_stop=1;
		break;
	case 0x20:
	case 0x22:
	case 0x72:
	case 0x7f:
#endif
	case 0x01:
        case 0x00:
	case 0x71:
	case 0x26:
            //ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
            //        "0x%02x: not supported, ignore", data[0]);
            break;
	default:
            ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
                    "0x%02x: not defined, stop sherring", data[0]);
            err_to_stop=1;
            break;
	}
}

#endif //ENABLE_SHERRY
