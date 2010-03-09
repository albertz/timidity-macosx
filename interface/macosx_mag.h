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

    macosx_mag.h
    MAG image driver for MacOS X
    by T.Nogami	<t-nogami@happy.email.ne.jp>
*/

#import <Cocoa/Cocoa.h>

typedef struct {
	uint8	header;
	uint8	machine_code;
	uint8	machine_depend_flag;
	uint8	screen_mode;
	uint16	x1,y1,x2,y2;
	uint32	offset_flagA;
	uint32	offset_flagB;
	uint32	size_flagB;
	uint32	offset_pixel;
	uint32	size_pixel;

} Mag_Header;

typedef struct{
	long	header_pos;
	uint8	flag[1280]; //for safty
	uint8	*flagA_work, *flagB_work;
	int	flagA_pos, flagB_pos, pixel_pos;
}Mag_work;

typedef struct {
    char	*filename;
    Mag_Header  header;
    Mag_work	work;

    int		width, hight,rowBytes;
    RGBColor   palette[16];
    unsigned char *data;
}MagImage;

MagImage* macosx_mag_load( char* fn);
void macosx_mag_free(MagImage* magimg);

int mac_pho_load( char* fn, NSBitmapImageRep *pm);


