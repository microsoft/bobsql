EXECUTE sp_configure 'allow server scoped db credentials', 1;
GO
RECONFIGURE WITH OVERRIDE;
GO