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

    macosx_mag.m
    MAG image driver for MacOS X
    by T.Nogami	<t-nogami@happy.email.ne.jp>
*/

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif /* HAVE_CONFIG_H */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "timidity.h"
#include "common.h"
#include "wrd.h"

#import "macosx_mag.h"
#import "macosx_wrdwindow.h"



static void read_flagA_setup(MagImage * magimg, struct timidity_file *tf )
{
    int	 readbytes;
    
    readbytes=magimg->header.offset_flagB - magimg->header.offset_flagA;
    magimg->work.flagA_work=(uint8*)safe_malloc( readbytes );
    tf_seek(tf, magimg->work.header_pos + magimg->header.offset_flagA, SEEK_SET);
    tf_read(magimg->work.flagA_work, 1, readbytes, tf);
    magimg->work.flagA_pos=0;
}

static void read_flagB_setup(MagImage *magimg, struct timidity_file *tf )
{	
    magimg->work.flagB_work=(uint8*)safe_malloc( magimg->header.size_flagB );
    tf_seek(tf, magimg->work.header_pos + magimg->header.offset_flagB, SEEK_SET);
    tf_read(magimg->work.flagB_work, 1, magimg->header.size_flagB, tf);
    magimg->work.flagB_pos=0;
}

static void read_flag_1line(MagImage * magimg )
{
    int		x, flagA,flagB;
    
    for( x=0; x<magimg->width;  ){
        flagA= magimg->work.flagA_work[magimg->work.flagA_pos/8]
                & (0x80 >> (magimg->work.flagA_pos & 0x07) );
        magimg->work.flagA_pos++;
        if( flagA ){
                flagB= magimg->work.flagB_work[magimg->work.flagB_pos++];
        }else{
                flagB= 0;
        }
        magimg->work.flag[x] ^= flagB>>4;	 x+=4;
        magimg->work.flag[x] ^= flagB & 0x0F; x+=4;
    }
}

static void load_pixel(MagImage * magimg, struct timidity_file *tf )
{
    int 		fpos,x,y,i, dx,dy;
    uint16		pixels;
    const int	DX[]={0,-4,-8,-16,  0,-4,  0,-4,-8,  0,-4,-8,  0,-4,-8, 0},
                DY[]={0, 0, 0,  0, -1,-1, -2,-2,-2, -4,-4,-4, -8,-8,-8, -16};
#define OUT_OF_DISP (x>=640 || y>=400)

    read_flagA_setup(magimg, tf );
    read_flagB_setup(magimg, tf );
    fpos= magimg->work.header_pos + magimg->header.offset_pixel;
    tf_seek(tf, fpos, SEEK_SET);
    for( y=0; y<magimg->hight; y++ ){
        read_flag_1line( magimg );
        for( x=0; x<magimg->width; x+=4 ){
            if( magimg->work.flag[x]==0 ){
                tf_read(&pixels, 1, 2, tf);
                if( OUT_OF_DISP ) continue;
                for( i=3; i>=0; i-- ){
                        *(uint8*)(&magimg->data[y*magimg->rowBytes+x+i])= (pixels & 0x000F);
                        pixels >>= 4;
                }
            } else {
                if( OUT_OF_DISP ) continue;
                dx=DX[magimg->work.flag[x]];
                dy=DY[magimg->work.flag[x]];
                //*(uint32*)(&magimg->data[y*magimg->rowBytes+x]) =  //copy 4bytes, danger?
                //		 *(uint32*)(&magimg->data[(y+dy)*magimg->rowBytes+ x+dx]);
                magimg->data[y*magimg->rowBytes+x  ]=
                                        magimg->data[(y+dy)*magimg->rowBytes+ x+dx  ];
                magimg->data[y*magimg->rowBytes+x+1]=
                                        magimg->data[(y+dy)*magimg->rowBytes+ x+dx+1];
                magimg->data[y*magimg->rowBytes+x+2]= 
                                        magimg->data[(y+dy)*magimg->rowBytes+ x+dx+2];
                magimg->data[y*magimg->rowBytes+x+3]= 
                                        magimg->data[(y+dy)*magimg->rowBytes+ x+dx+3];
            }
        }
    }
}

MagImage* macosx_mag_load( char* fn)
{
            // no err -> return pointer of MagImage; else return NULL;
    uint8		buf[80];
    int		ret,i;
    struct timidity_file	*tf=NULL;
    MagImage	*magimg=NULL;

    
    if( (tf=wrd_open_file(fn))==0 ){ //fail
        goto mac_mag_load_fail;
    }
    
    magimg = (MagImage*)safe_malloc(sizeof(MagImage));
    memset( magimg, 0x00, sizeof(MagImage) );  //clear memory
    
    magimg->filename = safe_strdup(fn);    
    
    // initialize table
    //mag_header.data = GetPixBaseAddr(pixmap);
    //mag_header.rowBytes= (**pixmap).rowBytes & 0x1FFF;
    
    // magic string check
    ret=tf_read(buf, 1, 8,tf);
    if( ret!=8 || memcmp(buf, "MAKI02  ",8)!=0 ){
        goto mac_mag_load_fail;
    }
    
    while( tf_getc(tf) != 0x1A ) //skip machine code,user name, comment
            /*nothing*/;
    
    magimg->work.header_pos=tf_tell(tf); //get header position
    
    // read header	
    ret=tf_read(&magimg->header, 1, 32, tf);
    if( ret!=32 ) goto mac_mag_load_fail; //unexpected end of file
    
    //transrate endian
    magimg->header.x1=LE_SHORT(magimg->header.x1);
    magimg->header.y1=LE_SHORT(magimg->header.y1);
    magimg->header.x2=LE_SHORT(magimg->header.x2);
    magimg->header.y2=LE_SHORT(magimg->header.y2);
    magimg->header.offset_flagA=LE_LONG(magimg->header.offset_flagA);
    magimg->header.offset_flagB=LE_LONG(magimg->header.offset_flagB);
    magimg->header.size_flagB=LE_LONG(magimg->header.size_flagB);
    magimg->header.offset_pixel=LE_LONG(magimg->header.offset_pixel);
    magimg->header.size_pixel=LE_LONG(magimg->header.size_pixel);
    
    magimg->header.x1 &= ~0x7;
    magimg->header.x2 |= 0x7;	    
    
    magimg->width = magimg->header.x2 - magimg->header.x1+1;
    magimg->hight = magimg->header.y2 - magimg->header.y1+1;
    magimg->rowBytes = magimg->width;
    
    magimg->data = safe_malloc( magimg->width*magimg->hight );
    
    
    if( magimg->header.screen_mode != 0 ){
        goto mac_mag_load_fail; //not support mode
    }
    
    //read pallet
    for( i=0; i<16; i++){
        ret=tf_read(buf, 1, 3, tf);
        if( ret!=3 ) goto mac_mag_load_fail; //unexpected end of file
        magimg->palette[i].red=buf[1]<<8;
        magimg->palette[i].green=buf[0]<<8;
        magimg->palette[i].blue=buf[2]<<8;
    }
    
    load_pixel(magimg, tf );
    return magimg;

mac_mag_load_fail:
    macosx_mag_free(magimg);
    if(tf){ close_file(tf); }
    return NULL;
}

void macosx_mag_free(MagImage* magimg)
{
    if( magimg==NULL ){return;} //for safty
    
    if( magimg->filename ){
        free(magimg->filename);
        magimg->filename=NULL;
    }
    if( magimg->data ){
        free(magimg->data);
        magimg->data=NULL;
    }
    if( magimg->work.flagA_work ){
        free(magimg->work.flagA_work);
        magimg->work.flagA_work=NULL;
    }
    if( magimg->work.flagB_work ){
        free(magimg->work.flagB_work);
        magimg->work.flagB_work=NULL;
    }
    free(magimg);
}

// **********************************************************************
#pragma mark -
int mac_pho_load( char* fn, NSBitmapImageRep *pm)
{
    uint8	buf[80];
    int		ret,i,j,x,y,rowBytes;
    struct timidity_file	*tf;
    uint8*	data;


    dev_box(pm, portRect, 0, 0xFF);
    
    if( (tf=wrd_open_file(fn))==0 )
            return 1;
    rowBytes= [pm bytesPerRow];
    data = [pm bitmapData];

    for( j=0; j<=3; j++){
        for( y=0; y<400; y++){
            for( x=0; x<640;  ){
                ret=tf_read(buf, 1, 1, tf);
                if( ret!=1 ) goto mac_pho_load_exit; //unexpected end of file
                //data[y*rowBytes+x] &= 0x1F;
                for( i=7; i>=0; i--){
                        data[y*rowBytes+x+i] |= ((buf[0] & 0x01)<<j);
                        buf[0]>>=1;
                }
                x+=8;
            }
        }
    }

mac_pho_load_exit:
    close_file(tf);
    return 0;
}
