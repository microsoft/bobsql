$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\00-config.ps1"
Import-Module SqlServer -ErrorAction Stop

$account = Invoke-Az @('account', 'show', '--output', 'json')
if ($account.id -ne $SubscriptionId) {
    throw 'The configured subscription must match the currently signed-in Azure CLI subscription.'
}
if ($SqlServerName -notlike 'sql-caldova-network-*' -or $CaldovaDatabase -ne 'caldova-scheduling') {
    throw 'These read-only fixtures and baseline comparison target the Grow sql-caldova-network-* server and databases.'
}
$pool = Invoke-Az @('sql', 'elastic-pool', 'show', '--resource-group', $ResourceGroup,
    '--server', $SqlServerName, '--name', $ElasticPoolName, '--output', 'json')
foreach ($name in @($CaldovaDatabase) + @($AcquiredDatabases | ForEach-Object { $_.Name })) {
    $database = Invoke-Az @('sql', 'db', 'show', '--resource-group', $ResourceGroup,
        '--server', $SqlServerName, '--name', $name, '--output', 'json')
    if ($database.status -ne 'Online' -or $database.elasticPoolId -ne $pool.id) {
        throw "$name must be Online in $ElasticPoolName before these read-only SQL checks."
    }
}

$viewFile = Join-Path $PSScriptRoot '..\..\sql\02-network-view.sql'
$definition = Get-Content $viewFile -Raw
$match = [regex]::Match($definition, '(?s)CREATE OR ALTER VIEW network\.AppointmentAvailability AS\s*(SELECT.*?)\s*;\s*GO')
if (-not $match.Success) { throw 'Cannot extract the canonical view SELECT without executing DDL.' }
$body = $match.Groups[1].Value
$token = Invoke-Az @('account', 'get-access-token', '--resource', 'https://database.windows.net/', '--output', 'json')
$options = @{
    ServerInstance = $SqlServerFqdn; Database = $CaldovaDatabase; AccessToken = $token.accessToken
    ConnectionTimeout = 90; QueryTimeout = 120; Encrypt = 'Mandatory'
    AbortOnError = $true; OutputSqlErrors = $true; ErrorAction = 'Stop'
}

function Test-EquivalentRows {
    param([string]$Prefix, [string]$Candidate, [string]$Expected, [int]$ExpectedCount = -1, [string]$Label)
    $query = @"
WITH $Prefix
Candidate AS ($Candidate),
Expected AS ($Expected)
SELECT
    (SELECT COUNT(*) FROM Candidate) AS CandidateRows,
    (SELECT COUNT(*) FROM Expected) AS ExpectedRows,
    (SELECT COUNT(*) FROM (SELECT * FROM Candidate EXCEPT SELECT * FROM Expected) AS d) AS CandidateOnly,
    (SELECT COUNT(*) FROM (SELECT * FROM Expected EXCEPT SELECT * FROM Candidate) AS d) AS ExpectedOnly,
    (SELECT COUNT(*) FROM (
        SELECT ProviderKey, SlotId FROM Candidate
        GROUP BY ProviderKey, SlotId HAVING COUNT(*) > 1
    ) AS d) AS DuplicateSlots;
"@
    $result = Invoke-Sqlcmd @options -Query $query
    if ($null -eq $result -or $result.CandidateRows -ne $result.ExpectedRows -or
        $result.CandidateOnly -ne 0 -or $result.ExpectedOnly -ne 0 -or $result.DuplicateSlots -ne 0 -or
        ($ExpectedCount -ge 0 -and $result.CandidateRows -ne $ExpectedCount)) {
        throw "$Label failed: $($result | ConvertTo-Json -Compress)"
    }
    Write-Host "PASS: $Label ($($result.CandidateRows) rows, all eight columns equivalent, no duplicate provider slots)."
}

$fixtures = @"
Directory (ProviderKey, ProviderName, ClinicId, Location, IsNetworkMember) AS (
    SELECT * FROM (VALUES
        ('caldova', 'Caldova', 1, 'C-A', 1),
        ('caldova', 'Caldova', 2, 'C-B', 1),
        ('caldova', 'Caldova', 3, 'C-empty', 1),
        ('northbrook', 'Northbrook', 1, 'N-A', 1),
        ('northbrook', 'Northbrook', 2, 'N-inactive', 0),
        ('ridgeview', 'Ridgeview', 1, 'R-A', 1),
        ('ridgeview', 'Ridgeview', 2, 'R-booked', 1),
        ('unknown', 'Unknown', 1, 'Unknown', 1)
    ) AS v (ProviderKey, ProviderName, ClinicId, Location, IsNetworkMember)
),
CaldovaSlots (SlotId, ClinicId, Clinician, Specialty, SlotStart, DurationMinutes, IsBooked) AS (
    SELECT * FROM (VALUES
        (1, 1, 'C-1', 'Cardiology', '2030-01-01T09:00:00', 20, 0),
        (2, 1, 'C-booked', 'Cardiology', '2030-01-01T10:00:00', 30, 1),
        (3, 2, 'C-2', 'Orthopedics', '2025-01-01T09:00:00', 40, 0),
        (4, 1, 'C-4', 'Pediatrics', '2030-01-01T11:00:00', 50, 0),
        (5, 9, 'C-orphan', 'Cardiology', '2030-01-01T12:00:00', 60, 0)
    ) AS v (SlotId, ClinicId, Clinician, Specialty, SlotStart, DurationMinutes, IsBooked)
),
NorthbrookSlots (SlotId, ClinicId, Clinician, Specialty, SlotStart, DurationMinutes, IsBooked) AS (
    SELECT * FROM (VALUES
        (1, 1, 'N-1', 'Pediatrics', '2030-02-01T09:00:00', 25, 0),
        (2, 2, 'N-inactive', 'Cardiology', '2030-02-01T10:00:00', 35, 0),
        (3, 1, 'N-booked', 'Cardiology', '2030-02-01T11:00:00', 45, 1)
    ) AS v (SlotId, ClinicId, Clinician, Specialty, SlotStart, DurationMinutes, IsBooked)
),
RidgeviewSlots (SlotId, ClinicId, Clinician, Specialty, SlotStart, DurationMinutes, IsBooked) AS (
    SELECT * FROM (VALUES
        (1, 1, 'R-1', 'Cardiology', '2030-03-01T09:00:00', 15, 0),
        (2, 1, 'R-2', 'Oncology', '2030-03-01T10:00:00', 55, 0),
        (3, 2, 'R-booked', 'Cardiology', '2030-03-01T11:00:00', 65, 1)
    ) AS v (SlotId, ClinicId, Clinician, Specialty, SlotStart, DurationMinutes, IsBooked)
),
"@
$fixtureBody = $body.Replace('[northbrook-scheduling].dbo.AppointmentSlot', 'NorthbrookSlots').
    Replace('[ridgeview-scheduling].dbo.AppointmentSlot', 'RidgeviewSlots').
    Replace('dbo.AppointmentSlot', 'CaldovaSlots').Replace('network.ProviderClinic', 'Directory')
$expected = @"
SELECT * FROM (VALUES
    ('caldova', 'Caldova', 1, 'C-A', 'C-1', 'Cardiology', '2030-01-01T09:00:00', 20),
    ('caldova', 'Caldova', 3, 'C-B', 'C-2', 'Orthopedics', '2025-01-01T09:00:00', 40),
    ('caldova', 'Caldova', 4, 'C-A', 'C-4', 'Pediatrics', '2030-01-01T11:00:00', 50),
    ('northbrook', 'Northbrook', 1, 'N-A', 'N-1', 'Pediatrics', '2030-02-01T09:00:00', 25),
    ('ridgeview', 'Ridgeview', 1, 'R-A', 'R-1', 'Cardiology', '2030-03-01T09:00:00', 15),
    ('ridgeview', 'Ridgeview', 2, 'R-A', 'R-2', 'Oncology', '2030-03-01T10:00:00', 55)
) AS v (ProviderKey, ProviderName, SlotId, Location, Clinician, Specialty, SlotStart, DurationMinutes)
"@
Test-EquivalentRows -Prefix $fixtures -Candidate $fixtureBody -Expected $expected -ExpectedCount 6 `
    -Label 'Canonical JOIN-only fixtures: colliding IDs, multiple clinics, empty schedules, excluded members/bookings, past slots'

$baseline = @"
SELECT p.ProviderKey, p.ProviderName, s.SlotId, p.Location,
       s.Clinician, s.Specialty, s.SlotStart, s.DurationMinutes
FROM network.ProviderClinic AS p
JOIN dbo.AppointmentSlot AS s ON s.ClinicId = p.ClinicId
WHERE p.ProviderKey = N'caldova' AND p.IsNetworkMember = 1 AND s.IsBooked = 0
UNION ALL
SELECT p.ProviderKey, p.ProviderName, s.SlotId, p.Location,
       s.Clinician, s.Specialty, s.SlotStart, s.DurationMinutes
FROM network.ProviderClinic AS p
JOIN [northbrook-scheduling].dbo.AppointmentSlot AS s ON s.ClinicId = p.ClinicId
WHERE p.ProviderKey = N'northbrook' AND p.IsNetworkMember = 1 AND s.IsBooked = 0
UNION ALL
SELECT p.ProviderKey, p.ProviderName, s.SlotId, p.Location,
       s.Clinician, s.Specialty, s.SlotStart, s.DurationMinutes
FROM network.ProviderClinic AS p
JOIN [ridgeview-scheduling].dbo.AppointmentSlot AS s ON s.ClinicId = p.ClinicId
WHERE p.ProviderKey = N'ridgeview' AND p.IsNetworkMember = 1 AND s.IsBooked = 0
"@
Test-EquivalentRows -Candidate $body -Expected $baseline -Label 'Live native reads versus the previous view semantics'
Write-Host 'No view, users, permissions, tables, data, or bookings were changed. These checks use the deployment identity, not the app identity.'
