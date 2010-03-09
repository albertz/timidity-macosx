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

    mac_sherry.c

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

#include "macosx_wrdwindow.h"
#include "macosx_sherry.h"

Sry_VImage* sry_vimage_hashtbl[SRY_HASHSIZE];
Sry_Vpalette* sry_vpal_hashtbl[SRY_HASHSIZE];
#define SRY_DEBUG(x)		{if(opt_wrddebug){ctl->cmsg x;}} 
//#define SRY_DEBUG(x)		{ctl->cmsg x;}
//#define SRY_DEBUG(x)		/*nothing*/


Sry_Vpalette realPalette;

int isRealPaletteChanged, isRealScreenChanged;
Rect	updateSrcRect, updateDestRect;
int 	updateScrID;



void sry_start()
{
    ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
  		"SHERRY START.");
    isRealPaletteChanged=1;
    isRealScreenChanged=1;
}

static void sry_gworld_release(Sry_VImage* vimage)
{
	[vimage->world release];
	free(vimage);
}

static void sry_pal_release(Sry_Vpalette* vpal)
{
	free( vpal );
}

void sry_end()
{
	int	i;
	
	for( i=0; i<SRY_HASHSIZE; i++ ){
		Sry_VImage 	*vimage= sry_vimage_hashtbl[i],
				*synonym;
		while( vimage ){
			synonym= vimage->synonym;
			sry_gworld_release(vimage);
			vimage= synonym;
		}
		sry_vimage_hashtbl[i]= NULL;
	}
	for( i=0; i<SRY_HASHSIZE; i++ ){
		Sry_Vpalette 	*vpal= sry_vpal_hashtbl[i],
				*synonym;
		while( vpal ){
			synonym= vpal->synonym;
			sry_pal_release(vpal);
			vpal= synonym;
		}
		sry_vpal_hashtbl[i]= NULL;
	}
}
// ******************************************************************************
#pragma mark -

static Sry_VImage* sry_new_gworld_core(int img_id, int width, int height, uint8 trance_pallette)
{
	NSBitmapImageRep	*new_world;
	Rect		destRect;
	Sry_VImage	*vimage;
	int		hash;

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
        new_world = [new_world initWithBitmapDataPlanes:NULL
                pixelsWide:(destRect.right - destRect.left)
                pixelsHigh:(destRect.bottom - destRect.top)
                bitsPerSample:8
                samplesPerPixel:1
                hasAlpha:NO
                isPlanar:NO
                colorSpaceName:NSCalibratedWhiteColorSpace
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
	vimage->trance_pallette= trance_pallette;
	
	hash= SRY_HASH(img_id);
	vimage->synonym= sry_vimage_hashtbl[hash];
	sry_vimage_hashtbl[hash]= vimage;

		//clear
	wrdEnv.gmode_mask_gline = 0xff;
	wrdEnv.gmode_mask = 0xff;
	dev_gline(0,0, width,height,
			 trance_pallette, 2, trance_pallette, vimage->world);
	//mac_setfont(vimage->world, WRD_FONTNAME);	
	SRY_DEBUG((CMSG_INFO, VERB_NOISY,
		"SHERRY GET WORLD : id=%d(%d,%d) allocated successfully.",
		img_id, width, height));
	return vimage;
}

static void sry_new_gworld(const uint8* data, int len) /*0x25*/
{
	int	i;
	
	for( i=1; i<len; i+=7 ){
		sry_new_gworld_core(
			SRY_GET_SHORT(data+i), SRY_GET_SHORT(data+i+2),
			SRY_GET_SHORT(data+i+4), data[i+6]);
	}
	return;
}

Sry_VImage* sry_find_vimage(int img_id)
{
	int		hash= SRY_HASH(img_id);
	Sry_VImage*	vimage=sry_vimage_hashtbl[hash];
	
	while(vimage){
		if( vimage->img_id == img_id ) return vimage;
		vimage= vimage->synonym;
	}
	/*not found*/
	return NULL;
}

// ******************************************************************************
#pragma mark -

static Sry_Vpalette* sry_find_vpal(int pal_id)
{
	int		hash= SRY_HASH(pal_id);
	Sry_Vpalette*	vpal=sry_vpal_hashtbl[hash];
	
	while(vpal){
		if( vpal->pal_id == pal_id ) return vpal;
		vpal= vpal->synonym;
	}
	/*not found*/
	return NULL;
}

static Sry_Vpalette* sry_new_vpal_core(int pal_id)
{
	Sry_Vpalette	*vpal;
	int		hash;
	
	{	//check
		Sry_Vpalette	*vpal;
		if( (vpal=sry_find_vpal(pal_id))!=NULL ){
			ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  			"SHERRY GET VPAL : id=%d double allocating.", pal_id);
			memset(vpal->pal, 0x00, sizeof(RGBColor)*256);
			//err_to_stop=1;
			return vpal;
		}
	}
	
	vpal= (Sry_Vpalette*)malloc(sizeof(Sry_Vpalette));
	if( vpal==0 ){
            ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY GET VPAL : id=%d. fail.", pal_id);
            return NULL;
        }
	memset(vpal, 0x00, sizeof(Sry_Vpalette));
	
	vpal->pal_id= pal_id;
	
	hash= SRY_HASH(pal_id);
	vpal->synonym= sry_vpal_hashtbl[hash];
	sry_vpal_hashtbl[hash]= vpal;

	SRY_DEBUG((CMSG_INFO, VERB_NOISY,
	  		"SHERRY GET VPAL : id=%d allocated successfully.", pal_id));
	return vpal;
}

static void sry_new_vpal(const uint8 *data, int len) /*0x21*/
{
	int i;
	
	for( i=1; i<len; i+=2 ){
		sry_new_vpal_core(SRY_GET_SHORT(data+i));
	}
}

static void sry_pal_v2r(const uint8 *data) /*0x31*/
{
	int		img_id= SRY_GET_SHORT(data+1);
	Sry_Vpalette*	vpal= sry_find_vpal(img_id);
	int	i;
	
	if( vpal==NULL ){ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
  		"pal_v2r31 : %d not found.", img_id);return;}
	for( i=0; i<256; i++){
		dev_change_1_palette(i, vpal->pal[i]);
	}
	dev_redisp(portRect);
	SRY_DEBUG((CMSG_INFO, VERB_NOISY,
  		"pal_v2r31 : %d success.", img_id));
}

static void sry_pal_set(const uint8 *data, int len) /*0x41*/
{
	int	palid= SRY_GET_SHORT(data+1);
	Sry_Vpalette* vpal= sry_find_vpal(palid);
	int	i;
	
	if( vpal==NULL ){
            ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
  		"pal_set41 : vpal %d not found.", palid);
            err_to_stop=1; return;
        }
	
	for(i=3; i<len; i+=4)
	{
		int	no=data[i];
		vpal->pal[no].red=   data[i+1]*0x101;
		vpal->pal[no].green= data[i+2]*0x101;
		vpal->pal[no].blue=  data[i+3]*0x101;
	}
}

static void sry_pal_merge(const uint8 *data) /*0x42*/
{
	int	pal1id= SRY_GET_SHORT(data+1),
		pal2id= SRY_GET_SHORT(data+3),
		palresultid= SRY_GET_SHORT(data+5),
		pal1in=	data[7],
		pal1bit= data[8],
		pal1out= data[9],
		pal2in=	data[10],
		pal2bit= data[11],
		pal2out= data[12],
		per1= data[13],
		per2= data[14];
	Sry_Vpalette	*pal1= sry_find_vpal(pal1id),
			*pal2= sry_find_vpal(pal2id),
			*palresult= sry_find_vpal(palresultid);
	int	Pal1Mask,Pal2Mask,PalMask;
	int	i;
	
	
	if( pal1==NULL || pal2==NULL || palresult==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
			"pal_merge42 : not allocated.");
		err_to_stop=1;
		return;
	}
	Pal1Mask = 0xFF >> ( 8 - pal1bit );
	Pal1Mask <<= pal1out;
	Pal2Mask = 0xFF >> ( 8 - pal2bit );
	Pal2Mask <<= pal2out;
	PalMask  = Pal1Mask | Pal2Mask;
	
	SRY_DEBUG((CMSG_INFO, VERB_NOISY,
  		"%d+%d->%d, (%d,%d) mask%0x",
			 pal1id,pal2id,palresultid, per1,per2,PalMask));
			
	for ( i = 0; i < 256; i++){
		if( (i & PalMask) == i){
			int	j1= (i & Pal1Mask) >> pal1in,
				j2= (i & Pal2Mask) >> pal2in, p;
			p=  ( pal1->pal[j1].red*per1 + pal2->pal[j2].red*per2) / 100;
			palresult->pal[i].red= (p>0xffff? 0xffff: p);
			
			p=  ( pal1->pal[j1].green*per1 + pal2->pal[j2].green*per2) / 100;
			palresult->pal[i].green= (p>0xffff? 0xffff: p);
			
			p=  ( pal1->pal[j1].blue*per1 + pal2->pal[j2].blue*per2) / 100;
			palresult->pal[i].blue= (p>0xffff? 0xffff: p);
		}
	}
}

static void sry_pal_copy(const uint8 *data) /*0x43*/
{
	int	srcid= SRY_GET_SHORT(data+1),
		destid= SRY_GET_SHORT(data+3);
	Sry_Vpalette	*src= sry_find_vpal(srcid),
			*dest= sry_find_vpal(destid);
	if( src==NULL || dest==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
			"pal_copy43: not allocated.");
		err_to_stop=1;
		return;
	}
	memcpy(dest->pal, src->pal, sizeof(RGBColor)*256);
}

static void sry_pal_mask_copy(const uint8 *data) /*0x44*/
{
	int	srcid= SRY_GET_SHORT(data+1),
		destid= SRY_GET_SHORT(data+3);
	Sry_Vpalette	*src= sry_find_vpal(srcid),
			*dest= sry_find_vpal(destid);
	const uint8	*mask= data+5;
	int i;
	
	if( src==NULL || dest==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
			"pal_copy44: not allocated.");
		err_to_stop=1;
		return;
	}
	for( i=0; i<256; i++){
		if( mask[i/8] & (0x01<<(i%8)) ){
			dest->pal[i]= src->pal[i];
		}
	}
}

static void sry_pal_partial_copy(const uint8 *data, int len) /*0x45*/
{
	int	srcid= SRY_GET_SHORT(data+1),
		destid= SRY_GET_SHORT(data+3);
	Sry_Vpalette	*src= sry_find_vpal(srcid),
			*dest= sry_find_vpal(destid);
	int i;

	if( src==NULL || dest==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
			"pal_copy44: not allocated.");
		err_to_stop=1;
		return;
	}
	for( i=5; i<len; i+=2 ){
		dest->pal[ data[i] ]= src->pal[ data[i+1] ];
	}
}
// ***************************************************************
#pragma mark -

#define LOCK_VIMAGE(vimage) LockPixels(GetPortPixMap((vimage)->world))
#define UNLOCK_VIMAGE(vimage) UnlockPixels(GetPortPixMap((vimage)->world))

static void sry_trans_partial_real_core(int img_id, Rect src, Rect dest)
{
	Sry_VImage*	vimage= sry_find_vimage(img_id);
	
	if( vimage==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY TRANS : id=%d not allocated.", img_id);
		err_to_stop=1;
		return;
	}
	
	SRY_DEBUG((CMSG_INFO, VERB_NORMAL,
  		"SHERRY TRANS : %d(%d,%d)-(%d,%d)`", img_id,
  			src.left,src.top, dest.left,dest.top));

	MyCopyBits( vimage->world, wrdEnv.dispWorld,
				src, dest, 0, 0, 0xFF, 0,0,0);
	
	dev_redisp(dest);
	isRealScreenChanged=0;
}

static void sry_trans_partial_real_regist(int img_id, Rect src, Rect dest)
{
	if(isRealScreenChanged)
	{
		/*???*/
		sry_update();
	}
	updateSrcRect= src;
	updateDestRect= dest;
	updateScrID= img_id;
	isRealScreenChanged=1;
}

static void sry_trans_partial_real(const uint8 *data)	/*ox36*/
{
	int		img_id=SRY_GET_SHORT(data+1),
			width, height;
	Rect	src,dest;

	src.left= SRY_GET_SHORT(data+3);
	src.top= SRY_GET_SHORT(data+5),
	dest.left= SRY_GET_SHORT(data+7);
	dest.top= SRY_GET_SHORT(data+9);
	
	width= SRY_GET_SHORT(data+11);
	height= SRY_GET_SHORT(data+13);
	src.right= src.left+width;
	dest.right= dest.left+width;
	src.bottom= src.top+height;
	dest.bottom= dest.top+height;
	SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
  		"SHERRY TRANS : %d(%d,%d)-(%d,%d)-(%d,%d)", img_id,
  			src.left,src.top, dest.left,dest.top, width,height));

	sry_trans_partial_real_regist(img_id, src, dest);

}

static void sry_trans_partial(const uint8 *data, int maskingflg)	/*0x61,0x62*/
{
	int		srcid =SRY_GET_SHORT(data+1),
			destid= SRY_GET_SHORT(data+3);
	Sry_VImage	*vimage_src= sry_find_vimage(srcid),
			*vimage_dest= sry_find_vimage(destid);
	uint8		pmask= data[5];
	uint8		trans_flag= data[6];
	int		trance_pallette;
	int		maskx, masky;
	const uint8	*maskdata;
	int		sw;
	
	if( vimage_src==NULL || vimage_src==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY TRANS 0x%02x: %d->%d not allocated.",data[0], srcid, destid );
		err_to_stop=1;
		return;
	}
	
	
	if( pmask!=0xFF ){
		SRY_DEBUG((CMSG_ERROR, VERB_NORMAL, "masking: 0x%02x, trans=%d",pmask,trans_flag));
	}
	sw=0x10; //xcopy mode
	if( trans_flag ){
		sw |= 0x1;
		trance_pallette= vimage_src->trance_pallette;
	} else { trance_pallette=-1; }
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
	wrdEnv.gmode_mask = wrdEnv.gmode_mask_gline = pmask;
	SRY_DEBUG((CMSG_INFO, VERB_NOISY,
	  		"SHERRY TRANS 62: %d->%d sw%d mask0x%x.",data[0], srcid, destid, sw, pmask ));
	dev_gmove(SRY_GET_SHORT(data+7), SRY_GET_SHORT(data+9),
			SRY_GET_SHORT(data+11), SRY_GET_SHORT(data+13),
			SRY_GET_SHORT(data+15), SRY_GET_SHORT(data+17),
			vimage_src->world, vimage_dest->world,
			sw, trance_pallette, pmask, maskx, masky, maskdata);
}

static void sry_trans_all(const uint8 *data)
{
	Rect src,dest={0,0,480,640};
	
	src.left= SRY_GET_SHORT(data+3); src.right= src.left+640;
	src.top=  SRY_GET_SHORT(data+5); src.bottom= src.top+480;
	
	sry_trans_partial_real_regist(SRY_GET_SHORT(data+1),src,dest);
}

static void sry_text(const uint8 *data)	/*0x51*/
{
	int	img_id= SRY_GET_SHORT(data+1),
		x= SRY_GET_SHORT(data+7),
		y= SRY_GET_SHORT(data+9);
	uint8	pmask= data[3],
		mode= data[4],
		fore= data[5],
		back= data[6];
	const char*	text= (char*)data+11;
	int		len= strlen(text), i;
	
	Sry_VImage*	vimage= sry_find_vimage(img_id);

	if( vimage==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY TEXT51 : id=%d not allocated.", img_id);
		err_to_stop=1;
		return;
	}

	SRY_DEBUG((CMSG_INFO, VERB_NOISY,
  		"Now, try to draw : id%d %s,%d(%d,%d)mode%d,mask%d",
  			img_id, text,len,x,y, mode, pmask ));
  		
		/*if( pmask==0xFF ){
			for( i=0; i<len; ){
				int dlen;
				dlen= (IS_MULTI_BYTE(text[i])? 2:1);
				if( mode & 1 ){
					vimage->world->fgColor= fore;
					TextMode(srcOr);
					MoveTo( x+i*8,y+12);DrawText(&text[i],0, dlen );
				}
				if( mode & 2 ){
					vimage->world->fgColor= back;
					TextMode(notSrcOr);
					MoveTo( x+i*8,y+12);DrawText(&text[i],0, dlen );
				}
				i+= dlen;
			}
			MoveTo(x,y+15);Line(len*8,0); //make 16 dot height
		}else*/{
			for( i=0; i<len; ){
				int dlen;
				dlen= (IS_MULTI_BYTE(text[i])? 2:1);
				dev_draw_text_gmode(vimage->world, x+i*8, y,
					&text[i], dlen,
					pmask, mode, fore, back, 1 );
				i+= dlen;
			}
		}
}

static void sry_load_png(const uint8 *data) /*0x27*/
{
	int	img_id= SRY_GET_SHORT(data+1);
	int	palid= SRY_GET_SHORT(data+3);
	Sry_VImage*	vimage;
	Sry_Vpalette* vpal;
	char	*filename= (char*)data+5;
	char	fullpath[256], *p;
		
		
	vpal=sry_new_vpal_core(palid);
	if( vpal==NULL ){
            ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
  		"load_png : vpal %d not found.", palid);
            err_to_stop=1;return;
        }
	
	strcpy(fullpath, current_file_info->filename); //a little danger
	p= strrchr( fullpath, PATH_SEP );
	if( p==0 ) return;
	strcpy( p+1, filename );
	SRY_DEBUG((CMSG_INFO, VERB_NORMAL,
	  		"PNG27: try to load %s", fullpath));
	{
		struct timidity_file *tf;
		png_structp png_ptr;
		png_infop info_ptr;
		png_uint_32 width, height;
		int bit_depth, color_type, interlace_type, num_trans;
		png_bytep	trans;
		png_color_16p	trans_values;
		png_uint_32 retval;
		
		//tf= open_file(fullpath, 0, OF_SILENT);
		tf= wrd_open_file(filename);
		if ( tf == NULL ){
			ctl->cmsg(CMSG_ERROR, VERB_NORMAL, "%s: open fail.", filename);
 			err_to_stop=1;return;
 		}
		if( mac_loadpng_pre( &png_ptr, &info_ptr, tf) != 0 ){
			close_file(tf);
			err_to_stop=1;
			return;
		}
		
		png_get_IHDR(png_ptr, info_ptr, &width, &height, &bit_depth, &color_type,
			&interlace_type, NULL, NULL);
		retval= png_get_tRNS(png_ptr, info_ptr, &trans, &num_trans, &trans_values);

		if( (retval&PNG_INFO_tRNS) && num_trans>=1 && trans!=NULL )
				vimage= sry_new_gworld_core( img_id, width, height, trans[0]);
			else	vimage= sry_new_gworld_core( img_id, width, height, 0);
		if( vimage==NULL ){
			ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
		  		"PNG27 : id=%d not allocated.", img_id);
			err_to_stop=1;
		}
		else mac_loadpng(png_ptr, info_ptr, vimage->world, vpal->pal );
		mac_loadpng_post( png_ptr, info_ptr);
		close_file(tf);
	}
}

static void sry_draw_box(const uint8 *data) /*52*/
{
	int	img_id= SRY_GET_SHORT(data+1);
	Sry_VImage*	vimage= sry_find_vimage(img_id);
	int		pmask= data[3];
	uint8	color;
	
	if( vimage==NULL ){return;}
	
	wrdEnv.gmode_mask = wrdEnv.gmode_mask_gline = pmask;
	color= data[12];
	SRY_DEBUG((CMSG_INFO, VERB_NOISY,
		"box52 : id%d (%d,%d)-(%d,%d)", img_id,
			SRY_GET_SHORT(data+4),SRY_GET_SHORT(data+6),
			SRY_GET_SHORT(data+8),SRY_GET_SHORT(data+10)));
	dev_gline(SRY_GET_SHORT(data+4),SRY_GET_SHORT(data+6),
		SRY_GET_SHORT(data+8),SRY_GET_SHORT(data+10),
			 color, 2, color, vimage->world);
}


static void sry_draw_line_core(int img_id, int pmask,
		int x1, int y1, int x2, int y2, int color)
{
	Sry_VImage*	vimage= sry_find_vimage(img_id);
	
	if( vimage==NULL ){return;}
	
	wrdEnv.gmode_mask = wrdEnv.gmode_mask_gline = pmask;
	dev_gline(x1,y1,x2,y2,
			 color, 0/*line*/, 0xFF, vimage->world);
}

static void sry_draw_hline(const uint8 *data) /*0x54*/
{
	sry_draw_line_core(SRY_GET_SHORT(data+1), data[3],
		SRY_GET_SHORT(data+4),SRY_GET_SHORT(data+6),
		SRY_GET_SHORT(data+8),SRY_GET_SHORT(data+6),
		data[10]);
}

static void sry_draw_vline(const uint8 *data) /*0x53*/
{
	sry_draw_line_core(SRY_GET_SHORT(data+1), data[3],
		SRY_GET_SHORT(data+4),SRY_GET_SHORT(data+6),
		SRY_GET_SHORT(data+4),SRY_GET_SHORT(data+8),
		data[10]);
}

static void sry_draw_line(const uint8 *data) /*0x55*/
{
	sry_draw_line_core(SRY_GET_SHORT(data+1), data[3],
		SRY_GET_SHORT(data+4),SRY_GET_SHORT(data+6),
		SRY_GET_SHORT(data+8),SRY_GET_SHORT(data+10),
		data[12]);
}

// ******************************************************************************
#pragma mark -

static void sry_updatePalette()
{
	Rect dest={0,0,480,640};

	dev_redisp(dest);
	isRealScreenChanged = 0;
	isRealPaletteChanged = 0;
}

void sry_update()
{
	Sry_VImage*	vimage= sry_find_vimage(updateScrID);

	if(!isRealPaletteChanged && !isRealScreenChanged)
		return;

	SRY_DEBUG((CMSG_INFO, VERB_NOISY,
  		"sry_update: %d", updateScrID));

	if( vimage==NULL ){
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
	  		"SHERRY TRANS : id=%d not allocated.", updateScrID);
		err_to_stop=1;
		return;
	}

	if(isRealPaletteChanged)
		sry_updatePalette();
	if(isRealScreenChanged)
		sry_trans_partial_real_core(updateScrID, updateSrcRect, updateDestRect);

	dev_redisp(updateDestRect);
	isRealScreenChanged=0;
}

void sry_wrdt_apply( uint8* data, int len)
{
	int skip_bit;
	
	if( err_to_stop ) return;
	if( neowrd_flg ){
            neo_wrdt_apply(data,len);
            return;
        }
        
	SRY_DEBUG((CMSG_ERROR, VERB_NORMAL,
	"SHERRY OP= 0x%02x", data[0]));
	
	skip_bit = data[0] & 0x80;
	if(skip_bit && aq_filled_ratio() < 0.2)
		return;

  	switch( data[0] & 0x7F ){ //ignore skip bit
  	case 0x21:
  		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"new pal21 len=%d", len));
		sry_new_vpal(data, len);
  		break;
  	case 0x25:
		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"get gworld 25(%d,%d)len%d",
	  			SRY_GET_SHORT(data+3),SRY_GET_SHORT(data+5), len));
	  	sry_new_gworld(data,len);
  		break;
  	case 0x27:
  		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"load PNG27 %s", data+5 ));
	  	sry_load_png(data);
		break;
	case 0x31:
		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"pallete 31(%d)",SRY_GET_SHORT(data+1) ));
	  	sry_pal_v2r(data);
		break;
  	case 0x35:
		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"image copy 35(%d,%d)",
	  			SRY_GET_SHORT(data+3),SRY_GET_SHORT(data+5)  ));
	  	sry_trans_all(data);
  		break;
  	case 0x36:
  		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"image copy 36 %d(%d,%d)",SRY_GET_SHORT(data+1),
	  			SRY_GET_SHORT(data+3),SRY_GET_SHORT(data+5)  ));
	  	sry_trans_partial_real(data);
  		break;
  	case 0x41:
		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"set pal 41 %d, len%d",SRY_GET_SHORT(data+1),len));
	  	sry_pal_set(data, len);
  		break;
  	case 0x42:
		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"pal merge42"));
	  	sry_pal_merge(data);
  		break;
  	case 0x43:
  		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"pal copy43: %d->%d",SRY_GET_SHORT(data+1),SRY_GET_SHORT(data+3) ));
	  	sry_pal_copy(data);
		break;
	case 0x44:
		sry_pal_mask_copy(data);
		break;
	case 0x45:
		sry_pal_partial_copy(data,len);
		break;
	case 0x51:
		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"text 51 %d",
				SRY_GET_SHORT(data+1)));
		sry_text(data);
		break;
	case 0x52:
		sry_draw_box(data);
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
		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
	  		"image copy 61(%d->%d)",
	  		SRY_GET_SHORT(data+1),SRY_GET_SHORT(data+3)));
		sry_trans_partial(data, 0 /*no mask*/);
		break;
	case 0x62:
		SRY_DEBUG((CMSG_INFO, VERB_VERBOSE,
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
	case 1:
	case 0x20:
	case 0x22:
	case 0x26:
	case 0x71:
	case 0x72:
	case 0x7f:
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
  			"0x%02x: not supported, ignore", data[0]);
		break;
	default:
		ctl->cmsg(CMSG_ERROR, VERB_NORMAL,
  			"0x%02x: not defined, stop sherring", data[0]);
  		err_to_stop=1;
		break;
	}
}

#endif //ENABLE_SHERRY
