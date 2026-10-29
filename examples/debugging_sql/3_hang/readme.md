# Demos for SQL Server hangs

1. Run debug server again

- Run **nonyield.cmd**
- Show the script **nonyield.sql**
- After a few seconds you will see info in ERRORLOG
- Wait a bit longer and you get a stack dump

2. Go to the LOG directory

- Edit **debughang.cmd** to get the last .MDMP file
- Look at the debugger header
- Type in `k` to see the call stack
- Why is this a non-yielding problem based on the assembly instruction?
- It depends where in the code the dump was triggered. For one of the dumps the current instruction looks like

```armasm
jmp     sqlmin!NonYieldTest+0x3c5 (00007ffc`9f277ac5)
```
- Type in this instruction

```armasm
u 0007ffc`9f277ac5
```

If you keep hitting `u` you will see these instructions

```armasm
00007ffc`9f277b0a 85c0            test    eax,eax
00007ffc`9f277b0c 7402            je      sqlmin!NonYieldTest+0x410 (00007ffc`9f277b10)
00007ffc`9f277b0e eb02            jmp     sqlmin!NonYieldTest+0x412 (00007ffc`9f277b12)
00007ffc`9f277b10 ebb3            jmp     sqlmin!NonYieldTest+0x3c5 (00007ffc`9f277ac5)
```
This is a signature for a loop.

- So basically we are in a big loop not yielding to SQLOS. How is the server detecting the dump?

- Type in `!uniqstack`
- Search for **SchedulerMonitor**
- Notice the callstack is the one triggering the dump

Stop the debug server.

3. Let's see a stalled scheduler scenario

Follow the readme.md in the **scheduler_deadlock** folder