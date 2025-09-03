SELECT statement FROM sys.fn_get_audit_file_v2(
  'https://onelake.blob.fabric.microsoft.com/c6d0a565-c00a-487d-9c9b-a18ebd83e349/8ca4a989-bac6-4f83-b31f-fb8daef8571f/Audit/sqldbauditlogs/',
  DEFAULT, DEFAULT, DEFAULT, DEFAULT
)
WHERE application_name = 'Mashup Engine (TridentDataflowNative)';
GO
