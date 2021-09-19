#!/usr/sbin/dtrace -s

/*
 *  traceSQLiteSyscalls.d
 *  PerformanceTools
 *
 *  Created by Ben Nham on 2/25/11.
 *  Copyright 2011 Apple. All rights reserved.
 *
 *  Prints out all syscalls made during a sqlite3_prepare or sqlite3_step call.
 *  
 *  You can attach to a process that's already running (probably best to make sure app has SQLITE_AUTO_TRACE on):
 *  
 *  # traceSQLiteSyscalls.d -p `pidof Contacts~iphone`
 *
 *  Or attach to a process before it launches. To do this, use the dtrace-wait wrapper script
 *  to wait for the process to start up:
 *  
 *    # dtrace-wait Contacts~ipad -s traceSQLiteSyscalls.d
 *  
 *  In another terminal, start the process with LaunchApp so that it will print
 *  out all queries using SQLITE_AUTO_TRACE:
 *  
 *    # SQLITE_AUTO_TRACE=1 LaunchApp com.apple.MobileAddressBook 
 *  
 *  You then get output like this:
 *  
 *    SELECT ROWID, Name, ExternalIdentifier, Type, ConstraintsPath,
 *      ExternalModificationTag,  ExternalSyncTag, AccountIdentifier, Enabled, 
 *      SyncData, MeIdentifier FROM ABStore WHERE Enabled = '1';
 *    F_SETLK(AddressBook.sqlitedb, F_RDLCK, 1b@0b) => 0
 *    F_SETLK(AddressBook.sqlitedb, F_RDLCK, 510b@2b) => 0
 *    F_SETLK(AddressBook.sqlitedb, F_UNLCK, 1b@0b) => 0
 *    access(AddressBook.sqlitedb-journal) => -1
 *    fstat64(AddressBook.sqlitedb) => 0
 *    pread(AddressBook.sqlitedb, 16b@24b) => 16
 *    fstat64(AddressBook.sqlitedb) => 0
 *    access(AddressBook.sqlitedb-wal) => -1
 *    fstat64(AddressBook.sqlitedb) => 0 
 *
 */

#pragma D option quiet

BEGIN
{
     fcntl[7] = "F_GETLK";
     fcntl[8] = "F_SETLK";
     fcntl[9] = "F_SETLKW";
     
     lockType[1] = "F_RDLCK";
     lockType[2] = "F_UNLCK";
     lockType[3] = "F_WRLCK";
     
     seek[0] = "SEEK_SET";
     seek[1] = "SEEK_CUR";
     seek[2] = "SEEK_END";
     
     printf("Tracing...\n");
}

/* sometimes prepare and step are re-entrant */
pid$target:libsqlite3.dylib:sqlite3_prepare*:entry  { self->prepareLevel++; }
pid$target:libsqlite3.dylib:sqlite3_prepare*:return { self->prepareLevel--; }
pid$target:libsqlite3.dylib:sqlite3_step*:entry     { self->stepLevel++;    }
pid$target:libsqlite3.dylib:sqlite3_step*:return    { self->stepLevel--;    }

/* access, unlink */
syscall::access:entry,
syscall::unlink:entry
/ self->prepareLevel > 0 || self->stepLevel > 0 /
{
	self->path = copyinstr(arg0);
}

syscall::access:return,
syscall::unlink:return
/ self->prepareLevel > 0 || self->stepLevel > 0 /
{
    printf("%s(%s) => %d\n", probefunc, self->path, arg1);
    self->path = NULL;
}

/* fsync, fstat64 */
syscall::fsync:entry,
syscall::fstat64:entry
/ self->prepareLevel > 0 || self->stepLevel > 0 /
{
    self->fd = arg0;
}

syscall::fsync:return,
syscall::fstat64:return
/ self->prepareLevel > 0 || self->stepLevel > 0 /
{
    printf("%s(%d [%s]) => %d\n", probefunc, self->fd, fds[self->fd].fi_name, arg1);
    self->fd = NULL;
}

/* fcntl byte-range locking and full fsyncs */
syscall::fcntl:entry
/ (self->prepareLevel > 0 || self->stepLevel > 0) && fcntl[arg1] != NULL /
{
	self->fd = arg0;
    self->op = fcntl[arg1];
    
    this->flock = (struct flock *)copyin(arg2, sizeof(struct flock));
    self->offset = this->flock->l_start;
    self->length = this->flock->l_len;
    self->pid = this->flock->l_pid;
    self->type = lockType[this->flock->l_type];
    self->whence = seek[this->flock->l_whence];
}

/* check out PENDING_BYTE defines and friends in SQLite sources to figure out what these byte offsets mean. */
syscall::fcntl:return
/ (self->prepareLevel > 0 || self->stepLevel > 0) && self->op != NULL && self->op != "F_FULLFSYNC" /
{
    printf("%s(%d [%s], %s, %d@0x%p) => %d\n", 
        self->op,
        self->fd,
        fds[self->fd].fi_name,
        self->type,
        self->length,
        self->offset,
        arg1);
    
    self->fd = 0;
    self->op = NULL;
    self->flock = NULL;
    self->offset = NULL;
    self->length = NULL;
    self->pid = NULL;
    self->type = NULL;
    self->whence = NULL;
}

syscall::fcntl:entry
/ (self->prepareLevel > 0 || self->stepLevel > 0) && arg1 == 51 /
{
	self->fd = arg0;
    self->op = "F_FULLFSYNC";
}

syscall::fcntl:return
/ (self->prepareLevel > 0 || self->stepLevel > 0) && self->op == "F_FULLFSYNC" /
{
    printf("fcntl(%d [%s], %s) => %d\n", self->fd, fds[self->fd].fi_name, self->op, arg1);
    
    self->fd = 0;
    self->op = NULL;
}

/* reads and writes */

syscall::pread:entry, syscall::pwrite:entry
/ (self->prepareLevel > 0 || self->stepLevel > 0) /
{
	self->fd = arg0;
    self->nbyte = arg2;
    self->offset = arg3;
}

syscall::pread:return, syscall::pwrite:return
/ (self->prepareLevel > 0 || self->stepLevel > 0) && self->nbyte /
{
    printf("%s(%d [%s], %d@%d) => %d\n", probefunc, self->fd, fds[self->fd].fi_name, self->nbyte, self->offset, arg1);
    
    self->fd = 0;
    self->nbyte = 0;
    self->offset = 0;
}

pid$target:libsqlite3.dylib:_sqlite_auto_trace*:entry
{
    printf("-- connection 0x%p: %s\n", arg0, copyinstr(arg1));

    ustack();
}
