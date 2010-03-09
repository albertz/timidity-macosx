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

    macosx_ListData.c
    MacOS X, Data source of List.
    */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif /* HAVE_CONFIG_H */

#import "macosx_ListData.h"
#import "macosx_c.h"

@implementation ListDataSource
- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return number_of_files;
}

- (id)tableView:(NSTableView *)aTableView
 objectValueForTableColumn:(NSTableColumn *)aTableColumn
 row:(int)rowIndex
{
    NSString *column_id; 
    id        retid=0;

    [filelist_lock lock];

    //NSParameterAssert(rowIndex >= 0 && rowIndex < [records count]);
    //theRecord = [records objectAtIndex:rowIndex];
    //theValue = [theRecord objectForKey:[aTableColumn identifier]];
    //return theValue;
    //return @"hoge";
    if( rowIndex>=number_of_files ){
        retid=0;
        goto exit;
    }
    
    column_id = [aTableColumn identifier];
    if( [column_id isEqualToString:@"No"] ){
        retid=( rowIndex==current_no? @"=>":@"");
        goto exit;
    }else if(  [column_id isEqualToString:@"Title"]  ){
        retid =  [NSString stringWithCString:
            list_of_files[rowIndex]->title? list_of_files[rowIndex]->title:"--"];
        goto exit;
    }else if(  [column_id isEqualToString:@"File"]  ){
        char *filen;

        if( list_of_files[rowIndex]->file == NULL ){
            retid = [NSString stringWithCString:"--" ];
            goto exit;
        }
        filen = strrchr(list_of_files[rowIndex]->file, '#');
        if( filen==NULL ){ filen = strrchr(list_of_files[rowIndex]->file, PATH_SEP); }
        retid = [NSString stringWithCString:
             filen? (filen+1):list_of_files[rowIndex]->file ];
        goto exit;
    }else if( [column_id isEqualToString:@"full_path"] ){
        retid = [NSString stringWithUTF8String:
            list_of_files[rowIndex]->file? list_of_files[rowIndex]->file:"--" ];
        goto exit;
    }

exit:
    [filelist_lock unlock];

    return  retid;
}

@end
