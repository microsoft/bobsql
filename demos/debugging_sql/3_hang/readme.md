# Demos for SQL Server hangs

1. Run debug server again

- Load **nonyield.sql** in SSMS and run it
- Use **requests.sql** to see the status is RUNNING
- After a few seconds you will see info in ERRORLOG
- Wait a bit longer and you get a stack dump

2. Go to the LOG directory

- Edit **debughang.cmd** to get the last .MDMP file
- Look at the debugger header
- Type in `k` to see the call stack
- Why is this a non-yielding problem based on the assembly instruction?
- Type in `u` and find these instructions


```
00007ff8`ed0b7b0a 85c0            test    eax,eax
00007ff8`ed0b7b0c 7402            je      sqlmin!NonYieldTest+0x410 (00007ff8`ed0b7b10)
00007ff8`ed0b7b0e eb02            jmp     sqlmin!NonYieldTest+0x412 (00007ff8`ed0b7b12)
00007ff8`ed0b7b10 ebb3            jmp     sqlmin!NonYieldTest+0x3c5 (00007ff8`ed0b7ac5)
```

- These are typical of a counter and a loop. This instruction points "backwards" before our current instruction

```00007ff8`ed0b7b10 ebb3            jmp     sqlmin!NonYieldTest+0x3c5 (00007ff8`ed0b7ac5)```

- So basically we are in a big loop not yielding to SQLOS. How is the server detecting the dump?

- Type in `!uniqstack`
- Search for **SchedulerMonitor**
- Notice the callstack is the one triggering the dump

3. Let's see a stalled scheduler scenario

Follow the readme.md in the **scheduler_deadlock** folder