USE master;
GO
CREATE CREDENTIAL [https://cowboysstorage.blob.core.windows.net/cowboysfiles]  
WITH IDENTITY='SHARED ACCESS SIGNATURE',  
SECRET = 'sv=2019-12-12&ss=bfqt&srt=sco&sp=rwdlacupx&se=2021-01-01T05:02:23Z&st=2020-10-24T20:02:23Z&spr=https&sig=To46DaG0hn0OsXQmdcw0sRYXmdkBl5htHjzxOD8tdfg%3D';
GO
DROP DATABASE IF EXISTS cowboysonazure;
GO
CREATE DATABASE cowboysonazure   
ON  
( NAME = cowboysonazure_data,  
    FILENAME = 'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazuredata.mdf',
	SIZE = 100Gb)
 LOG ON  
( NAME = cowboysonazure_log,  
    FILENAME =  'https://cowboysstorage.blob.core.windows.net/cowboysfiles/cowboysonazurelog.ldf',
	SIZE = 100Gb);
GO