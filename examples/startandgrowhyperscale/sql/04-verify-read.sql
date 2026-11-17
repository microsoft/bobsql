-- Connect directly to caldova-scheduling as the application identity.
SELECT ORIGINAL_LOGIN() AS LoginName, USER_NAME() AS DatabaseUser, DB_NAME() AS ConnectedDatabase;

SELECT ProviderKey, COUNT_BIG(*) AS OpenSlots
FROM network.AppointmentAvailability
GROUP BY ProviderKey;

SELECT TOP (10) ProviderKey, ProviderName, SlotId, Location, Clinician, Specialty, SlotStart, DurationMinutes
FROM network.AppointmentAvailability
WHERE Specialty = N'Cardiology' AND SlotStart >= SYSUTCDATETIME()
ORDER BY SlotStart, ProviderKey, SlotId;

-- After booking, check the precise provider/SlotId shown by the app directly.
-- IsBooked = 1 confirms the state, not who booked it after an interrupted response.
