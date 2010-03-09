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

    macosx_controller.h
    MacOS X, Cocoa interface controller.
    by T.Nogami	<t-nogami@happy.email.ne.jp>
    */

#import <Cocoa/Cocoa.h>

@interface Macosx_controller : NSObject
{
    IBOutlet id cmsg;
    IBOutlet id doc;
    IBOutlet id list;
    IBOutlet id time_indicator;
    IBOutlet id i_voices;    
    IBOutlet id slider;
    IBOutlet id volume;
    IBOutlet id window;
    IBOutlet id title;
}
- (IBAction)backward:(id)sender;
- (IBAction)foreward:(id)sender;
- (IBAction)open:(id)sender;
- (IBAction)pause:(id)sender;
- (IBAction)play:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)change_volume:(id)sender;
- (IBAction)logClear:(id)sender;

- (void)message:(const char*)buf;
- (void)refresh;
- (void)core_thread:(id)arg;
- (void)current_time:(int)sec voices:(int)v;
- (void)total_time:(int)secs;
- (void)setMidiTitle:(const char*)str;
- (void)setDocFile:(const char*)fname;

@end

