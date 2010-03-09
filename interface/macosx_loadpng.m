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
#include "timidity.h"
#include "common.h"
#include "controls.h"
//#import "macosx_wrdwindow.h"

#include "png.h"

#import <Cocoa/Cocoa.h>

//#define SRY_DEBUG(x)		{ctl->cmsg x;}
#define SRY_DEBUG(x)		/*nothing*/


static void read_timidity_file(png_structp png_ptr, png_bytep buf, png_size_t len)
{
	struct timidity_file *tf;
	size_t readlen;
	
	tf= (struct timidity_file *)png_ptr->io_ptr;
	
	readlen= tf_read( buf, 1, len, tf);
	if( len!=readlen ) png_error(png_ptr, "read_timidity_file: tf_read error");
	return;
}

int mac_loadpng_pre( png_structp *png_ptrp, png_infop *info_ptrp, struct timidity_file * tf)
{
	png_structp png_ptr;
	png_infop info_ptr;
	unsigned int sig_read = 0;
	png_uint_32 width, height;
	int bit_depth, color_type, interlace_type;
	
	png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, (png_voidp)NULL,
		(png_error_ptr)NULL, (png_error_ptr)NULL);
	if (png_ptr == NULL){
		return -1;
	}

	info_ptr = png_create_info_struct(png_ptr);
	if (info_ptr == NULL){
		png_destroy_read_struct(&png_ptr, (png_infopp)NULL, (png_infopp)NULL);
		return-1;
	}
	if (setjmp(png_ptr->jmpbuf)){
		//mac_ErrorExit("\pSorry, Fail to open PNG image.\r(out of memory??)");
                exit(1234);
		/* Free all of the memory associated with the png_ptr and info_ptr */
		png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
		/* If we get here, we had a problem reading the file */
		return -1;
	}

	png_set_read_fn(png_ptr, (void *)tf, read_timidity_file);

	//png_set_read_status_fn(png_ptr, NULL);
	png_set_sig_bytes(png_ptr, sig_read);
	png_read_info(png_ptr, info_ptr);
	png_get_IHDR(png_ptr, info_ptr, &width, &height, &bit_depth, &color_type,
		&interlace_type, NULL, NULL);
	
	png_set_strip_16(png_ptr);
	png_set_packing(png_ptr);
	png_read_update_info(png_ptr, info_ptr);
	
	*png_ptrp= png_ptr;
	*info_ptrp= info_ptr;
	return 0;
}

static uint8* get_pointadr(int x, int y, NSBitmapImageRep *world)
{
	int	rowBytes = [world bytesPerRow];
	uint8	*baseAdr = [world bitmapData];
	
	return &baseAdr[y*rowBytes+x];
}

int mac_loadpng(png_structp png_ptr, png_infop info_ptr, NSBitmapImageRep *world,
                RGBColor pal[256] )
{
	png_uint_32 width, height;
	int bit_depth, color_type, interlace_type;
	png_bytep *row_pointers;
	int	row, num_palette, i;
	png_color *palette;
	
        
        SRY_DEBUG((CMSG_INFO, VERB_NORMAL,"mac_loadpng"));
                        
	png_get_IHDR(png_ptr, info_ptr, &width, &height, &bit_depth, &color_type,
		&interlace_type, NULL, NULL);
        SRY_DEBUG((CMSG_INFO, VERB_NORMAL,"width=%d,height=%d",width,height));
	
	row_pointers= (png_bytep *)malloc(height*sizeof(png_bytep));
	if( row_pointers==NULL ) return -1;
	for (row = 0; row < height; row++){
		row_pointers[row] = get_pointadr(0,row, world);
	}

	png_read_image(png_ptr, row_pointers);
	free(row_pointers);
	
	png_get_PLTE(png_ptr, info_ptr, &palette, &num_palette );
	for( i=0; i<num_palette; i++ ){
		pal[i].red= palette[i].red*0x100;
		pal[i].green= palette[i].green*0x100;
		pal[i].blue= palette[i].blue*0x100;
	}
	
	return 0;
}

void mac_loadpng_post(png_structp png_ptr, png_infop info_ptr)
{
	png_read_end(png_ptr, info_ptr);
	png_destroy_read_struct(&png_ptr, &info_ptr, (png_infopp)NULL);
}

#endif //ENABLE_SHERRY