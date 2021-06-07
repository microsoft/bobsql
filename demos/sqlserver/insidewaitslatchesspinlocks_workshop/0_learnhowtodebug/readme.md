# Learn the basics of how to debug SQL Server

1. Download and install SQL Server 2019 Developer Edition from https://go.microsoft.com/fwlink/?linkid=866662

2. Install the "classic" Windows Debugger (windbg) from https://docs.microsoft.com/en-us/windows-hardware/drivers/debugger/debugger-download-tools#small-classic-windbg-preview-logo-debugging-tools-for-windows-10-windbg

3. Put the location of windbg in your system path. The classic debugger it should be something like c:\program files (x86)\Windows Kits\10\Debuggers\64

4. Get ready to do some debuggin!

5. Run the following command to attach to the SQL Server process

    `windbg -y srv*c:\public_symbols*http://msdl.microsoft.com/download/symbols -pn sqlservr.exe`

    Any loaded symbols will be cached in the local directory

6. Adjust the font under the View menu. Use File/Save Workspace to make it stick.

7. Since you attached to the SQL Server process, it is "frozen" so you can't connect or run queries. By default a history is dumped out of modules loaded in the process.

8. Left of the prompt is the thread "number". Type in 
 
    `k`

    This is the callstack for the thread that was injected to break into the process for the debugger

9. Type in 
 
    `~`

    This is a list of all threads in the process. The columns are from left to right:

    Thread number
    Process id
    Thread id
    Thread suspend status
    Thread Environment Block address
    Thread frozen state

10. Try dumping the call stack of a specific thread

    `~0k`

    This could take a second while symbols get loaded

    This is the call stack of the "main" thread for the SQL Server process

11. Use this command to "switch" to that thread

    `~0s`

12. Notice the thread number changes. Type in

    `k`

    to see the same stack

    type in

    `kv`

    and

    `kn`

    to get more from the stack such as Arguments

13. Dump out callstack for all threads (this could take a while) with this command

    `~*k`

14. How about only unique callstacks

    `!uniqstack`

15. Let's dump out modules

    `lm`

    Find sqlservr and click on the link. Observe the output

16. Let's browse some symbols from public symbols

    `x kernelbase!*VirtualAlloc*`

    This is a list of Windows functions to allocate virtual memory

17. How about this one for sqlservr

    `x sqlservr!Resource`

18. Dump out the process environment block

    `!peb`

19. Learn to dump out memory addresses

    Search the output of !peb and find the Environment: section.

    Dump out the memory at that address as bytes

    `dd <address>`

    Now dump it out as bytes with ascii on the right

    `db <address>`

20. Type

    `q`

    to quit







WAIT!!!!!! You just crashed SQL Server. Use .detach next time
