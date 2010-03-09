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

    macosx_c.m
    MacOS X control mode.
    by T.Nogami	<t-nogami@happy.email.ne.jp>
    */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif /* HAVE_CONFIG_H */
#include <stdio.h>

#include <stdarg.h>
#include <ctype.h>
#ifndef NO_STRING_H
#include <string.h>
#else
#include <strings.h>
#endif
#include <math.h>

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif /* HAVE_UNISTD_H */
#include <pthread.h>
#include <sys/stat.h>

#include "timidity.h"
#include "common.h"
#include "instrum.h"
#include "playmidi.h"
#include "readmidi.h"
#include "output.h"
#include "controls.h"
#include "miditrace.h"
#include "timer.h"
#include "bitset.h"
#include "arc.h"
#include "aq.h"
#include "wrd.h"


#import "macosx_c.h"
#import "macosx_controller.h"
#include "macosx_prefs.h"

/***********************************************************************/
#define DISPLAY_MID_MODE
#define COMMAND_BUFFER_SIZE 4096
#define MINI_BUFF_MORE_C '$'
#define LYRIC_OUT_THRESHOLD 10.0
#define CHECK_NOTE_SLEEP_TIME 5.0
#define NCURS_MIN_LINES 8

#define CTL_STATUS_UPDATE -98
#define CTL_STATUS_INIT -99

#ifndef MIDI_TITLE
#undef DISPLAY_MID_MODE
#endif /* MIDI_TITLE */


#define MAX_U_PREFIX 256

/* GS LCD */
#define GS_LCD_MARK_ON		-1
#define GS_LCD_MARK_OFF		-2
#define GS_LCD_MARK_CLEAR	-3
#define GS_LCD_MARK_CHAR '$'
#define GS_LCD_CLEAR_TIME 10.0
#define GS_LCD_WIDTH 40
/***********************************************************************/
static struct
{
    int bank, bank_lsb, bank_msb, prog, vol, exp, pan, sus, pitch, wheel;
    int is_drum;
    int bend_mark;

    double last_note_on;
    char *comm;
} ChannelStatus[MAX_CHANNELS];

enum indicator_mode_t
{
    INDICATOR_DEFAULT,
    INDICATOR_LYRIC,
    INDICATOR_CMSG
};


/***********************************************************************/
static double gslcd_last_display_time;
static int gslcd_displayed_flag = 0;
int mac_play_active=0;
/***********************************************************************/

extern int set_extension_modes(char *flag);

static int indicator_mode = INDICATOR_DEFAULT;
static int display_channels = 16;

static Bitset gs_lcd_bits[MAX_CHANNELS];
static int is_display_lcd = 1;
static int scr_modified_flag = 1; /* delay flush for trace mode */


static void update_indicator(void);
static void reset_indicator(void);
static void indicator_chan_update(int ch);
static void display_lyric(char *lyric, int sep);
static void display_play_system(int mode);
static void display_aq_ratio(void);

#define LYRIC_WORD_NOSEP	0
#define LYRIC_WORD_SEP		' '


static int ctl_open(int using_stdin, int using_stdout);
static void ctl_close(void);
static void ctl_pass_playing_list(int number_of_files, char *init_list_of_files[]);
static int ctl_read(int32 *valp);
static int cmsg(int type, int verbosity_level, char *fmt, ...);
static void ctl_event(CtlEvent *e);

static void ctl_refresh(void);
static void ctl_help_mode(void);
static void ctl_list_mode(int type);
static void ctl_total_time(int tt);
static void ctl_master_volume(int mv);
static void ctl_file_name(char *name);
static void ctl_current_time(int ct, int nv);
static const char note_name_char[12] =
{
    'c', 'C', 'd', 'D', 'e', 'f', 'F', 'g', 'G', 'a', 'A', 'b'
};

static void ctl_note(int status, int ch, int note, int vel);
static void ctl_drumpart(int ch, int is_drum);
static void ctl_program(int ch, int prog, char *vp, unsigned int banks);
static void ctl_volume(int channel, int val);
static void ctl_expression(int channel, int val);
static void ctl_panning(int channel, int val);
static void ctl_sustain(int channel, int val);
static void update_bend_mark(int ch);
static void ctl_pitch_bend(int channel, int val);
static void ctl_mod_wheel(int channel, int wheel);
static void ctl_lyric(int lyricid);
static void ctl_gslcd(int id);
static void ctl_reset(void);

/**********************************************/

/* define (LINE,ROW) */
#ifdef MIDI_TITLE
#define VERSION_LINE 0
#define HELP_LINE 1
#define FILE_LINE 2
#define FILE_TITLE_LINE 3
#define TIME_LINE 4
#define VOICE_LINE 4
#define SEPARATE1_LINE 5
#define TITLE_LINE 6
#define NOTE_LINE 7
#else
#define VERSION_LINE 0
#define HELP_LINE 1
#define FILE_LINE 2
#define TIME_LINE  3
#define VOICE_LINE 3
#define SEPARATE1_LINE 4
#define TITLE_LINE 5
#define SEPARATE2_LINE 6
#define NOTE_LINE 7
#endif

#define DEBUG_MACOSX_C(x)	 ctl.cmsg x;
//#define DEBUG_MACOSX_C(x)	 /*nothing*/
/***********************************************************************/
/* export the interface functions */

#define ctl macosx_control_mode

ControlMode ctl=
{
    "macosx GUI interface", 'm',
    1,1,0,
    0,
    ctl_open,
    ctl_close,
    ctl_pass_playing_list,
    ctl_read,
    cmsg,
    ctl_event
};


/***********************************************************************/
/* foreground/background checks disabled since switching to curses */
/* static int in_foreground=1; */

enum ctl_ncurs_mode_t
{
    /* Major modes */
    NCURS_MODE_NONE,	/* None */
    NCURS_MODE_MAIN,	/* Normal mode */
    NCURS_MODE_TRACE,	/* Trace mode */
    NCURS_MODE_HELP,	/* Help mode */
    NCURS_MODE_LIST,	/* MIDI list mode */
    NCURS_MODE_DIR,	/* Directory list mode */

    /* Minor modes */
    /* Command input mode */
    NCURS_MODE_CMD_J,	/* Jump */
    NCURS_MODE_CMD_L,	/* Load file */
    NCURS_MODE_CMD_E,	/* Extensional mode */
    NCURS_MODE_CMD_FSEARCH,	/* forward search MIDI file */
    NCURS_MODE_CMD_D,	/* Change drum channel */
    NCURS_MODE_CMD_S,	/* Save as */
    NCURS_MODE_CMD_R	/* Change sample rate */
};
static int ctl_ncurs_mode = NCURS_MODE_MAIN; /* current mode */
static int ctl_ncurs_back = NCURS_MODE_MAIN; /* prev mode to back from help */
static int ctl_cmdmode = 0;
static char ctl_mode_L_lastenter[COMMAND_BUFFER_SIZE];

struct double_list_string
{
    char *string;
    struct double_list_string *next, *prev;
};

static void init_chan_status(void);

static int selected_channel = -1;


NSLock *filelist_lock,*cmdqueue_lock;
int number_of_files,current_no;
int number_of_list;
MFnode **list_of_files;

static MFnode *current_MFnode = NULL;

#define NC_LIST_MAX 512
static int ctl_listmode=1;
static int ctl_listmode_max=1;	/* > 1 */
static int ctl_listmode_play=1;	/* > 1 */
static int ctl_list_select[NC_LIST_MAX];
static int ctl_list_from[NC_LIST_MAX];
static int ctl_list_to[NC_LIST_MAX];
static void ctl_list_table_init(void);
static MFnode *make_new_MFnode_entry(char *file);
static void insert_MFnode_entrys(MFnode *mfp, int pos);


/*********************************************************************/
#define RC_QUEUE_SIZE 8
static struct
{
    int rc;
    int32 value;
} rc_queue[RC_QUEUE_SIZE];
static volatile int rc_queue_len, rc_queue_beg, rc_queue_end;

void mac_send_rc(int rc, int32 value)
{
    [cmdqueue_lock lock];

    if(rc_queue_len == RC_QUEUE_SIZE){
	/* Over flow.  Remove the oldest message */
	rc_queue_len--;
	rc_queue_beg = (rc_queue_beg + 1) % RC_QUEUE_SIZE;
    }

    rc_queue_len++;
    rc_queue[rc_queue_end].rc = rc;
    rc_queue[rc_queue_end].value = value;
    rc_queue_end = (rc_queue_end + 1) % RC_QUEUE_SIZE;
    //ReleaseSemaphore(w32g_empty_sem, 1, NULL);
    [cmdqueue_lock unlock];
}

int mac_get_rc(int32 *value, int wait_if_empty)
{
    int rc;

    while(rc_queue_len == 0){
	if(!wait_if_empty)
	    return RC_NONE;
	//WaitForSingleObject(w32g_empty_sem, INFINITE);
        usleep(10000);
	VOLATILE_TOUCH(rc_queue_len);
    } 

    [cmdqueue_lock lock];
    rc = rc_queue[rc_queue_beg].rc;
    *value = rc_queue[rc_queue_beg].value;
    rc_queue_len--;
    rc_queue_beg = (rc_queue_beg + 1) % RC_QUEUE_SIZE;
    [cmdqueue_lock unlock];

    return rc;

}
/*********************************************************************/

static void ctl_refresh(void)
{
    [macosx_controller refresh];
}


static void init_chan_status(void)
{
    int ch;

    for(ch = 0; ch < MAX_CHANNELS; ch++)
    {
	ChannelStatus[ch].bank = 0;
	ChannelStatus[ch].bank_msb = 0;
	ChannelStatus[ch].bank_lsb = 0;
	ChannelStatus[ch].prog = 0;
	ChannelStatus[ch].is_drum = ISDRUMCHANNEL(ch);
	ChannelStatus[ch].vol = 0;
	ChannelStatus[ch].exp = 0;
	ChannelStatus[ch].pan = NO_PANNING;
	ChannelStatus[ch].sus = 0;
	ChannelStatus[ch].pitch = 0x2000;
	ChannelStatus[ch].wheel = 0;
	ChannelStatus[ch].bend_mark = ' ';
	ChannelStatus[ch].last_note_on = 0.0;
	ChannelStatus[ch].comm = NULL;
    }
}

static void display_play_system(int mode)
{
}

static void ctl_list_MFnode_files(MFnode *mfp, int select_id, int play_id)
{
#if 0
    int i, mk;
#ifdef MIDI_TITLE
    char *item, *f, *title;
    int tlen, flen, mlen;
#ifdef DISPLAY_MID_MODE
    char *mname;
#endif /* DISPLAY_MID_MODE */
#endif /* MIDI_TITLE */

    N_ctl_werase(listwin);
    mk = 0;
    for(i = 0; i < LIST_TITLE_LINES && mfp; i++, mfp = mfp->next)
    {
	if(i == select_id || i == play_id)
	{
	    mk = 1;
	    wattron(listwin,A_REVERSE);
	}

	wmove(listwin, i, 0);
	wprintw(listwin,"%03d%c",
		i + ctl_list_from[ctl_listmode],
		i == play_id ? '*' : ' ');

#ifdef MIDI_TITLE

	if((f = pathsep_strrchr(mfp->file)) != NULL)
	    f++;
	else
	    f = mfp->file;
	flen = strlen(f);
	title = mfp->title;
	if(title != NULL)
	{
	    while(*title == ' ')
		title++;
	    tlen = strlen(title) + 1;
	}
	else
	    tlen = 0;

#ifdef DISPLAY_MID_MODE
	mname = mid2name(mfp->infop->mid);
	if(mname != NULL)
	    mlen = strlen(mname);
	else
	    mlen = 0;
#else
	mlen = 0;
#endif /* DISPLAY_MID_MODE */

	item = (char *)new_segment(&tmpbuffer, tlen + flen + mlen + 4);
	if(title != NULL)
	{
	    strcpy(item, title);
	    strcat(item, " ");
	}
	else
	    item[0] = '\0';
	strcat(item, "(");
	strcat(item, f);
	strcat(item, ")");

#ifdef DISPLAY_MID_MODE
	if(mlen)
	{
	    strcat(item, "/");
	    strcat(item, mname);
	}
#endif /* DISPLAY_MID_MODE */

	waddnstr(listwin, item, COLS-6);
	reuse_mblock(&tmpbuffer);
#else
	waddnstr(listwin, mfp->file, COLS-6);
#endif
	if(mk)
	{
	    mk = 0;
	    wattroff(listwin,A_REVERSE);
	}
    }
#endif
}

static void ctl_add_mfnod(MFnode *mfp)
{
    [filelist_lock lock];
    if( number_of_files==number_of_list ){ /*full*/
        list_of_files = (MFnode**)safe_realloc(list_of_files, (number_of_list+10)*sizeof(MFnode *) );
        number_of_list += 10;
    }
    
    list_of_files[number_of_files] = mfp;
    number_of_files ++;
    [filelist_lock unlock];
    
    ctl_refresh();
}

static int isDirectory(const char *path)
{
    struct stat sb;
    int ret;
    
    ret=stat(path,&sb);
    if( ret==0 ){
        if( S_ISDIR(sb.st_mode) ){
            return 1;
        } 
    }
    return 0;
}

void ctl_load_file(const char* fn)
{
    MFnode *mfp;
    int i;
    int nfiles;
    char  	*files[1];
    char       **new_files;
    int  prev_number_of_files = number_of_files;

    //fprintf(stderr, "listing: %s\n", fn);

    files[0] = (char*)safe_malloc(strlen(fn)+2);
    strcpy(files[0], fn);
    if( isDirectory(files[0]) ){ strcat(files[0],PATH_STRING); }
    nfiles  = 1;
    new_files = expand_file_archives(files, &nfiles);
    if(new_files == NULL){
        return ;
    }

    for(i = 0; i < nfiles; i++){
        if((mfp = make_new_MFnode_entry(new_files[i])) != NULL){
            //[macosx_controller message:new_files[i]];
            ctl_add_mfnod(mfp);
        }
    }
    free(files[0]);
    free(new_files[0]);
    free(new_files);

    //if( current_no==-1 /*&& prev_number_of_files<number_of_files*/ ){
        //current_no = prev_number_of_files;
        //mac_send_rc(RC_LOAD_FILE, 0);
        //mac_send_rc(RC_CONTINUE, 0);
    //}
    if( nfiles && (!mac_play_active) ){
        current_no = prev_number_of_files;
        mac_send_rc(RC_CONTINUE, 0);        
    }
}

static void redraw_all(void)
{
    //N_ctl_scrinit();
    ctl_total_time(CTL_STATUS_UPDATE);
    ctl_master_volume(CTL_STATUS_UPDATE);
    //display_key_helpmsg();
    ctl_file_name(NULL);
    //ctl_ncurs_mode_init();
}

static void ctl_event(CtlEvent *e)
{
    if(midi_trace.flush_flag)
	return;
    switch(e->type)
    {
      case CTLE_NOW_LOADING:
	ctl_file_name((char *)e->v1);
	break;
      case CTLE_LOADING_DONE:
	redraw_all();
	break;
      case CTLE_PLAY_START:
	init_chan_status();
	//ctl_ncurs_mode_init();
	ctl_total_time((int)e->v1);
	break;
      case CTLE_PLAY_END:
	break;
      case CTLE_TEMPO:
	break;
      case CTLE_METRONOME:
	//update_indicator();
	break;
      case CTLE_CURRENT_TIME:
	ctl_current_time((int)e->v1, (int)e->v2);
	//display_aq_ratio();
	break;
      case CTLE_NOTE:
	ctl_note((int)e->v1, (int)e->v2, (int)e->v3, (int)e->v4);
	break;
      case CTLE_MASTER_VOLUME:
	ctl_master_volume((int)e->v1);
	break;
      case CTLE_PROGRAM:
	ctl_program((int)e->v1, (int)e->v2, (char *)e->v3, (unsigned int)e->v4);
	break;
      case CTLE_DRUMPART:
	ctl_drumpart((int)e->v1, (int)e->v2);
	break;
      case CTLE_VOLUME:
	ctl_volume((int)e->v1, (int)e->v2);
	break;
      case CTLE_EXPRESSION:
	ctl_expression((int)e->v1, (int)e->v2);
	break;
      case CTLE_PANNING:
	ctl_panning((int)e->v1, (int)e->v2);
	break;
      case CTLE_SUSTAIN:
	ctl_sustain((int)e->v1, (int)e->v2);
	break;
      case CTLE_PITCH_BEND:
	ctl_pitch_bend((int)e->v1, (int)e->v2);
	break;
      case CTLE_MOD_WHEEL:
	ctl_mod_wheel((int)e->v1, (int)e->v2);
	break;
      case CTLE_CHORUS_EFFECT:
	break;
      case CTLE_REVERB_EFFECT:
	break;
      case CTLE_LYRIC:
	ctl_lyric((int)e->v1);
	break;
      case CTLE_GSLCD:
	if(is_display_lcd)
	    ctl_gslcd((int)e->v1);
	break;
      case CTLE_REFRESH:
	ctl_refresh();
	break;
      case CTLE_RESET:
	ctl_reset();
	break;
      case CTLE_SPEANA:
	break;
      case CTLE_PAUSE:
	ctl_current_time((int)e->v2, 0);
	//N_ctl_refresh();
	break;
    }
}

static void ctl_total_time(int tt)
{
    [macosx_controller total_time:(tt/play_mode->rate)];
#if 0
    static int last_tt = CTL_STATUS_UPDATE;
    int mins, secs;

    if(tt == CTL_STATUS_UPDATE)
	tt = last_tt;
    else
	last_tt = tt;
    secs=tt/play_mode->rate;
    mins=secs/60;
    secs-=mins*60;
#endif
}

static void ctl_master_volume(int mv)
{
}

static void ctl_file_name(char *name)
{
}

static void ctl_current_time(int secs, int v)
{
    [macosx_controller current_time:secs voices:v];
    
#if 0
    int mins;
    static int last_voices = CTL_STATUS_INIT, last_v = CTL_STATUS_INIT;
    static int last_secs = CTL_STATUS_INIT;

    if(secs == CTL_STATUS_INIT)
    {
	last_voices = last_v = last_secs = CTL_STATUS_INIT;
	return;
    }
    if(last_secs != secs)
    {
	last_secs = secs;
	mins = secs/60;
	secs -= mins*60;
	wmove(dftwin, TIME_LINE, 5);
	wattron(dftwin, A_BOLD);
	wprintw(dftwin, "%3d:%02d", mins, secs);
	wattroff(dftwin, A_BOLD);
	scr_modified_flag = 1;
    }

    if(last_v != v)
    {
	last_v = v;
	wmove(dftwin, VOICE_LINE, 47);
	wattron(dftwin, A_BOLD);
	wprintw(dftwin, "%3d", v);
	wattroff(dftwin, A_BOLD);
	scr_modified_flag = 1;
    }

    if(last_voices != voices)
    {
	last_voices = voices;
	wmove(dftwin, VOICE_LINE, 52);
	wprintw(dftwin, "%3d", voices);
	scr_modified_flag = 1;
    }
#endif
}

static void ctl_note(int status, int ch, int note, int vel)
{
}

static void ctl_drumpart(int ch, int is_drum)
{
    if(ch >= display_channels)
	return;
    ChannelStatus[ch].is_drum = is_drum;
}

static void ctl_program(int ch, int prog, char *comm, unsigned int banks)
{
}

static void ctl_volume(int ch, int vol)
{
    if(ch >= display_channels)
	return;

    if(vol != CTL_STATUS_UPDATE)
    {
	if(ChannelStatus[ch].vol == vol)
	    return;
	ChannelStatus[ch].vol = vol;
    }
    else
	vol = ChannelStatus[ch].vol;

    if(ctl_ncurs_mode != NCURS_MODE_TRACE || selected_channel == ch)
	return;

}

static void ctl_expression(int ch, int exp)
{
    if(ch >= display_channels)
	return;

    if(exp != CTL_STATUS_UPDATE)
    {
	if(ChannelStatus[ch].exp == exp)
	    return;
	ChannelStatus[ch].exp = exp;
    }
    else
	exp = ChannelStatus[ch].exp;

    if(ctl_ncurs_mode != NCURS_MODE_TRACE || selected_channel == ch)
	return;

}

static void ctl_panning(int ch, int pan)
{
    if(ch >= display_channels)
	return;

    if(pan != CTL_STATUS_UPDATE)
    {
	if(pan == NO_PANNING)
	    ;
	else if(pan < 5)
	    pan = 0;
	else if(pan > 123)
	    pan = 127;
	else if(pan > 60 && pan < 68)
	    pan = 64;
	if(ChannelStatus[ch].pan == pan)
	    return;
	ChannelStatus[ch].pan = pan;
    }
    else
	pan = ChannelStatus[ch].pan;

    if(ctl_ncurs_mode != NCURS_MODE_TRACE || selected_channel == ch)
	return;
#if 0
    wmove(dftwin, NOTE_LINE + ch, COLS - 8);
    switch(pan)
    {
      case NO_PANNING:
	waddstr(dftwin, "   ");
	break;
      case 0:
	waddstr(dftwin, " L ");
	break;
      case 64:
	waddstr(dftwin, " C ");
	break;
      case 127:
	waddstr(dftwin, " R ");
	break;
      default:
	pan -= 64;
	if(pan < 0)
	{
	    waddch(dftwin, '-');
	    pan = -pan;
	}
	else 
	    waddch(dftwin, '+');
	wprintw(dftwin, "%02d", pan);
	break;
    }
    scr_modified_flag = 1;
#endif
}

static void ctl_sustain(int ch, int sus)
{
    if(ch >= display_channels)
	return;

    if(sus != CTL_STATUS_UPDATE)
    {
	if(ChannelStatus[ch].sus == sus)
	    return;
	ChannelStatus[ch].sus = sus;
    }
    else
	sus = ChannelStatus[ch].sus;

    if(ctl_ncurs_mode != NCURS_MODE_TRACE || selected_channel == ch)
	return;
#if 0
    wmove(dftwin, NOTE_LINE + ch, COLS - 4);
    if(sus)
	waddch(dftwin, 'S');
    else
	waddch(dftwin, ' ');
    scr_modified_flag = 1;
#endif
}

static void update_bend_mark(int ch)
{
}

static void ctl_pitch_bend(int ch, int pitch)
{
}

static void ctl_mod_wheel(int ch, int wheel)
{
    int mark;

    if(ch >= display_channels)
	return;

    ChannelStatus[ch].wheel = wheel;

    if(ctl_ncurs_mode != NCURS_MODE_TRACE || selected_channel == ch)
	return;

    if(wheel)
	mark = '=';
    else
    {
	/* restore pitch bend mark */
	if(ChannelStatus[ch].pitch > 0x2000)
	    mark = '>';
	else if(ChannelStatus[ch].pitch < 0x2000)
	    mark = '<';
	else
	    mark = ' ';
    }

    if(ChannelStatus[ch].bend_mark == mark)
	return;
    ChannelStatus[ch].bend_mark = mark;
    update_bend_mark(ch);
}

static void ctl_lyric(int lyricid)
{
    char *lyric;

    lyric = event2string(lyricid);
    if(lyric != NULL)
    {
        /* EAW -- if not a true KAR lyric, ignore \r, treat \n as \r */
        if (*lyric != ME_KARAOKE_LYRIC) {
            while (strchr(lyric, '\r')) {
            	*(strchr(lyric, '\r')) = ' ';
            }
	    if (ctl.trace_playing) {
		while (strchr(lyric, '\n')) {
		    *(strchr(lyric, '\n')) = '\r';
		}
            }
        }

	if(ctl.trace_playing)
	{
	    if(*lyric == ME_KARAOKE_LYRIC)
	    {
		if(lyric[1] == '/')
		{
		    display_lyric(" / ", LYRIC_WORD_NOSEP);
		    display_lyric(lyric + 2, LYRIC_WORD_NOSEP);
		}
		else if(lyric[1] == '\\')
		{
		    display_lyric("\r", LYRIC_WORD_NOSEP);
		    display_lyric(lyric + 2, LYRIC_WORD_NOSEP);
		}
		else if(lyric[1] == '@')
		    display_lyric(lyric + 3, LYRIC_WORD_SEP);
		else
		    display_lyric(lyric + 1, LYRIC_WORD_NOSEP);
	    }
	    else
	    {
		if(*lyric == ME_CHORUS_TEXT || *lyric == ME_INSERT_TEXT)
		    display_lyric("\r", LYRIC_WORD_SEP);
		display_lyric(lyric + 1, LYRIC_WORD_SEP);
	    }
	}
	else
	    cmsg(CMSG_INFO, VERB_NORMAL, "%s", lyric + 1);
    }
}

static void ctl_lcd_mark(int status, int x, int y)
{
}

static void ctl_gslcd(int id)
{
}

static void ctl_reset(void)
{
    //if(ctl.trace_playing)
    //        reset_indicator();
    //N_ctl_refresh();
    //ctl_ncurs_mode_init();
}

/***********************************************************************/

/*ARGSUSED*/
static int ctl_open(int using_stdin, int using_stdout)
{
    loadPreference();
    //ctl.cmsg(CMSG_INFO, VERB_NORMAL, "Welcom to TiMidity!" );
    ctl.opened = 1;
    return 0;
}

static void ctl_close(void)
{
  if (ctl.opened)
    {
      ctl.opened=0;
    }
}




static int ctl_read(int32 *valp)
{
    int32  value;
    return mac_get_rc(&value, 0);    	    
}


static int cmsg(int type, int verbosity_level, char *fmt, ...)
{
    va_list ap;
    char buff[256];

    if ((type==CMSG_TEXT || type==CMSG_INFO || type==CMSG_WARNING) &&
	ctl.verbosity<verbosity_level)
            return 0;
    
    indicator_mode = INDICATOR_CMSG;
    va_start(ap, fmt);
    vsnprintf(buff, 255, fmt, ap);
    strcat(buff, "\n");

    if(!ctl.opened){
	vfprintf(stderr, fmt, ap);
	fprintf(stderr, NLS);
            NSRunAlertPanel(
                [NSString stringWithCString:buff], @"", 
                @"OK", nil, nil);
    }
    else{
        if( /*!mac_LogWindow.ref ||*/ type==CMSG_FATAL){
            //StopAlertMessage(c2pstr(buf));  /* no Window or Fatal ERR*/
            
            NSRunAlertPanel(
                [NSString stringWithCString:buff], @"",
                @"OK", nil, nil);
        }
        [macosx_controller message:buff];
    }
    va_end(ap);
    return 0;
}


static void ctl_list_table_init(void)
{
}

static MFnode *make_new_MFnode_entry(char *file)
{
    struct midi_file_info *infop;
#ifdef MIDI_TITLE
    char *title = NULL;
#endif

    if(!strcmp(file, "-"))
	infop = get_midi_file_info("-", 1);
    else
    {
#ifdef MIDI_TITLE
	title = get_midi_title(file);
#else
	if(check_midi_file(file) < 0)
	    return NULL;
#endif /* MIDI_TITLE */
	infop = get_midi_file_info(file, 0);
    }

    if(!strcmp(file, "-") || (infop && infop->format >= 0))
    {
	MFnode *mfp;
	mfp = (MFnode *)safe_malloc(sizeof(MFnode));
	memset(mfp, 0, sizeof(MFnode));
#ifdef MIDI_TITLE
	mfp->title = title;
#endif /* MIDI_TITLE */
	mfp->file = safe_strdup(url_unexpand_home_dir(file));
	mfp->infop = infop;
	return mfp;
    }

    cmsg(CMSG_WARNING, VERB_NORMAL, "%s: Not a midi file (Ignored)",
	 url_unexpand_home_dir(file));
    return NULL;
}

static void ctl_pass_playing_list(int init_number_of_files, char *  init_list_of_files[])
{
    int i;
    int stdin_check;
    int rc;
    int32 value;
    
    
    
    stdin_check = 0;
    filelist_lock = [[NSLock alloc] init];
    cmdqueue_lock = [[NSLock alloc] init];
    
    if( filelist_lock==nil || cmdqueue_lock==nil ){
        ctl.cmsg(CMSG_FATAL, VERB_NORMAL,
		"Sorry. NSLock alloc fail.");
    }
        
    for(i=0;i<init_number_of_files;i++){
        ctl_load_file(init_list_of_files[i]);
    }

    //ctl.cmsg(CMSG_INFO, VERB_NORMAL, "Welcom to TiMidity++!" );
    current_no=-1;
    rc=RC_NONE;
    for (;;){
    	if(rc == RC_NONE){
	    rc = mac_get_rc(&value, true);    	    
    	}
    
    redo:
        switch(rc){
          case RC_NONE:
            usleep(100000);
      	    break;

       	  case RC_CONTINUE:
          case RC_LOAD_FILE: /* Play playlist.selected */
      	    DEBUG_MACOSX_C((CMSG_INFO, VERB_VERBOSE, "RC_LOAD_FILE"));
            if( current_no==-1 && number_of_files>0 ){
                current_no=0;
            }
      	    if( 0<=current_no && current_no<number_of_files ){
      	        
      	        //play
	    	//skin_state=PLAYING;
	    	//mac_pre_play();
                {
                    NSAutoreleasePool *pool =[[NSAutoreleasePool alloc] init];
                    [macosx_controller setDocFile:list_of_files[current_no]->file];
                    [macosx_controller setMidiTitle:
                        (list_of_files[current_no]->title? list_of_files[current_no]->title:"--")];
                    mac_play_active=1;
                    rc=play_midi_file( list_of_files[current_no]->file );
                    mac_play_active=0;
                    [pool release];

                }
                //mac_post_play();
      	    	
      	    	//play ended
      	    	//skin_state=(rc==RC_QUIT? STOP:WAITING);
      	    	goto redo;
      	    }else{
                DEBUG_MACOSX_C((CMSG_INFO, VERB_VERBOSE, "no file."));
            }
            break;
            
        case RC_REALLY_PREVIOUS:
            if (current_no>0){
                current_no--;
                ctl_refresh();
            }
            else
            {
                if(ctl.flags & CTLF_LIST_LOOP){
                    current_no = number_of_files-1;
                    ctl_refresh();
                }else{
                    ctl_reset();
                    break;
                }
                sleep(1);
            }
            break;
	case RC_ERROR:
	    DEBUG_MACOSX_C((CMSG_INFO, VERB_VERBOSE, "RC_ERROR"));
        case RC_TUNE_END:
        case RC_NEXT:
      	    DEBUG_MACOSX_C((CMSG_INFO, VERB_VERBOSE, "RC_NEXT"));
            if (current_no<number_of_files-1){
                current_no++;
                ctl_refresh();
                rc = RC_LOAD_FILE;
	    	goto redo;
            }else {
                current_no=-1;
                ctl_refresh();
                break;
            }
            break;

        case RC_QUIT:
      	    DEBUG_MACOSX_C((CMSG_INFO, VERB_VERBOSE, "RC_QUIT"));
            //current_no = -1;
            break;
            
	case RC_TOGGLE_PAUSE:
	    DEBUG_MACOSX_C((CMSG_INFO, VERB_VERBOSE, "RC_TOGGLE_PAUSE"));
	    //play_pause_flag = !play_pause_flag;
	    //update_PlayerWin();
	    break;
            
	case RC_RESTART:
	    DEBUG_MACOSX_C((CMSG_INFO, VERB_VERBOSE, "RC_RESTART"));
	    rc = RC_LOAD_FILE;
	    goto redo;
            
        default: /* An error or something */
      	    DEBUG_MACOSX_C((CMSG_INFO, VERB_VERBOSE, "unknown rc: %d", rc));
            break;
        }
        ctl_reset();

       	if(mark_apply_setting){
            setPreference(&pref_data);
        }

        rc = RC_NONE;
    }
}

void ctl_play_nth(int i)
{
    if( i<0 || number_of_files<=i ){
        return;
    }
    current_no = i;
    mac_send_rc(RC_LOAD_FILE,0);
}


static void indicator_chan_update(int ch)
{
    ChannelStatus[ch].last_note_on = get_current_calender_time();
    if(ChannelStatus[ch].comm == NULL)
    {
	if((ChannelStatus[ch].comm = default_instrument_name) == NULL)
	{
	    if(ChannelStatus[ch].is_drum)
		ChannelStatus[ch].comm = "<Drum>";
	    else
		ChannelStatus[ch].comm = "<GrandPiano>";
	}
    }
}

static void display_lyric(char *lyric, int sep)
{
    cmsg(CMSG_INFO, VERB_NORMAL, "%s", lyric + 1);
}



/*
 * interface_<id>_loader();
 */
ControlMode *interface_n_loader(void)
{
    return &ctl;
}
