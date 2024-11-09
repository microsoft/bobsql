# Example 1 - Transaction Log File

SQL Server 2022 will be used for examples.

## Example 1.1 - Physical Log File

1. Create a database in SSMS using the query editor with no options so all defaults are used

```sql
CREATE DATABASE defaultdb;
GO
```

2. Examine the default size and autogrow using the following query

```sql
USE defaultdb;
GO
SELECT name, size*8192/(1024*1024) AS size_in_MB, growth*8192/(1024*1024) AS growth_in_MB
FROM sys.database_files
WHERE file_id = 2;
GO
```

3. Let's look at the file header page of the log file using the following query:

```sql
DBCC TRACEON(3604);
GO
DBCC PAGE(defaultdb, 2, 0, 3);
GO
```

This is identical to the file header page of the data file except for details about the log file.

## Example 1.2 - Virtual Log File

1. Let's see how VLFs are created for a physical log file. Using the example in Example 1.1, let's see what VLFs look like by executing the following query:

```sql
SELECT * FROM sys.dm_db_log_info(DB_ID('defaultdb'));
```

Let's break down the output of this query:

- There are 4 VLFs in the log file
- The first VLF is "active" and the rest are "inactive" as you can see from vlf_active = 1 and vlf_status = 2. The active VLF is the one that is currently being written to.
- Notice the first VLF starts at physical offset 8192 bytes into the file because of the log file header page.
- Because the log header page takes up 8192 bytes the VLFs cannot be divided evenly so the first 3 VLFs are 1.92MB and the last one if 2.17MB. vlf_size_mb is "rounded" but if you calculate the differences for each vlf_begin_offset you can see the actual byte difference and it adds up to 8388608 which is 8MB.
- The vlf_sequence number is 39 for the active VLF because the last vlf_sequence_number for model was 38.
- The vlf_parity is 64 which is 0x40 or 01000000.
- The vlf_first_lsn is the first log record in the VLF which we will examine later

2. Let's see what VLFs look like for other sized databases.

-- A database log file of 64MB has 4 VLFs roughly 16Mb each
-- A database log file of 1GB has 8 VLFs roughly 128Mb each
-- A database log file of 2GB has 16 VLFs roughly 128Mb each
-- A database log file of 20GB has 16 VLFs roughly 1.28GB each

3. Let's see the VLF log header information in each VLF and what the "empty" VLFs look like

Here are the offsets for each VLF

database_id	file_id	vlf_begin_offset

14	2	8192
14	2	2039808
14	2	4071424
14	2	6103040

a. Shutdown SQL Server
b. Use the list.exe program in hex mode to look at the log file

The first 2000 (hex) bytes are the log file header. So let's go at 2000 (hex) to see the VLF header.

The VLF header is actually 8192 bytes even though it does not take up a page but it is written as a page. So the first log block is at 4000 (hex).

At 4000 hex, notice the first byte is 0x50. This is the parity bytes of 0x40 OR'd with 0x10 which indicates this the first 512 sector of the log block. Go to 4200 which is the next 512 bytes and now you see 0x40. Go to 4E00 (hex) and you will see 0x48. The last sector of the log block is OR'd with 0x08.

This means the 1st log block is 4KB in size. You can see at 5000 at new log block.

iF you start scrolling down on the right side you can see strings which are part of log records.

Note: Use in later lab on LSN. You can find a log block physically in a log file by using this formula:

log block offset*0x200 (512 bytes)+0x2000 (first page of VLF). this is the physical offset of the log block in the log file.