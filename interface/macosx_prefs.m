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

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif /* HAVE_CONFIG_H */

#import "timidity.h"
#import "instrum.h"
#import "playmidi.h"
#import "readmidi.h"
#import "controls.h"

#import "macosx_c.h"
#import "macosx_prefs.h"

/***********************************************************************/
Pref_data pref_data;
int mark_apply_setting = 0;
/***********************************************************************/

@implementation Prefs_controller

static void setDefault(Pref_data* data)
{
    //data->rate = 44100;
    //data->stereo = 1;
    data->voices = DEFAULT_VOICES;
    
    data->ModulationWheel = 1;
    data->Portamento = 1;
    data->NRPNVibrato = 1;
    data->ChannelPressure = 0;
    data->OverlappedVoice = 1;
    data->TraceTextMetaEvent = 1;
}

static void getPreference_fromGlobals(Pref_data* data)
{
    //data->rate = 44100;
    //data->i_stereo = 1;
    data->voices = voices;
    
    data->ModulationWheel = opt_modulation_wheel;
    data->Portamento = opt_portamento;
    data->NRPNVibrato = opt_nrpn_vibrato;
    data->ChannelPressure = opt_channel_pressure;
    data->OverlappedVoice = opt_overlap_voice_allow;
    data->TraceTextMetaEvent = opt_trace_text_meta_event;
}

static void savePreference(Pref_data* data)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    // make dictionary
    [dict setObject:[NSNumber numberWithInt:data->voices] forKey: @"voices"];
    [dict setObject:[NSNumber numberWithInt:data->ModulationWheel] forKey: @"ModulationWheel"];
    [dict setObject:[NSNumber numberWithInt:data->Portamento] forKey: @"Portamento"];
    [dict setObject:[NSNumber numberWithInt:data->NRPNVibrato] forKey: @"NRPNVibrato"];
    [dict setObject:[NSNumber numberWithInt:data->ChannelPressure] forKey: @"ChannelPressure"];
    [dict setObject:[NSNumber numberWithInt:data->OverlappedVoice] forKey: @"OverlappedVoice"];
    [dict setObject:[NSNumber numberWithInt:data->TraceTextMetaEvent] forKey: @"TraceTextMetaEvent"];

    // write
    [defaults setObject:dict forKey:@"timidity_option_dict"];
    [defaults synchronize];
}

void restore_voices(int save_voices);  // fixme

void setPreference(Pref_data* data)
{
    voices = data->voices;
    restore_voices(1);

    opt_modulation_wheel = data->ModulationWheel;
    opt_portamento = data->Portamento;
    opt_nrpn_vibrato = data->NRPNVibrato;
    opt_channel_pressure = data->ChannelPressure;
    opt_overlap_voice_allow = data->OverlappedVoice;
    opt_trace_text_meta_event = data->TraceTextMetaEvent;
    
    savePreference(data);
    
    mark_apply_setting = 0;
}

void loadPreference()
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary   *dict;
    id              obj;
    
    // load Pref dictionary.
    dict = [defaults dictionaryForKey:@"timidity_option_dict"];
    if( ! dict ){
        return; //no pref
    }
    
    obj = [dict objectForKey:@"voices"];
    if( obj ){  voices = [obj intValue]; }
    
    obj = [dict objectForKey:@"ModulationWheel"];
    if( obj ){  opt_modulation_wheel = [obj intValue]; }
    
    obj = [dict objectForKey:@"Portamento"];
    if( obj ){  opt_portamento = [obj intValue]; }
    
    obj = [dict objectForKey:@"NRPNVibrato"];
    if( obj ){  opt_nrpn_vibrato = [obj intValue]; }
    
    obj = [dict objectForKey:@"ChannelPressure"];
    if( obj ){  opt_channel_pressure = [obj intValue]; }
    
    obj = [dict objectForKey:@"OverlappedVoice"];
    if( obj ){  opt_overlap_voice_allow = [obj intValue]; }
    
    obj = [dict objectForKey:@"TraceTextMetaEvent"];
    if( obj ){  opt_trace_text_meta_event = [obj intValue]; }
    
}

/***********************************************************************/
- (void)updateUI:(Pref_data*)data
{
    [i_voices setIntValue:data->voices];
    [i_stereo selectCellWithTag: 1 ];

    [i_ModulationWheel    setState:data->ModulationWheel ];
    [i_Portamento         setState:data->Portamento ];
    [i_NRPNVibrato        setState:data->NRPNVibrato ];
    [i_ChannelPressure    setState:data->ChannelPressure ];
    [i_OverlappedVoice    setState:data->OverlappedVoice ];
    [i_TraceTextMetaEvent setState:data->TraceTextMetaEvent ];
}

static long SetValue(int32 value, int32 min, int32 max)
{
  int32 v = value;
  if(v < min) v = min;
  else if( v > max) v = max;
  return v;
}

- (void)getPreference_fromPanel:(Pref_data*)data
{
    data->voices = SetValue([i_voices intValue],1,256);
    
    data->ModulationWheel    = [i_ModulationWheel state];
    data->Portamento         = [i_Portamento state];
    data->NRPNVibrato        = [i_NRPNVibrato state];
    data->ChannelPressure    = [i_ChannelPressure state];
    data->OverlappedVoice    = [i_OverlappedVoice state];
    data->TraceTextMetaEvent = [i_TraceTextMetaEvent state];
}

/***********************************************************************/
- (IBAction)showPanel:(id)sender
{
    if (!i_rate) {
        if (![NSBundle loadNibNamed:@"Preference" owner:self])  {
            NSLog(@"Failed to load Preference.nib");
            NSBeep();
            return;
        }
        //[[i_rate window] setExcludedFromWindowsMenu:YES];
        //[[i_rate window] setMenu:nil];
        //[[i_rate window] center];
    }/*else{
        printf("already loaded.\n");
    }*/

    getPreference_fromGlobals(&pref_data);
    [self updateUI:&pref_data];
    [[i_rate window] makeKeyAndOrderFront:nil];
}

- (IBAction)a_cancel:(id)sender
{
    mark_apply_setting = 0;
    //printf("calcel.\n");
    [[i_rate window] orderOut:sender];
}

- (IBAction)a_ok:(id)sender
{
    //printf("ok\n");
    [self getPreference_fromPanel:&pref_data];
    
    if( mac_play_active ){
        mark_apply_setting = 1;
        mac_send_rc(RC_QUIT, 0);
        mac_send_rc(RC_CONTINUE, 0);
    }else{
        setPreference(&pref_data);
    }
    [[i_rate window] orderOut:sender];
}

- (IBAction)a_default:(id)sender
{
    setDefault(&pref_data);
    [self updateUI:&pref_data];
}

@end
