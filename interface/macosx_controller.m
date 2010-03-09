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

    macosx_controller.m
    MacOS X, Cocoa interface controller.
    by T.Nogami	<t-nogami@happy.email.ne.jp>
    */

#ifdef HAVE_CONFIG_H
#import "config.h"
#endif /* HAVE_CONFIG_H */

#import "timidity.h"
#import "common.h"
#import "instrum.h"
#import "playmidi.h"
#import "controls.h"
#import "aq.h"
#include "wrd.h"

#import "macosx_controller.h"
#import "macosx_c.h"


Macosx_controller * macosx_controller=NULL;
BOOL macosx_controller_launched=FALSE;

int mac_main(int argc, char* argv[]);


@implementation Macosx_controller

extern WRDTracer macosx_wrdt_mode;
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    wrdt=&macosx_wrdt_mode;  //dirty!!
    //wrdt_open_opts= "m";
    auto_reduce_polyphony=0;

    macosx_controller = self;
    macosx_controller_launched = TRUE;

    [cmsg turnOffKerning:self];
    [cmsg turnOffLigatures:self];
    [doc turnOffKerning:self];
    [doc turnOffLigatures:self];
    [NSThread detachNewThreadSelector:@selector(core_thread:) toTarget:self withObject:nil ];
    [list setDoubleAction:@selector(listDoubleClick)];
    //[[NSGraphicsContext graphicsContextWithWindow:window] setShouldAntialias:NO];
    

   { // for dropping files
     NSArray *pbTypes = [ NSArray arrayWithObjects :
                             NSFilenamesPboardType, nil ];
     [ window registerForDraggedTypes : pbTypes ];
   }
}

/***********************************************************************/

- (IBAction)backward:(id)sender
{
    //[self message:"backward\n"];
    mac_send_rc(RC_BACK, 0);
}

- (IBAction)foreward:(id)sender
{
    //[self message:"foreward\n"];
    mac_send_rc(RC_NEXT, 0);
}

- (IBAction)open:(id)sender
{
    int result;
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    int  prev_number_of_files = number_of_files;

    //[self message:"open\n"];
    [oPanel setAllowsMultipleSelection:YES];
    [oPanel setCanChooseDirectories:YES];
    result = [oPanel runModalForDirectory:nil file:nil types:nil];
    if (result == NSOKButton) {
        NSArray *filesToOpen = [oPanel filenames];
        int i, count = [filesToOpen count];
        for (i=0; i<count; i++) {
            NSString *aFile = [filesToOpen objectAtIndex:i];
            ctl_load_file([aFile UTF8String]);
        }
        if( current_no==-1 && prev_number_of_files<number_of_files ){
            current_no = prev_number_of_files;
            mac_send_rc(RC_LOAD_FILE, 0);
        }
    }

    [self refresh];
}

- (IBAction)pause:(id)sender
{
    mac_send_rc(RC_TOGGLE_PAUSE, 0);
}

- (IBAction)play:(id)sender
{
    [self message:"play\n"];
    mac_send_rc(RC_CONTINUE, 0);
}

- (IBAction)stop:(id)sender
{
    [self message:"stop\n"];
    mac_send_rc(RC_QUIT, 0);
}

extern float output_volume;
- (IBAction)change_volume:(id)sender
{
    //fprintf(stderr, "%g\n", [sender floatValue]);
    output_volume = [sender floatValue];
}

- (IBAction)logClear:(id)sender
{
    [cmsg  setString:@""]; //clear
}

/***********************************************************************/

- (void)listDoubleClick
{
    //fprintf(stderr, "double click: %d\n", [list selectedRow]);
    ctl_play_nth([list selectedRow]);
    [list reloadData];
}

- (void)message:(const char*)buf
{
    NSString *str = [NSString stringWithCString:buf];
    
    [cmsg replaceCharactersInRange:NSMakeRange([[cmsg string] length], 0)
                                   withString:str];
    [cmsg scrollRangeToVisible:NSMakeRange([[cmsg string] length], 0)];
}

- (void)refresh
{
    //[self message:"refresh\n"];
    //[list reloadData];
}

- (void)core_thread:(id)arg
{
    NSAutoreleasePool *pool =[[NSAutoreleasePool alloc] init];
    char *argv[] = {"timidity"};
    chdir([[[NSBundle mainBundle] bundlePath] UTF8String]);
    chdir("..");
    mac_main(1, argv);

    [pool release];
    exit(0);
}

extern int mac_buf_using_num;
int toltal_secs;
- (void)current_time:(int)secs voices:(int)v
{
#define CTL_STATUS_INIT -99
    static int last_voices = CTL_STATUS_INIT, last_v = CTL_STATUS_INIT;
    static int last_secs = CTL_STATUS_INIT;
    char   buf[80];

    if(secs == CTL_STATUS_INIT)
    {
	last_voices = last_v = last_secs = CTL_STATUS_INIT;
	return;
    }

    if(last_secs != secs){
	last_secs = secs;
	sprintf(buf, "%02d:%02d/%02d:%02d", secs/60, secs%60,
                toltal_secs/60, toltal_secs%60 );
	//sprintf(buf, "%02d:%02d/%02d:%02d buf %d%%", secs/60, secs%60,
        //        toltal_secs/60, toltal_secs%60, (int)(aq_filled_ratio()*100) );
        [time_indicator setStringValue:[NSString stringWithCString:buf]];
        [slider setDoubleValue:(double)secs/toltal_secs];

        if(last_v != v){
            last_v = v;
            sprintf(buf, "%d/%d", v, voices);
            [i_voices setStringValue:[NSString stringWithCString:buf]];
        }    
    }
    
}

- (void)total_time:(int)secs
{
    toltal_secs=secs;
}

- (void)setMidiTitle:(const char*)str
{
    [title setStringValue:[NSString stringWithCString:str]];
    //[title setStringValue:[NSString stringWithCString:"hoge"]];
}

/***********************************************************************/

static int TEReadFile(char* filename, IBOutlet id text)
{	//return value: no err ->0
        //                 err ->1
    struct timidity_file	*tf;
    char	buf[256];
    int		len;

    [text  setString:@""]; //clear

            //read
    if( (tf=open_file(filename, 0, OF_SILENT))==0 ){
        [text setString:@"No document."];
        return 1;
    }
    
    while( tf_gets(buf, 256, tf) ){
        len=strlen(buf);
        if( len>=2 && buf[len-2]=='\r' && buf[len-1]=='\n' ){
                len--; //cut dos extrra 
        }
        if( len>=1 && buf[len-1]=='\n' ){
                buf[len-1]='\r';
        }
        [text replaceCharactersInRange:NSMakeRange([[text string] length], 0)
                                withString:[NSString stringWithCString:buf]];
        //fprintf(stderr, buf);
    }
    close_file(tf);

    return 0;
}

- (void)setDocFile:(const char*)midiname
{
    char	*p, docname[256];
    
    strcpy(docname, midiname);
    if((p = strrchr(docname, '.')) == NULL){
        return;
    }
    if('A' <= p[1] && p[1] <= 'Z'){
        strcpy(p + 1, "DOC");
    }else{
        strcpy(p + 1, "doc");
    }

    if( TEReadFile( docname, doc )==0 ){
        return;
    }else{
        ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "fail to open : %s",
                    docname);
    }
        
    // try *.txt
    if('A' <= p[1] && p[1] <= 'Z'){
        strcpy(p + 1, "TXT");
    }else{
        strcpy(p + 1, "txt");
    }

    if( TEReadFile( docname, doc )==0 ){
        return;
    }else{
        ctl->cmsg(CMSG_INFO, VERB_VERBOSE, "fail to open : %s",
                    docname);
        
    }
}

/***********************************************************************/
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    printf("open file\n");
    NSLog(filename);
    ctl_load_file([filename UTF8String]);
    return YES;
}

/***********************************************************************/
// drag & drop

- (unsigned int)draggingEntered:(id <NSDraggingInfo>)sender
{
    //printf("draggingEntered\n");
    return NSDragOperationCopy;
}
 
- (BOOL) performDragOperation : (id<NSDraggingInfo>) sender
{
    NSPasteboard *pb = [ sender draggingPasteboard ];
    NSArray *ar = [ pb propertyListForType : NSFilenamesPboardType ];
    NSString *path;
    unsigned int i;
    
    for( i=0; i<[ ar count ]; i++ ){
        path = [ ar objectAtIndex : i ]; // 配列の先頭を取り出す
        //printf("%s\n", [path UTF8String] );
        ctl_load_file([path UTF8String]);
    }
    
    //printf("performDragOperation\n");
    
    return( YES );                    // ドロップOK!
 }


- (void) windowWillClose   : (NSNotification *) aNote
{
    //fprintf(stderr,"close window.\n");
    exit(0);
}

@end
