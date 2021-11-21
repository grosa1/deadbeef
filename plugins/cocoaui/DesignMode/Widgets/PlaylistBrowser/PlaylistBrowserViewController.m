//
//  PlaylistBrowserViewController.m
//  deadbeef
//
//  Created by Alexey Yakovenko on 21/11/2021.
//  Copyright © 2021 Alexey Yakovenko. All rights reserved.
//

#include "deadbeef.h"
#import "NSMenu+ActionItems.h"
#import "PlaylistBrowserViewController.h"
#import "PlaylistContextMenu.h"
#import "RenamePlaylistViewController.h"
#import "DeletePlaylistConfirmationController.h"

extern DB_functions_t *deadbeef;

@interface PlaylistBrowserViewController () <NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate, RenamePlaylistViewControllerDelegate, DeletePlaylistConfirmationControllerDelegate>

@property (weak) IBOutlet NSTableView *tableView;

@property (weak) IBOutlet NSTableColumn *playingColumn;
@property (weak) IBOutlet NSTableColumn *nameColumn;
@property (weak) IBOutlet NSTableColumn *itemsColumn;
@property (weak) IBOutlet NSTableColumn *durationColumn;

@property (weak) IBOutlet NSMenuItem *playingMenuItem;
@property (weak) IBOutlet NSMenuItem *itemsMenuItem;
@property (weak) IBOutlet NSMenuItem *durationMenuItem;

@property (nonatomic) BOOL isReloading;
@property (nonatomic) NSInteger clickedRow;

@end

@implementation PlaylistBrowserViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.menu = [PlaylistContextMenu new];
    self.tableView.menu.delegate = self;

    [self reloadData];
}

- (void)updateSelectedRow {
    int curr = deadbeef->plt_get_curr_idx();
    [self.tableView selectRow:curr byExtendingSelection:NO];
}

- (void)reloadData {
    self.isReloading = YES;
    [self.tableView reloadData];
    [self updateSelectedRow];
    self.isReloading = NO;
}

- (void)updateTableViewMenu {
    PlaylistContextMenu *menu = (PlaylistContextMenu *)self.tableView.menu;
    menu.parentView = self.tableView;
    menu.renamePlaylistDelegate = self;
    menu.deletePlaylistDelegate = self;
    NSPoint coord = [self.tableView.window convertPointFromScreen:NSEvent.mouseLocation];
    menu.clickPoint = [self.tableView convertPoint:coord fromView:nil];
    self.clickedRow = self.tableView.clickedRow;
    [menu updateWithPlaylistIndex:(int)self.tableView.clickedRow];
}

- (void)widgetMessage:(uint32_t)_id ctx:(uintptr_t)ctx p1:(uint32_t)p1 p2:(uint32_t)p2 {
    switch (_id) {
    case DB_EV_SONGCHANGED:
        {
            // FIXME: UI
            int highlight_curr_plt = deadbeef->conf_get_int ("cocoaui.pltbrowser.highlight_curr_plt", 0);
            // only fill when playlist changed
            if (highlight_curr_plt) {
                ddb_event_trackchange_t *ev = (ddb_event_trackchange_t *)ctx;
                if (ev->from && ev->to) {
                    ddb_playlist_t *plt_from = deadbeef->pl_get_playlist (ev->from);
                    ddb_playlist_t *plt_to = deadbeef->pl_get_playlist (ev->to);
                    if (plt_from != plt_to) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self updateSelectedRow];
                        });
                    }
                    if (plt_from) {
                        deadbeef->plt_unref (plt_from);
                    }
                    if (plt_to) {
                        deadbeef->plt_unref (plt_to);
                    }
                }
                else if (!ev->from) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self updateSelectedRow];
                    });
                }
            }
        }
        break;
    case DB_EV_PLAYLISTSWITCHED:
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateSelectedRow];
            });
        }
        break;
    case DB_EV_CONFIGCHANGED:
    case DB_EV_PAUSED:
    case DB_EV_STOP:
    case DB_EV_TRACKINFOCHANGED:
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadData];
            });
        }
        break;
    case DB_EV_PLAYLISTCHANGED:
        {
            if (p1 == DDB_PLAYLIST_CHANGE_CONTENT
                || p1 == DDB_PLAYLIST_CHANGE_TITLE) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self reloadData];
                });
            }
            else if (p1 == DDB_PLAYLIST_CHANGE_POSITION
                     || p1 == DDB_PLAYLIST_CHANGE_DELETED
                     || p1 == DDB_PLAYLIST_CHANGE_CREATED) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self reloadData];
                });
            }
        }
        break;
    }
}

#pragma mark -

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu == self.tableView.menu) {
        [self updateTableViewMenu];
    }
}

- (IBAction)playingItemAction:(NSMenuItem *)sender {
    self.playingColumn.hidden = !self.playingColumn.isHidden;
}
- (IBAction)itemsItemAction:(NSMenuItem *)sender {
    self.itemsColumn.hidden = !self.itemsColumn.isHidden;
}
- (IBAction)durationItemAction:(NSMenuItem *)sender {
    self.durationColumn.hidden = !self.durationColumn.isHidden;
}

#pragma mark - NSMenuDelegate

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem == self.playingMenuItem) {
        menuItem.state = self.playingColumn.isHidden ? NSControlStateValueOff : NSControlStateValueOn;
    }
    else if (menuItem == self.itemsMenuItem) {
        menuItem.state = self.itemsColumn.isHidden ? NSControlStateValueOff : NSControlStateValueOn;
    }
    else if (menuItem == self.durationMenuItem) {
        menuItem.state = self.durationColumn.isHidden ? NSControlStateValueOff : NSControlStateValueOn;
    }
    return YES;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *view = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];

    int plt_active = deadbeef->streamer_get_current_playlist ();
    // FIXME: UI
    // FIXME: perf (react to configchanged)
    int highlight_curr = deadbeef->conf_get_int ("cocoaui.pltbrowser.highlight_curr_plt", 0);
    ddb_playback_state_t playback_state = deadbeef->get_output ()->state ();
    ddb_playlist_t *plt = deadbeef->plt_get_for_idx ((int)row);
    if (plt == NULL) {
        return nil;
    }

    if ([tableColumn.identifier isEqualToString:@"Playing"]) {
        if (row == plt_active) {
            switch (playback_state) {
            case DDB_PLAYBACK_STATE_PLAYING:
                view.imageView.image = [NSImage imageNamed:@"btnplayTemplate.pdf"];
                break;
            case DDB_PLAYBACK_STATE_PAUSED:
                view.imageView.image = [NSImage imageNamed:@"btnpauseTemplate.pdf"];
                break;
            default:
                view.imageView.image = nil;
                break;
            }
        }
        else {
            view.imageView.image = nil;
        }
        view.textField.stringValue = @"";
    }
    else if ([tableColumn.identifier isEqualToString:@"Name"]) {
        char title[1000];
        char title_temp[1000];
        deadbeef->plt_get_title (plt, title_temp, sizeof (title_temp));
        if (plt_active == (int)row && highlight_curr) {
            if (playback_state == DDB_PLAYBACK_STATE_PAUSED) {
                snprintf (title, sizeof (title), "%s%s", title_temp, " (paused)");
            }
            else if (playback_state == DDB_PLAYBACK_STATE_STOPPED) {
                snprintf (title, sizeof (title), "%s%s", title_temp, " (stopped)");
            }
            else {
                snprintf (title, sizeof (title), "%s%s", title_temp, " (playing)");
            }
        }
        else {
            snprintf (title, sizeof (title), "%s", title_temp);
        }
        view.textField.stringValue = [NSString stringWithUTF8String:title];
    }
    else if ([tableColumn.identifier isEqualToString:@"Items"]) {
        char num_items_str[100];
        int num_items = deadbeef->plt_get_item_count (plt, PL_MAIN);
        snprintf (num_items_str, sizeof (num_items_str), "%d", num_items);
        view.textField.stringValue = [NSString stringWithUTF8String:num_items_str];
    }
    else if ([tableColumn.identifier isEqualToString:@"Duration"]) {
        float pl_totaltime = deadbeef->plt_get_totaltime (plt);
        int daystotal = (int)pl_totaltime / (3600*24);
        int hourtotal = ((int)pl_totaltime / 3600) % 24;
        int mintotal = ((int)pl_totaltime/60) % 60;
        int sectotal = ((int)pl_totaltime) % 60;

        char totaltime_str[512] = "";
        if (daystotal == 0) {
            snprintf (totaltime_str, sizeof (totaltime_str), "%d:%02d:%02d", hourtotal, mintotal, sectotal);
        }
        else {
            snprintf (totaltime_str, sizeof (totaltime_str), "%dd %d:%02d:%02d", daystotal, hourtotal, mintotal, sectotal);
        }
        view.textField.stringValue = [NSString stringWithUTF8String:totaltime_str];
    }
    else {
        view.textField.stringValue = @"";
    }

    if (plt != NULL) {
        deadbeef->plt_unref (plt);
    }

    return view;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (self.isReloading) {
        return;
    }
    NSInteger selectedRow = self.tableView.selectedRow;

    ddb_playlist_t *plt = NULL;
    if (selectedRow != -1) {
        plt = deadbeef->plt_get_for_idx ((int)selectedRow);
    }
    deadbeef->plt_set_curr (plt);
    if (plt != NULL) {
        deadbeef->plt_unref (plt);
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return deadbeef->plt_get_count();
}

#pragma mark - RenamePlaylistViewControllerDelegate

- (void)renamePlaylist:(RenamePlaylistViewController *)viewController doneWithName:(NSString *)name {
    ddb_playlist_t *plt = deadbeef->plt_get_for_idx ((int)self.clickedRow);
    if (plt == NULL) {
        return;
    }
    deadbeef->plt_set_title (plt, [name UTF8String]);
    deadbeef->plt_save_config (plt);
    deadbeef->plt_unref (plt);
}

#pragma mark - DeletePlaylistConfirmationControllerDelegate

- (void)deletePlaylistDone:(DeletePlaylistConfirmationController *)controller {
    deadbeef->plt_remove ((int)self.clickedRow);
    int playlist = deadbeef->plt_get_curr_idx ();
    deadbeef->conf_set_int ("playlist.current", playlist);
    self.clickedRow = -1;
}

@end
