set nocount on
declare @i int;
declare @s varchar(100);
declare @x float(10);

set @i=100000000

while @i > 0 
begin
	select @s = @@version;
	--if (@i % 5 = 0)
		select @x=VAR(s1.object_id) FROM sys.all_columns s1 INNER JOIN sys.all_columns s2 ON s1.object_id = s2.object_id WHERE s1.name LIKE '%a%' 
	set @i = @i - 1;
end