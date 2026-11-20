USE CustomerServiceDesk;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

INSERT dbo.Customers (CustomerCode, DisplayName, Email, Phone)
SELECT CONCAT('DEMO-C', RIGHT(CONCAT('000', value), 3)),
    CONCAT(N'Demo Customer ', RIGHT(CONCAT('000', value), 3)),
    CONCAT('customer', RIGHT(CONCAT('000', value), 3), '@example.test'),
    CONCAT('+1 202-555-', RIGHT(CONCAT('0000', 99 + value), 4))
FROM GENERATE_SERIES(1, 100) AS g
WHERE NOT EXISTS (SELECT 1 FROM dbo.Customers AS c
    WHERE c.CustomerCode = CONCAT('DEMO-C', RIGHT(CONCAT('000', g.value), 3)));

DECLARE @Topics TABLE
(
    TopicId int PRIMARY KEY, Topic varchar(40), Product nvarchar(80),
    Title nvarchar(150), Description nvarchar(1500), Resolution nvarchar(1500)
);
INSERT @Topics VALUES
(1, 'wifi-dropouts', N'Home Router', N'Wireless connection drops during video meetings',
 N'The laptop repeatedly loses its wireless network while video calls are active. Wired devices stay online. The router is close to neighboring wireless networks.',
 N'A wireless scan showed interference on the crowded channel. Selected a quieter channel, updated router firmware, and confirmed a stable video call.'),
(2, 'password-reset', N'Customer Portal', N'Password reset link expires before sign-in',
 N'The customer cannot sign in after forgetting the password. Reset emails arrive but the link says it is expired or has already been used.',
 N'Invalidated older reset requests and issued one fresh link. Opened it in a private browser session and successfully set a new password.'),
(3, 'duplicate-charge', N'Billing', N'Two card charges appear for the same purchase',
 N'The payment statement shows the same order amount twice after checkout was retried. The customer needs to know whether a duplicate payment was captured.',
 N'Compared payment references and confirmed one captured payment and one authorization hold. Released the redundant authorization and explained the bank settlement timeline.'),
(4, 'printer-offline', N'Office Printer', N'Network printer is offline despite being powered on',
 N'The print queue reports the device offline. Printing stopped after the network restarted although the printer display indicates that it is connected.',
 N'The printer received a different network address. Reserved its address in DHCP, updated the print queue port, and printed a test page.'),
(5, 'battery-drain', N'Notebook', N'Notebook battery drains rapidly while asleep',
 N'The fully charged notebook has very little battery remaining the next morning even with the lid closed. Battery diagnostics show no hardware fault.',
 N'Identified a background synchronization task preventing sleep. Updated the power driver, disabled the unnecessary wake task, and verified overnight power usage.'),
(6, 'delivery-delay', N'Order Tracking', N'Parcel tracking has stopped updating',
 N'The delivery date has passed and tracking still shows the parcel at a sorting hub. The customer wants a reliable delivery estimate rather than another generic notification.',
 N'Opened a carrier trace, confirmed the hub backlog, and arranged a priority delivery slot. Shared the revised tracking milestone with the customer.'),
(7, 'refund-missing', N'Billing', N'Approved refund is missing from the bank statement',
 N'A returned order has been approved for a refund but the credit is not visible on the payment account. The customer has already received a return confirmation.',
 N'Confirmed the refund transaction was submitted to the original payment method. Supplied its reference number and explained the remaining bank processing period.'),
(8, 'bluetooth-audio', N'Wireless Headset', N'Headset audio becomes distorted during calls',
 N'Music plays clearly but speech sounds muffled when the microphone is enabled in a meeting. The problem occurs with a paired wireless headset.',
 N'The operating system had selected the low-bandwidth hands-free audio profile. Selected the proper audio device and updated the Bluetooth driver.'),
(9, 'sync-conflict', N'Cloud Drive', N'Files keep producing conflicting synchronized copies',
 N'Edits made on two computers generate multiple conflict copies. One computer has been offline and the customer is unsure which document contains the latest changes.',
 N'Preserved both versions, compared their changes, and merged the final document. Cleared the stale synchronization cache and verified updates on both computers.'),
(10, 'subscription-cancel', N'Subscriptions', N'Subscription renewal continues after cancellation request',
 N'The customer believes automatic renewal was disabled but received another renewal notice. They need confirmation of the cancellation effective date and billing status.',
 N'Checked the subscription event history, disabled automatic renewal on the correct plan, and issued a cancellation confirmation with the service end date.'),
(11, 'vpn-connection', N'Secure Access', N'VPN tunnel fails after a client update',
 N'The remote access client cannot establish a secure tunnel. Internet browsing works but the VPN reports a certificate or negotiation error after an update.',
 N'Removed the expired client certificate, installed the current organization certificate, and refreshed the VPN profile. Verified access through the secure tunnel.'),
(12, 'screen-flicker', N'External Monitor', N'External display flickers when connected through a dock',
 N'The monitor intermittently blanks when the notebook is attached to a docking station. The notebook display remains stable and the issue worsens at high refresh rates.',
 N'Updated dock firmware and replaced a cable that did not support the requested bandwidth. Selected a supported refresh rate and confirmed stable display output.'),
(13, 'account-lockout', N'Customer Portal', N'Account locks repeatedly despite a correct password',
 N'The customer can unlock the account but it becomes locked again shortly afterward. They are entering the correct current password on their main device.',
 N'A second device was retrying a stored old password. Removed its cached credentials, updated the saved password, and confirmed repeated lockouts stopped.'),
(14, 'damaged-item', N'Returns', N'Item arrived damaged in transit',
 N'The shipping box is visibly crushed and the product cannot be used safely. The customer needs a replacement without waiting for a lengthy return inspection.',
 N'Recorded the synthetic damage assessment, approved a prepaid return, and dispatched a replacement from available inventory. Provided return packaging instructions.'),
(15, 'mobile-notifications', N'Mobile App', N'Push notifications arrive late or not at all',
 N'Important app alerts do not appear until the customer opens the application. Notifications are enabled inside the app, but background delivery is unreliable.',
 N'The mobile operating system was restricting background activity. Allowed notifications and background data, excluded the app from battery optimization, and tested a new alert.'),
(16, 'storage-full', N'Cloud Drive', N'Cloud storage reports full after large files were removed',
 N'The customer deleted old files but the storage quota still reports no available space. New uploads fail even though the visible folders are much smaller.',
 N'The recycle bin and retained file versions still counted against the quota. Reviewed retention requirements, cleared eligible deleted items, and confirmed available space.'),
(17, 'checkout-error', N'Online Store', N'Checkout fails when applying a promotional code',
 N'The shopping cart works until a discount code is entered. Checkout then displays a validation error, and the customer cannot complete a qualifying purchase.',
 N'The promotion excluded one item category and conflicted with an existing discount. Applied the eligible promotion to the supported items and completed checkout.'),
(18, 'device-overheating', N'Notebook', N'Notebook fan runs constantly and performance slows',
 N'The device becomes unusually warm during ordinary office work. The fan runs loudly and applications slow down even when only a few windows are open.',
 N'Found obstructed ventilation and a background indexing task consuming processor time. Cleared the vents, completed the task, and verified normal operating temperature.'),
(19, 'invoice-details', N'Billing', N'Invoice needs corrected business information',
 N'The customer needs the purchase invoice to show the correct organization name and purchase reference. The order and payment are valid but the accounting document is incomplete.',
 N'Validated the requested synthetic organization details, issued a corrected invoice linked to the original order, and retained the original financial audit trail.'),
(20, 'mfa-device', N'Secure Access', N'Cannot approve multifactor sign-in after replacing a phone',
 N'The customer has a new phone and no longer receives authentication approvals on the old device. Their password works, but the second verification step prevents sign-in.',
 N'Completed the approved account recovery process, revoked the old authenticator registration, and enrolled the replacement phone with new recovery codes.');

INSERT dbo.Cases
    (SeedKey, CustomerId, Title, Description, Resolution, Topic, Status, Priority, Details, CreatedAt, UpdatedAt)
SELECT CONCAT('DEMO-CASE-', RIGHT(CONCAT('0000', n.CaseNumber), 4)), c.CustomerId,
    CONCAT(t.Title, N' - incident ', g.value),
    CONCAT(t.Description, N' Reported from a ',
        CASE g.value % 4 WHEN 0 THEN N'home office' WHEN 1 THEN N'small branch'
            WHEN 2 THEN N'shared workspace' ELSE N'remote work location' END,
        N'. The issue ', CASE g.value % 3 WHEN 0 THEN N'appeared after a recent change'
            WHEN 1 THEN N'occurs intermittently' ELSE N'can be reproduced consistently' END, N'.'),
    CASE WHEN g.value % 10 < 7 THEN t.Resolution ELSE NULL END,
    t.Topic, CASE WHEN g.value % 10 < 7 THEN 'Resolved' WHEN g.value % 10 = 7 THEN 'Open' ELSE 'InProgress' END,
    CASE WHEN g.value % 5 = 0 THEN 'High' WHEN g.value % 5 = 1 THEN 'Low' ELSE 'Normal' END,
    (SELECT t.Product AS product,
        CASE g.value % 3 WHEN 0 THEN 'web' WHEN 1 THEN 'phone' ELSE 'chat' END AS channel,
        CASE g.value % 3 WHEN 0 THEN 'Windows 11' WHEN 1 THEN 'Android' ELSE 'iOS' END AS device,
        CASE g.value % 4 WHEN 0 THEN 'West' WHEN 1 THEN 'East' WHEN 2 THEN 'Central' ELSE 'North' END AS region,
        g.value AS incident, 'synthetic-v1' AS seedVersion
     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    DATEADD(HOUR, -n.CaseNumber, CONVERT(datetime2(0), '2026-11-01T12:00:00')),
    DATEADD(HOUR, -n.CaseNumber + 2, CONVERT(datetime2(0), '2026-11-01T12:00:00'))
FROM @Topics AS t CROSS JOIN GENERATE_SERIES(1, 50) AS g
CROSS APPLY (SELECT (t.TopicId - 1) * 50 + g.value AS CaseNumber) AS n
INNER JOIN dbo.Customers AS c ON c.CustomerCode =
    CONCAT('DEMO-C', RIGHT(CONCAT('000', (n.CaseNumber - 1) % 100 + 1), 3))
WHERE NOT EXISTS (SELECT 1 FROM dbo.Cases AS existing
    WHERE existing.SeedKey = CONCAT('DEMO-CASE-', RIGHT(CONCAT('0000', n.CaseNumber), 4)));

MERGE dbo.PreparedSearches AS existing
USING (VALUES
    ('wifi', N'Colleagues freeze on Zoom; Ethernet fixes it.', 'wifi-dropouts'),
    ('payment', N'My wallet took a double hit.', 'duplicate-charge'),
    ('printer', N'No paper after rebooting the router.', 'printer-offline'),
    ('refund', N'Money sent back; balance unchanged.', 'refund-missing'),
    ('mfa', N'New handset; stuck at the extra login challenge.', 'mfa-device'),
    ('quota', N'Emptied digital cabinet, still no room.', 'storage-full')
) AS s(SearchCode, SearchText, ExpectedTopic)
ON existing.SearchCode = s.SearchCode
WHEN MATCHED AND (existing.SearchText <> s.SearchText OR existing.ExpectedTopic <> s.ExpectedTopic)
    THEN UPDATE SET SearchText = s.SearchText, ExpectedTopic = s.ExpectedTopic
WHEN NOT MATCHED THEN INSERT (SearchCode, SearchText, ExpectedTopic)
    VALUES (s.SearchCode, s.SearchText, s.ExpectedTopic);

SELECT (SELECT COUNT(*) FROM dbo.Customers) AS Customers,
       (SELECT COUNT(*) FROM dbo.Cases) AS Cases,
       (SELECT COUNT(*) FROM dbo.PreparedSearches) AS PreparedSearches;
