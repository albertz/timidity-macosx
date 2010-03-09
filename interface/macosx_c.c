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

    nncurs_c.c: written by Masanao Izumo <mo@goice.co.jp>
                      and Aoki Daisuke <dai@y7.net>.
    This version is merged with title list mode from Aoki Daisuke.
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

#import "tim_controller.h"

#define MIDI_TITLE
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
static double gslcd_last_display_time;
static int gslcd_displayed_flag = 0;
#define GS_LCD_CLEAR_TIME 10.0
#define GS_LCD_WIDTH 40

extern int set_extension_modes(char *flag);

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

static int indicator_width = 78;
static char *comment_indicator_buffer = NULL;
static char *current_indicator_message = NULL;
static char *indicator_msgptr = NULL;
static int current_indicator_chan = 0;
static double indicator_last_update;
static int indicator_mode = INDICATOR_DEFAULT;
static int display_velocity_flag = 0;
static int display_channels = 16;

static Bitset channel_program_flags[MAX_CHANNELS];
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
static void ctl_pass_playing_list(int number_of_files, char *list_of_files[]);
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

#define LIST_TITLE_LINES (LINES - TITLE_LINE - 1)

/**********************************************/
/* export the interface functions */

#define ctl macosx_control_mode

ControlMode ctl=
{
    "macosx GUI interface", 'm',
    1,0,0,
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
static int ctl_mode_L_dispstart = 0;
static char ctl_mode_L_lastenter[COMMAND_BUFFER_SIZE];
static char ctl_mode_SEARCH_lastenter[COMMAND_BUFFER_SIZE];

struct double_list_string
{
    char *string;
    struct double_list_string *next, *prev;
};
static struct double_list_string *ctl_mode_L_histh = NULL; /* head */
static struct double_list_string *ctl_mode_L_histc = NULL; /* current */

static void ctl_ncurs_mode_init(void);
static void init_trace_window_chan(int ch);
static void init_chan_status(void);
static void ctl_cmd_J_move(int diff);
static int ctl_cmd_J_enter(void);
static void ctl_cmd_L_dir(int move);
static int ctl_cmd_L_enter(void);

static int selected_channel = -1;

/* list_mode */
typedef struct _MFnode
{
    char *file;
#ifdef MIDI_TITLE
    char *title;
#endif /* MIDI_TITLE */
    struct midi_file_info *infop;
    struct _MFnode *next;
} MFnode;

static struct _file_list {
  int number;
  MFnode *MFnode_head;
  MFnode *MFnode_tail;
} file_list;

static MFnode *MFnode_nth_cdr(MFnode *p, int n);
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

#define NC_LIST_NEW 1
#define NC_LIST_NOW 2
#define NC_LIST_PLAY 3
#define NC_LIST_SELECT 4
#define NC_LIST_NEXT 5
#define NC_LIST_PREV 6
#define NC_LIST_UP 7
#define NC_LIST_DOWN 8
#define NC_LIST_UPPAGE 9
#define NC_LIST_DOWNPAGE 10

/* playing files */
static int nc_playfile=0;


static void N_ctl_scrinit(void)
{
}

static void ctl_refresh(void)
{
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



static void ctl_help_mode(void)
{
}

static MFnode *MFnode_nth_cdr(MFnode *p, int n)
{
    while(p != NULL && n-- > 0)
	p = p->next;
    return p;
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
    static int last_tt = CTL_STATUS_UPDATE;
    int mins, secs;

    if(tt == CTL_STATUS_UPDATE)
	tt = last_tt;
    else
	last_tt = tt;
    secs=tt/play_mode->rate;
    mins=secs/60;
    secs-=mins*60;

}

static void ctl_master_volume(int mv)
{
}

static void ctl_file_name(char *name)
{
}

static void ctl_current_time(int secs, int v)
{
    int mins;
    static int last_voices = CTL_STATUS_INIT, last_v = CTL_STATUS_INIT;
    static int last_secs = CTL_STATUS_INIT;

    if(secs == CTL_STATUS_INIT)
    {
	last_voices = last_v = last_secs = CTL_STATUS_INIT;
	return;
    }
#if 0
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

/* #define CURSED_REDIR_HACK */
/*static pthread_t cocoa_thread;
static void launch_cocoa()
{
    char * argv[]={"timidity"};
    fprintf(stderr,"launch_cocoa\n");
    NSApplicationMain(1, argv);
    fprintf(stderr,"launch_cocoa end\n");    
}*/

/*ARGSUSED*/
static int ctl_open(int using_stdin, int using_stdout)
{
    fprintf(stderr,"ctl_open\n");
    //pthread_create(&cocoa_thread, NULL, (void*)launch_cocoa, NULL);
    [tim_controller.cmsg insertText:@"hogehoge2"]
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

  return RC_NONE;
}


static int cmsg(int type, int verbosity_level, char *fmt, ...)
{
    va_list ap;

    if ((type==CMSG_TEXT || type==CMSG_INFO || type==CMSG_WARNING) &&
	ctl.verbosity<verbosity_level)
	return 0;
    indicator_mode = INDICATOR_CMSG;
    va_start(ap, fmt);
    if(!ctl.opened)
    {
	vfprintf(stderr, fmt, ap);
	fprintf(stderr, NLS);
    }
    else
    {
	if(ctl.trace_playing)
	{
	    char *buff;
	    int i;
	    MBlockList pool;

	    init_mblock(&pool);
	    buff = (char *)new_segment(&pool, MIN_MBLOCK_SIZE);
	    vsnprintf(buff, MIN_MBLOCK_SIZE, fmt, ap);
	    //N_ctl_clrtoeol(HELP_LINE);

	    switch(type)
	    {
		/* Pretty pointless to only have one line for messages, but... */
	      case CMSG_WARNING:
	      case CMSG_ERROR:
	      case CMSG_FATAL:
		//wattron(dftwin, A_REVERSE);
		//waddstr(dftwin, buff);
		//wattroff(dftwin, A_REVERSE);
		//N_ctl_refresh();
		if(type != CMSG_WARNING)
		    sleep(2);
		break;
	      default:
		//waddstr(dftwin, buff);
		//N_ctl_refresh();
		break;
	    }
	    reuse_mblock(&pool);
	}
    }
    va_end(ap);
    return 0;
}

static void insert_MFnode_entrys(MFnode *mfp, int pos)
{
    MFnode *q; /* tail pointer of mfp */
    int len;

    q = mfp;
    len = 1;
    while(q->next)
    {
	q = q->next;
	len++;
    }

    if(pos < 0) /* head */
    {
	q->next = file_list.MFnode_head;
	file_list.MFnode_head = mfp;
    }
    else
    {
	MFnode *p;
	p = MFnode_nth_cdr(file_list.MFnode_head, pos);

	if(p == NULL)
	    file_list.MFnode_tail = file_list.MFnode_tail->next = mfp;
	else
	{
	    q->next = p->next;
	    p->next = mfp;
	}
    }
    file_list.number += len;
    ctl_list_table_init();
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

static void shuffle_list(void)
{
    MFnode **nodeList;
    int i, j, n;

    n = file_list.number + 1;
    /* Move MFnode into nodeList */
    nodeList = (MFnode **)new_segment(&tmpbuffer, n * sizeof(MFnode));
    for(i = 0; i < n; i++)
    {
	nodeList[i] = file_list.MFnode_head;
	file_list.MFnode_head = file_list.MFnode_head->next;
    }

    /* Simple validate check */
    if(file_list.MFnode_head != NULL)
	ctl.cmsg(CMSG_ERROR, VERB_NORMAL, "BUG: MFnode_head is corrupted");

    /* Construct randamized chain */
    file_list.MFnode_head = file_list.MFnode_tail = NULL;
    for(i = 0; i < n; i++)
    {
	MFnode *tmp;

	j = int_rand(n - i);
	if(file_list.MFnode_head == NULL)
	    file_list.MFnode_head = file_list.MFnode_tail = nodeList[j];
	else
	    file_list.MFnode_tail = file_list.MFnode_tail->next = nodeList[j];

	/* nodeList[j] is used.  Swap out it */
	tmp = nodeList[j];
	nodeList[j] = nodeList[n - i - 1];
	nodeList[n - i - 1] = tmp;
    }
    file_list.MFnode_tail->next = NULL;
    reuse_mblock(&tmpbuffer);
}

static void ctl_pass_playing_list(int number_of_files, char *list_of_files[])
{
    int i;
    int act_number_of_files;
    int stdin_check;

    //listwin=newwin(LIST_TITLE_LINES,COLS,TITLE_LINE,0);
    stdin_check = 0;
    act_number_of_files=0;
    for(i=0;i<number_of_files;i++){
	MFnode *mfp;
	if(!strcmp(list_of_files[i], "-"))
	    stdin_check = 1;
	mfp = make_new_MFnode_entry(list_of_files[i]);
	if(mfp != NULL)
	{
	    if(file_list.MFnode_head == NULL)
		file_list.MFnode_head = file_list.MFnode_tail = mfp;
	    else
		file_list.MFnode_tail = file_list.MFnode_tail->next = mfp;
	    act_number_of_files++;
	}
    }

    file_list.number=act_number_of_files-1;

    if (file_list.number<0) {
      cmsg(CMSG_FATAL, VERB_NORMAL, "No MIDI file to play!");
      return;
    }

    ctl_listmode_max=1;
    ctl_list_table_init();
    i=0;
    for (;;)
	{
	  int rc;
	  current_MFnode = MFnode_nth_cdr(file_list.MFnode_head, i);
	  //display_key_helpmsg();
	  switch((rc=play_midi_file(current_MFnode->file)))
	    {
	    case RC_REALLY_PREVIOUS:
		if (i>0)
		    i--;
		else
		{
		    if(ctl.flags & CTLF_LIST_LOOP)
			i = file_list.number;
		    else
		    {
			ctl_reset();
			break;
		    }
		    sleep(1);
		}
		nc_playfile=i;
		//ctl_list_mode(NC_LIST_NEW);
		break;

	    default: /* An error or something */
	    case RC_TUNE_END:
	    case RC_NEXT:
		if (i<file_list.number)
		    i++;
		else
		{
		    if(!(ctl.flags & CTLF_LIST_LOOP) || stdin_check)
		    {
			aq_flush(0);
			return;
		    }
		    i = 0;
		    if(rc == RC_TUNE_END)
			sleep(2);
		    if(ctl.flags & CTLF_LIST_RANDOM)
			shuffle_list();
		}
		nc_playfile=i;
		//ctl_list_mode(NC_LIST_NEW);
		break;
	    case RC_LOAD_FILE:
		i=ctl_list_select[ctl_listmode];
		nc_playfile=i;
		break;

		/* else fall through */
	    case RC_QUIT:
		return;
	    }
	  ctl_reset();
	}
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
    char *p;
    int len, idlen, sepoffset;
    static int crflag = 0;

    if(lyric == NULL)
    {
	indicator_last_update = get_current_calender_time();
	crflag = 0;
	return;
    }

    if(indicator_mode != INDICATOR_LYRIC || crflag)
    {
	memset(comment_indicator_buffer, 0, indicator_width);
	//N_ctl_clrtoeol(HELP_LINE);
	//N_ctl_refresh();
	indicator_mode = INDICATOR_LYRIC;
	crflag = 0;
    }

    if(*lyric == '\0')
    {
	indicator_last_update = get_current_calender_time();
	return;
    }

    if(strchr(lyric, '\r') != NULL)
    {
	crflag = 1;
	if(lyric[0] == '\r' && lyric[1] == '\0')
	{
	    indicator_last_update = get_current_calender_time();
	    return;
	}
    }

    idlen = strlen(comment_indicator_buffer);
    len = strlen(lyric);

    if(sep)
    {
	while(idlen > 0 && comment_indicator_buffer[idlen - 1] == ' ')
	    comment_indicator_buffer[--idlen] = '\0';
	while(len > 0 && lyric[len - 1] == ' ')
	    len--;
    }

    if(len == 0)
    {
	indicator_last_update = get_current_calender_time();
	reuse_mblock(&tmpbuffer);
	return;
    }

    sepoffset = (sep != 0);

    if(len >= indicator_width - 2)
    {
	memcpy(comment_indicator_buffer, lyric, indicator_width - 1);
	comment_indicator_buffer[indicator_width - 1] = '\0';
    }
    else if(idlen == 0)
    {
	memcpy(comment_indicator_buffer, lyric, len);
	comment_indicator_buffer[len] = '\0';
    }
    else if(len + idlen + 2 < indicator_width)
    {
	if(sep)
	    comment_indicator_buffer[idlen] = sep;
	memcpy(comment_indicator_buffer + idlen + sepoffset, lyric, len);
	comment_indicator_buffer[idlen + sepoffset + len] = '\0';
    }
    else
    {
	int spaces;
	p = comment_indicator_buffer;
	spaces = indicator_width - idlen - 2;

	while(spaces < len)
	{
	    char *q;

	    /* skip one word */
	    if((q = strchr(p, ' ')) == NULL)
	    {
		p = NULL;
		break;
	    }
	    do q++; while(*q == ' ');
	    spaces += (q - p);
	    p = q;
	}

	if(p == NULL)
	{
	    //N_ctl_clrtoeol(HELP_LINE);
	    memcpy(comment_indicator_buffer, lyric, len);
	    comment_indicator_buffer[len] = '\0';
	}
	else
	{
	    int d, l, r, i, j;

	    d = (p - comment_indicator_buffer);
	    l = strlen(p);
	    r = len - (indicator_width - 2 - l - d);

	    j = d - r;
	    for(i = 0; i < j; i++)
		comment_indicator_buffer[i] = ' ';
	    for(i = 0; i < l; i++)
		comment_indicator_buffer[j + i] =
		    comment_indicator_buffer[d + i];
	    if(sep)
		comment_indicator_buffer[j + i] = sep;
	    memcpy(comment_indicator_buffer + j + i + sepoffset, lyric, len);
	    comment_indicator_buffer[j + i + sepoffset + len] = '\0';
	}
    }

    //wmove(dftwin, HELP_LINE, 0);
    //waddstr(dftwin, comment_indicator_buffer);
    //N_ctl_refresh();
    reuse_mblock(&tmpbuffer);
    indicator_last_update = get_current_calender_time();
}



/*
 * interface_<id>_loader();
 */
ControlMode *interface_n_loader(void)
{
    return &ctl;
}
