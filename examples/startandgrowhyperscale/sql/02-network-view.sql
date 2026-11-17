-- Connect directly to caldova-scheduling. All three databases must be pooled.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW network.AppointmentAvailability AS
SELECT p.ProviderKey, p.ProviderName,
       COALESCE(c.SlotId, n.SlotId, r.SlotId) AS SlotId, p.Location,
       COALESCE(c.Clinician, n.Clinician, r.Clinician) AS Clinician,
       COALESCE(c.Specialty, n.Specialty, r.Specialty) AS Specialty,
       COALESCE(c.SlotStart, n.SlotStart, r.SlotStart) AS SlotStart,
       COALESCE(c.DurationMinutes, n.DurationMinutes, r.DurationMinutes) AS DurationMinutes
FROM network.ProviderClinic AS p
LEFT JOIN dbo.AppointmentSlot AS c
    ON p.ProviderKey = N'caldova' AND c.ClinicId = p.ClinicId AND c.IsBooked = 0
LEFT JOIN [northbrook-scheduling].dbo.AppointmentSlot AS n
    ON p.ProviderKey = N'northbrook' AND n.ClinicId = p.ClinicId AND n.IsBooked = 0
LEFT JOIN [ridgeview-scheduling].dbo.AppointmentSlot AS r
    ON p.ProviderKey = N'ridgeview' AND r.ClinicId = p.ClinicId AND r.IsBooked = 0
WHERE p.IsNetworkMember = 1
  AND COALESCE(c.SlotId, n.SlotId, r.SlotId) IS NOT NULL;
GO
