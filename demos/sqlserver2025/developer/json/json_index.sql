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

-- Create a JSON index
DROP INDEX IF EXISTS [ji_contacts] ON contacts;
GO
CREATE JSON INDEX ji_contacts ON contacts(jdoc) FOR ('$');
GO

INSERT INTO contacts (jdoc) VALUES('
{
    "guid": "9c36adc1-7fb5-4d5b-83b4-90356a46061a",
    "name": "Angela Barton",
    "is_active": true,
    "company": "Magnafone",
    "address": "178 Howard Place, Gulf, Washington, 702",
    "registered": "2009-11-07T08:53:22 +08:00",
    "latitude": 19.793713,
    "longitude": 86.513373,
    "tags": [
        "enim",
        "aliquip",
        "qui"
    ],
    "id": 495
}'),
(
    '{
        "guid": "a1b2c3d4-e5f6-7g8h-9i0j-k1l2m3n4o5p6",
        "name": "John Doe",
        "is_active": false,
        "company": "TechCorp",
        "address": "123 Main Street, Springfield, IL, 62701",
        "registered": "2021-05-15T14:30:00 +00:00",
        "latitude": 39.7817,
        "longitude": -89.6501,
        "tags": [
            "tech",
            "innovation",
            "startup"
        ],
        "id": 236
    }'
),
(
    '{
        "guid": "b2c3d4e5-f6g7-h8i9-j0k1-l2m3n4o5p6q7",
        "name": "Jane Smith",
        "is_active": true,
        "company": "HealthPlus",
        "address": "456 Elm Street, Metropolis, NY, 10001",
        "registered": "2018-09-23T10:15:30 +00:00",
        "latitude": 40.7128,
        "longitude": -74.0060,
        "tags": [
            "health",
            "wellness",
            "fitness"
        ],
        "id": 1284
    }'
),
(
    '{
        "guid": "c3d4e5f6-g7h8-i9j0-k1l2-m3n4o5p6q7r8",
        "name": "Alice Johnson",
        "is_active": true,
        "company": "EduWorld",
        "address": "789 Oak Avenue, Gotham, CA, 90210",
        "registered": "2020-11-11T08:45:00 +00:00",
        "latitude": 34.0522,
        "longitude": -118.2437,
        "tags": [
            "education",
            "learning",
            "development"
        ],
        "id": 9637
    }'
),
(
    '{
        "guid": "g7h8i9j0-k1l2-m3n4-o5p6-q7r8s9t0u1v2",
        "name": "Sophia Martinez",
        "is_active": false,
        "company": "BioHealth",
        "address": "404 Cedar Street, Boston, MA, 02108",
        "registered": "2023-02-14T16:00:00 +00:00",
        "latitude": 42.3601,
        "longitude": -71.0589,
        "tags": [
            "biotech",
            "healthcare",
            "research"
        ],
        "id": 5342
    }'
),
(
    '{
        "guid": "h8i9j0k1-l2m3-n4o5-p6q7-r8s9t0u1v2w3",
        "name": "Olivia Taylor",
        "is_active": true,
        "company": "AgriCorp",
        "address": "505 Walnut Street, Des Moines, IA, 50309",
        "registered": "2020-08-30T07:15:00 +00:00",
        "latitude": 41.5868,
        "longitude": -93.6250,
        "tags": [
            "agriculture",
            "farming",
            "sustainability"
        ],
        "id": 8334
    }'
),
(
    '{
        "guid": "i9j0k1l2-m3n4-o5p6-q7r8-s9t0u1v2w3x4",
        "name": "Liam Johnson",
        "is_active": true,
        "company": "UrbanTech",
        "address": "606 Spruce Street, Seattle, WA, 98101",
        "registered": "2016-12-05T18:25:00 +00:00",
        "latitude": 47.6062,
        "longitude": -122.3321,
        "tags": [
            "urban",
            "technology",
            "development"
        ],
        "id": 7653
    }'
);
GO

-- Increase rowcount to enable use of JSON index
UPDATE STATISTICS contacts WITH ROWCOUNT = 10000;
GO

-- Show names and tags
SELECT JSON_VALUE(jdoc, '$.name') AS name, JSON_QUERY(jdoc, '$.tags') AS tags
FROM contacts;
GO

-- Show names and tags for certain tag values using a JSON index
SELECT JSON_VALUE(jdoc, '$.name') AS name, JSON_QUERY(jdoc, '$.tags') AS tags
FROM contacts
WHERE JSON_CONTAINS(jdoc, 'fitness', '$.tags[*]') = 1;
GO
