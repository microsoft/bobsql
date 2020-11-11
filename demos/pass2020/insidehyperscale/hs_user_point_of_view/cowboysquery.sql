SET STATISTICS IO ON
GO
SELECT * FROM dbo.howboutthemcowboys WHERE col1 > 10 and col1 < 2000000;
GO