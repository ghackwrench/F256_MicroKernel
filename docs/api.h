/*
 * This file is part of the TinyCore MicroKernel for the Foenix F256,
 * Copyright 2022,2023 Jessie Oberreuter <Gadget@HackwrenchLabs.com>. As with
 * the Linux Kernel Exception to the GPL3, programs built to run on the
 * MicroKernel are expected to include this file. Doing so does not affect
 * their license status.
 * 
 * SPDX-License-Identifier: GPL-3.0-only
 */

/*
 * Kernel calls populate the kernel.arg.* variables appropriately, and then
 * JSR to one of the velctors below:
 */

#ifndef kernel_h
#define kernel_h

#include <stdint.h>

struct call {  // Mount at $ff00
    
    long NextEvent;  // Copy the next event into user-space.
    long ReadData;   // Copy primary bulk event data into user-space
    long ReadExt;    // Copy secondary bolk event data into user-space
    long Yield;      // Give unused time to the kernel.
    long Putch;      // deprecated
    long Basic;      // deprecated
    long dummy1;     // reserved
    long dummy2;     // reserved
    
    struct {
        long List;       // Returns a bit-set of available block-accessible devices.
        long GetName;    // Gets the hardware level name of the given block device or media.
        long GetSize;    // Get the number of raw sectors (48 bits) for the given device
        long Read;       // Read a raw sector (48 bit LBA)
        long Write;      // Write a raw sector (48 bit LBA)
        long Format;     // Perform a low-level format if the media support it.
        long Export;     // Update the FileSystem table with the partition table (if present).
    } BlockDevice;
    
    struct {
        long List;       // Returns a bit-set of available logical devices.
        long GetSize;    // Get the size of the partition or logical device in sectors.
        long MkFS;       // Creates a new file-system on the logical device.
        long CheckFS;    // Checks the file-system for errors and corrects them.
        long Mount;      // Mark the file-system as available for File and Directory operations.
        long Unmount;    // Mark the file-system as unavailable for File and Directory operations.
        long ReadBlock;  // Read a partition-local raw sector on an unmounted device.
        long WriteBlock; // Write a partition-local raw sector on an unmounted device.
    } FileSystem;
    
    struct { 
        long Open;       // Open the given file for read, create, or append.
        long Read;       // Request bytes from a file opened for reading.
        long Write;      // Write bytes to a file opened for create or append.
        long Close;      // Close an open file.
        long Rename;     // Rename a closed file.
        long Delete;     // Delete a closed file.
    } File;
    
    struct {
        long Open;       // Open a directory for reading.
        long Read;       // Read a directory entry; may also return VOLUME and FREE events.
        long Close;      // Close a directory once finished reading.
    } Directory;
    
    long gate;    
    
    struct {
        long GetSize;    // Returns rows/cols in kernel args.
        long DrawRow;    // Draw text/color buffers left-to-right
        long DrawColumn; // Draw text/color buffers top-to-bottom
    } Display;
    
    struct {
        long GetIP;      // Get the local IP address.
        long SetIP;      // Set the local IP address.
        long GetDNS;     // Get the configured DNS IP address.
        long SetDNS;     // Set the configured DNS IP address.
        long GetTime;    //
        long SetTime;    //
        long GetSysInfo; //
        long SetBPS;     // Set the serial BPS (should match the SLIP router's speed).
    } Config;
    
    struct {
        long InitUDP;    //
        long SendUDP;    //
        long RecvUDP;    //
        long InitTCP;    //
        long SendTCP;    //
        long RecvTCP;    //
        long SendICMP;   //
        long RecvICMP;   //
    } Net;
};

// Kernel Call Arguments; mount at $f0

struct events_t {
    struct event_t *  event;   // GetNextEvent copies event data here
    char              pending; // Negative count of pending events
};

struct common_t {
    char     dummy[8-sizeof(struct events_t)];
    void *   ext;
    uint8_t  extlen;
    void *   buf;
    uint8_t  buflen;
    void *   internal;
};
    
struct fs_mkfs_t {
    uint8_t  drive;
    uint8_t  cookie;
    // label = common.buf; label_len = common.buflen
};
    
struct fs_t {
    union {
        struct fs_mkfs_t  format;
        struct fs_mkfs_t  mkfs;
    };
};

struct fs_open_t {
    uint8_t drive;
    uint8_t cookie;
    uint8_t mode;
    // fname       = common.buf
    // fname_len   = common.buflen
};

enum fs_open_mode {
    READ,
    WRITE,
};

struct fs_read_t {
    uint8_t stream;
    uint8_t buflen;
};

struct fs_write_t {
    uint8_t stream;
    // buf         = common.buf
    // buflen      = common.buflen
};

struct fs_close_t {
    uint8_t stream;
};

struct fs_rename_t {
    uint8_t drive;
    uint8_t cookie;
    // old         = args.buf
    // old_len     = args.buflen
    // new         = args.ext
    // new_len     = args.extlen
};

struct fs_delete_t {
    uint8_t drive;
    uint8_t cookie;
    // fnane       = args.buf
    // fname_len   = args.buflen
};

struct file_t {
    union {
        struct fs_open_t    open;
        struct fs_read_t    read;
        struct fs_write_t   write;
        struct fs_close_t   close;
        struct fs_rename_t  rename;
        struct fs_delete_t  delete;
    };
};

struct dir_open_t {
    uint8_t drive;
    uint8_t cookie;
    // fname       = args.buf
    // fname_len   = args.buflen
};

struct dir_read_t {
    uint8_t stream;
    uint8_t buflen;
};

struct dir_close_t {
    uint8_t stream;
};

struct dir_t {
    union {
        struct dir_open_t   open;
        struct dir_read_t   read;
        struct dir_close_t  close;
    };
};

struct display_t {
    uint8_t x; // coordinate or size
    uint8_t y; // coordinate or size
    // text        = args.buf      ; text
    // color       = args.ext      ; color
    // buflen      = args.buflen
};


struct call_args {
    struct events_t events;  // The GetNextEvent dest address is globally reserved.
    union {
        struct common_t   common;
        struct fs_t       fs;
        struct file_t     file;
        struct dir_t      directory;
        struct display_t  display;
     // struct net_t      net;
    };
};




// Events
// The vast majority of kernel operations communicate with userland
// by sending events; the data contained in the various events are
// described following the event list.

struct events {
    uint16_t reserved;
    uint16_t deprecated;
    uint16_t GAME;        // joystick events
    uint16_t DEVICE;      // deprecated
    
    struct {
        uint8_t PRESSED;
        uint8_t RELEASED;
    } key;
    
    struct {
        uint8_t DELTA;
        uint8_t CLICKS;
    } mouse;
    
    struct {
        uint8_t NAME;
        uint8_t SIZE;
        uint8_t DATA;
        uint8_t WROTE;
        uint8_t FORMATTED;
        uint8_t ERROR;
    } block;
    
    struct {
        uint8_t SIZE;
        uint8_t CREATED;
        uint8_t CHECKED;
        uint8_t DATA;
        uint8_t WROTE;
        uint8_t ERROR;
    } fs;
    
    struct {
        uint8_t NOT_FOUND;
        uint8_t OPENED;
        uint8_t DATA;
        uint8_t WROTE;
        uint8_t EOF;
        uint8_t CLOSED;
        uint8_t RENAMED;
        uint8_t DELETED;
        uint8_t ERROR;
    } file;
    
    struct {
        uint8_t OPENED;
        uint8_t VOLUME;
        uint8_t FILE;
        uint8_t FREE;
        uint8_t EOF;
        uint8_t CLOSED;
        uint8_t ERROR;
    } directory;
};

                 
struct event_key_t {
    uint8_t keyboard;
    uint8_t raw;
    char    ascii;
    char    flags;  // negative for no associated ASCII.
};

struct event_mouse_delta_t {
    char     x;
    char     y;
    char     z;
    uint8_t  buttons;
};

struct event_mouse_clicks_t {
    uint8_t inner;
    uint8_t middle;
    uint8_t outer;
};

struct event_mouse_t {
    union {
        struct event_mouse_delta_t  delta;
        struct event_mouse_clicks_t clicks;
    };
};

struct event_fs_data_t {
    uint8_t requested;    // Requested number of bytes to read
    uint8_t delivered;    // Number of bytes actually read
};

struct event_fs_wrote_t {
    uint8_t requested;    // Requested number of bytes to write
    uint8_t delivered;    // Number of bytes actually written
};

struct event_file_t {
    uint8_t stream;
    uint8_t cookie;
    union {
        struct    event_fs_data_t   data;
        struct    event_fs_wrote_t  wrote;
    };
};

struct event_dir_vol_t { // ext contains disk id
    uint8_t len;    // Length of volname (in buf)
    uint8_t flags;  // block size, text encoding
};

struct event_dir_file_t { // ext contains byte count and modified date
    uint8_t len;    // Length of name (in buf)
    uint8_t flags;  // block size, text encoding
};

struct event_dir_free_t {  // ext contains the block count &c
    uint8_t flags;  // block size, text encoding
};

struct dir_ext_t {  // Extended information; more to follow.
    uint32_t free;  // Actually, 48 bits, but you'll prolly never hit it.
};

struct event_dir_t {
    uint8_t stream;
    uint8_t cookie;
    union {
        struct event_dir_vol_t  volume;
        struct event_dir_file_t file;
        struct event_dir_free_t free;
    };
};

struct event_t {
    uint8_t type;
    uint8_t buf;    // kernel's buf page ID
    uint8_t ext;    // kernel's ext page ID
    union {
        struct event_key_t    key;
        struct event_mouse_t  mouse;
        struct event_file_t   file;
        struct event_dir_t    directory;
    };
};
#endif
