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

    macosx_c.h
    MacOS X control mode.
    by T.Nogami	<t-nogami@happy.email.ne.jp>
    */

#import <Cocoa/Cocoa.h>
#import "timidity.h"
#import "macosx_controller.h"

#define MIDI_TITLE


/* list_mode */
typedef struct _MFnode
{
    char *file;
#ifdef MIDI_TITLE
    char *title;
#endif /* MIDI_TITLE */
    struct midi_file_info *infop;
} MFnode;


void mac_send_rc(int rc, int32 value);
int  mac_get_rc(int32 *value, int wait_if_empty);
void ctl_load_file(const char* fn);
void ctl_play_nth(int i);

extern Macosx_controller * macosx_controller;
extern BOOL macosx_controller_launched;

extern NSLock *filelist_lock, *cmdqueue_lock;
extern int number_of_files,current_no;
extern int number_of_list;
extern MFnode **list_of_files;
extern int mac_play_active;
