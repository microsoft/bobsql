USE [WideWorldImporters]
GO

/****** Object:  Table [Warehouse].[VehicleTemperatures]    Script Date: 6/9/2018 2:02:36 PM ******/
DROP TABLE [Warehouse].[VehicleTemperatures]
GO

/****** Object:  Table [Warehouse].[VehicleTemperatures]    Script Date: 6/9/2018 2:02:36 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Warehouse].[VehicleTemperatures]
(
	[VehicleTemperatureID] [bigint] IDENTITY(1,1) NOT NULL,
	[VehicleRegistration] [nvarchar](20) COLLATE Latin1_General_CI_AS NOT NULL,
	[ChillerSensorNumber] [int] NOT NULL,
	[RecordedWhen] [datetime2](7) NOT NULL,
	[Temperature] [decimal](10, 2) NOT NULL,
	[FullSensorData] [nvarchar](1000) COLLATE Latin1_General_CI_AS NULL,
	[IsCompressed] [bit] NOT NULL,
	[CompressedSensorData] [varbinary](max) NULL,

 CONSTRAINT [PK_Warehouse_VehicleTemperatures]  PRIMARY KEY NONCLUSTERED 
(
	[VehicleTemperatureID] ASC
)
)WITH ( MEMORY_OPTIMIZED = ON , DURABILITY = SCHEMA_AND_DATA )
GO

delete from [Warehouse].[VehicleTemperatures]
go
begin tran
go
set nocount on
go
declare @x int
set @x = 0
while (@x < 10000)
BEGIN
	insert into [Warehouse].[VehicleTemperatures]
	(vehicleregistration, chillersensornumber, recordedwhen, temperature, iscompressed)
	values ('WWI-321-A', 1, getdate(), 5.0, 0)
	set @x = @x + 1
END
GO
commit tran
go
set nocount off
go