# Demo for using the debugger to look at memory

## WARNING: DO NOT TRY THIS ON A PRODUCTION SERVER. PLEASE USE A VM, your laptop, or a test machine you have exclusive access to

Prereqs

- Deploy SQL Server 2019 on Windows
- Install the Windows Debugger and make sure the install folder is in your path
- Create the db and load data from buildbigdb.sql
- Stop the SQL Server service
- Start the SQL Server service

Steps

1. Run queries from mem_accounting.sql to look at the locked model
2. Now attach the debugger with the following command

`windbg -y srv*c:\public_symbols*https://msdl.microsoft.com/download/symbols -pn sqlservr.exe`

   The debugger will come up and be at a debugger command prompt

3. Set a breakpoint with this command in the debugger window:

bp kernelbase!AllocateUserPhysicalPagesNuma

4. Now type this in the debugger command window

g

5. Run the query in runquery.sql

   Breakpoint should hit in the debugger

6. Use k in the debugger window to dump out the stack and show functions. May need to do g and k several times

7. Disable the breakpoint and type g

8. Run mem_accounting.sql again to show the full set of numbers for LOCKED model. Look at Task Manager to compare for Working Set.

9. Quit the debugger by typing in .detach and q

10. Restart SQL Server using /T835 (undoc'd trace flag to force CONVENTIONAL model for most memory)

11. Run mem_accounting.sql again and talk about the difference from LOCKED

- Attach debugger again

- Set breakpoint for sqldk!MemoryNode::VirtualAllocNativeNoCheck

- type in g

- Run runquery.sql and the breakpoint should hit

- Set breakpoint now for kernelbase!VirtualAlloc

- type in g

Show the full stack of memory allocations now coming from VirtualAlloc instead of AWE APIs

- disable breakpoints

- type in g

- Show mem_accounting.sql again to show differences. Compare to Task Manager

# APIs to check
#
# VirtualAllocExNuma
# sqldk!PhysicalPageCache::AllocatePhysicalPages
# sqldk!MemoryNode::AllocateUserPhysicalPages
# sqldk!MemoryNode::VirtualAllocNativeNoCheck
