USE master;
GO
DROP DATABASE IF EXISTS contactsdb;
GO
CREATE DATABASE contactsdb;
GO
USE contactsdb;
GO

-- Create a new database with a JSON type to hold the document
DROP TABLE IF EXISTS contacts;
GO
CREATE TABLE contacts (id INT IDENTITY PRIMARY KEY, jdoc JSON);
GO

-- INSERT enough rows to ensure the index will make sense
INSERT INTO dbo.contacts (jdoc) VALUES
(N'{
  "guid":"9c36adc1-7fb5-4d5b-83b4-90356a46061a",
  "name":"Angela Barton",
  "is_active":true,
  "company":"Magnafone",
  "address":"178 Howard Place, Gulf, Washington, 702",
  "registered":"2009-11-07T08:53:22+08:00",
  "latitude":19.793713,
  "longitude":86.513373,
  "tags":["enim","aliquip","qui"],
  "id":495
}'),
(N'{
  "guid":"a1b2c3d4-e5f6-7g8h-9i0j-k1l2m3n4o5p6",
  "name":"John Doe",
  "is_active":false,
  "company":"TechCorp",
  "address":"123 Main Street, Springfield, IL, 62701",
  "registered":"2021-05-15T14:30:00+00:00",
  "latitude":39.7817,
  "longitude":-89.6501,
  "tags":["tech","innovation","startup"],
  "id":236
}'),
(N'{
  "guid":"b2c3d4e5-f6g7-h8i9-j0k1-l2m3n4o5p6q7",
  "name":"Jane Smith",
  "is_active":true,
  "company":"HealthPlus",
  "address":"456 Elm Street, Metropolis, NY, 10001",
  "registered":"2018-09-23T10:15:30+00:00",
  "latitude":40.7128,
  "longitude":-74.0060,
  "tags":["health","wellness","fitness"],
  "id":1284
}'),
(N'{
  "guid":"c3d4e5f6-g7h8-i9j0-k1l2-m3n4o5p6q7r8",
  "name":"Alice Johnson",
  "is_active":true,
  "company":"EduWorld",
  "address":"789 Oak Avenue, Gotham, CA, 90210",
  "registered":"2020-11-11T08:45:00+00:00",
  "latitude":34.0522,
  "longitude":-118.2437,
  "tags":["education","learning","development"],
  "id":9637
}'),
(N'{
  "guid":"g7h8i9j0-k1l2-m3n4-o5p6-q7r8s9t0u1v2",
  "name":"Sophia Martinez",
  "is_active":false,
  "company":"BioHealth",
  "address":"404 Cedar Street, Boston, MA, 02108",
  "registered":"2023-02-14T16:00:00+00:00",
  "latitude":42.3601,
  "longitude":-71.0589,
  "tags":["biotech","healthcare","research"],
  "id":5342
}'),
(N'{
  "guid":"h8i9j0k1-l2m3-n4o5-p6q7-r8s9t0u1v2w3",
  "name":"Olivia Taylor",
  "is_active":true,
  "company":"AgriCorp",
  "address":"505 Walnut Street, Des Moines, IA, 50309",
  "registered":"2020-08-30T07:15:00+00:00",
  "latitude":41.5868,
  "longitude":-93.6250,
  "tags":["agriculture","farming","sustainability"],
  "id":8334
}'),
(N'{
  "guid":"i9j0k1l2-m3n4-o5p6-q7r8-s9t0u1v2w3x4",
  "name":"Liam Johnson",
  "is_active":true,
  "company":"UrbanTech",
  "address":"606 Spruce Street, Seattle, WA, 98101",
  "registered":"2016-12-05T18:25:00+00:00",
  "latitude":47.6062,
  "longitude":-122.3321,
  "tags":["urban","technology","development"],
  "id":7653
}');
GO

DECLARE
    @rows int = 5000000,
    @batch int = 50000,
    @fitnessPc int = 5;

DECLARE @i int = 0;
WHILE @i < @rows
BEGIN
    ;WITH n AS (
        SELECT TOP (@batch)
               ROW_NUMBER() OVER (ORDER BY (SELECT 0)) AS rn,
               ABS(CHECKSUM(NEWID())) AS r1,
               ABS(CHECKSUM(NEWID())) AS r2,
               ABS(CHECKSUM(NEWID())) AS r3
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    )
    INSERT INTO dbo.contacts(jdoc)
    SELECT
        /* Uncomment if your build requires explicit conversion:
           CAST( */
           JSON_OBJECT(
               'guid': CONVERT(nvarchar(36), NEWID()),
               'name': CONCAT('Noise Person #', @i + rn),
               'is_active': CASE WHEN r1 % 2 = 0 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END,
               'company': CASE 
                             WHEN r2 % 20 = 0 THEN 'NoiseCo20'
                             WHEN r2 % 10 = 0 THEN 'NoiseCo10'
                             WHEN r2 % 5  = 0 THEN 'NoiseCo5'
                             ELSE 'NoiseCo'
                          END,
               'address': CONCAT(@i + rn, ' Random Ave, City, ST, 12345'),
               'registered': SYSDATETIMEOFFSET(),
               'latitude':  25.0 + (r1 % 100000) / 10000.0,
               'longitude': -(70.0 + (r2 % 100000) / 10000.0),
               'tags': JSON_ARRAY('noise', 'seek', 'other'),
               'id': 1000000 + @i + rn
           )
        /* AS JSON) */
    FROM n;
    SET @i += @batch;
END;
GO

UPDATE STATISTICS dbo.contacts WITH FULLSCAN;
GO
