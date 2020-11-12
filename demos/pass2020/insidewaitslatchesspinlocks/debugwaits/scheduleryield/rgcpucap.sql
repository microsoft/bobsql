--alter to 5 (make sure you revert it back later) 
ALTER RESOURCE POOL [default] 
WITH ( CAP_CPU_PERCENT = 5 ); 
go 
ALTER RESOURCE GOVERNOR RECONFIGURE; 
go