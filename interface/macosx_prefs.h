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

    by T.Nogami	<t-nogami@happy.email.ne.jp>
    */

#import <Cocoa/Cocoa.h>

@interface Prefs_controller : NSObject
{
    IBOutlet id i_stereo;
    IBOutlet id i_rate;
    IBOutlet id i_voices;

    IBOutlet id i_ModulationWheel;
    IBOutlet id i_Portamento;
    IBOutlet id i_NRPNVibrato;
    IBOutlet id i_ChannelPressure;
    IBOutlet id i_OverlappedVoice;
    IBOutlet id i_TraceTextMetaEvent;
}

- (IBAction)showPanel:(id)sender;

- (IBAction)a_cancel:(id)sender;
- (IBAction)a_ok:(id)sender;
- (IBAction)a_default:(id)sender;
@end
/***********************************************************************/

typedef struct Pref_data{
    int voices;
    int stereo;
    
    int ModulationWheel;
    int Portamento;
    int NRPNVibrato;
    int ChannelPressure;
    int OverlappedVoice;
    int TraceTextMetaEvent;
    
}Pref_data;

void setPreference(Pref_data* data);
void loadPreference(void);

extern Pref_data pref_data;
extern int mark_apply_setting;
/***********************************************************************/
