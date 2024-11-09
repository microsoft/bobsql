Test 1

db has 4 VLFs to start with and only 1 active
open a transaction and hold it
checkpoint
kill SQL
Start SQL

Test 2

Same but run workload that grows VLFs to 1000 (997)

Size was 128128 or 1,049,624,576 bytes (1GB)

2024-10-28 18:42:10.28 spid72s     1 transactions rolled back in database 'growvlf' (17:0). This is an informational message only. No user action is required.
2024-10-28 18:42:10.28 spid72s     Recovery is writing a checkpoint in database 'growvlf' (17). This is an informational message only. No user action is required.
2024-10-28 18:42:10.32 spid72s     Recovery completed for database growvlf (database ID 17) in 4 second(s) (analysis 1 ms, redo 3701 ms, undo 13 ms [system undo 0 ms, regular undo 0 ms].) ADR-enabled=0, Is primary=1, OL-Enabled=0. This is an informational message only. No user action is required.

Test 3

Same for 10000 VLFs

size was 1280512 pages

Recovery looks like this

2024-10-28 19:50:27.86 spid71s     Recovery completed for database growvlf (database ID 17) in 31 second(s) (analysis 2 ms, redo 30160 ms, undo 16 ms [system undo 0 ms, regular undo 0 ms].) ADR-enabled=0, Is primary=1, OL-Enabled=0. This is an informational message only. No user action is required.

Test 4

Do Test 2 except this time same log size must 1 extra VLF instead of 1000
A 1GB autogrow resulted in 8 more VLFs (so 12 in total) of 128MB in size.

Recovery perf was the same

2024-10-28 18:52:50.29 spid71s     1 transactions rolled back in database 'growvlf' (17:0). This is an informational message only. No user action is required.
2024-10-28 18:52:50.29 spid71s     Recovery is writing a checkpoint in database 'growvlf' (17). This is an informational message only. No user action is required.
2024-10-28 18:52:50.44 spid71s     Recovery completed for database growvlf (database ID 17) in 4 second(s) (analysis 4 ms, redo 2978 ms, undo 12 ms [system undo 0 ms, regular undo 0 ms].) ADR-enabled=0, Is primary=1, OL-Enabled=0. This is an informational message only. No user action is required.
2024-10-28 18:52:50.44 spid71s     Parallel redo is shutdown for database 'growvlf' with worker pool size [8].

Test 5

Sane as Test 3 but only 1 autogrow instead of 10000
autogrow should be ~10GB
When this occurs you get 16 additional VLFs at 640MB each

select * from sys.dm_db_log_info(db_id('growvlf'))
select * from sys.database_files

Recovery was

2024-10-28 20:35:15.42 spid67s     Recovery completed for database growvlf (database ID 17) in 27 second(s) (analysis 4 ms, redo 26595 ms, undo 15 ms [system undo 0 ms, regular undo 0 ms].) ADR-enabled=0, Is primary=1, OL-Enabled=0. This is an informational message only. No user action is required.
10000 VLFs was only 4 seconds slower!

checkpoint