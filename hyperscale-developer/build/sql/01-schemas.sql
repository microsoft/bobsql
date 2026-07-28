/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   01-schemas.sql  : create the two application schemas for Ward General Hospital
   Target          : the wardgeneral Hyperscale database (clinical.* / ops.*)
   Run order       : 1 of 5  (schemas -> tables -> views -> procedures -> seed)

   All data created by these scripts is fully synthetic. No real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* clinical : patient-linked clinical data (PHI surface for RLS + masking)         */
IF SCHEMA_ID(N'clinical') IS NULL
    EXEC (N'CREATE SCHEMA clinical AUTHORIZATION dbo;');
GO

/* ops : scheduling and organizational reference data */
IF SCHEMA_ID(N'ops') IS NULL
    EXEC (N'CREATE SCHEMA ops AUTHORIZATION dbo;');
GO
