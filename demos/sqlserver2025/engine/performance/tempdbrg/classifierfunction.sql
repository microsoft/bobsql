USE master;
GO

-- Create a classifier function
CREATE FUNCTION dbo.ResourceGovernorClassifier()
RETURNS SYSNAME
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @WorkloadGroup SYSNAME;

    -- Example logic: Assign sessions based on application name
    IF APP_NAME() = 'GuyInCube'
    BEGIN
        SET @WorkloadGroup = 'GroupforUsersWhoDontKnowSQL';  -- Assign to your custom workload group
    END
    ELSE
    BEGIN
        SET @WorkloadGroup = 'default';  -- Assign to the default workload group
    END

    RETURN @WorkloadGroup;
END;
GO

-- Register the classifier function with Resource Governor
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.ResourceGovernorClassifier);
GO

-- Apply the changes
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO