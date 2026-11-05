USE [zavacliniq];
GO

SET NOCOUNT ON;

/* 1) Core documents */
DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

INSERT INTO content.Document
(ExternalRef, Title, DocType, Specialty, DeviceModel, Language, ClinicScope, VersionLabel,
 EffectiveFrom, EffectiveTo, IsActive, ContentHash, CreatedUtc, UpdatedUtc)
VALUES
(NULL, N'Pediatric MRI Sedation SOP (v3.2)', N'SOP', N'Pediatrics', NULL, N'en', N'Clinic-IRV-01', N'v3.2', '2024-10-01', NULL, 1, NULL, @now, @now),
(NULL, N'Adult CT Contrast Protocol (v2.1)', N'Guideline', N'Radiology', NULL, N'en', NULL, N'v2.1', '2024-08-15', NULL, 1, NULL, @now, @now),
(NULL, N'Infection Control Policy - Outpatient', N'Policy', NULL, NULL, N'en', NULL, N'2024R', '2024-01-01', NULL, 1, NULL, @now, @now),
(NULL, N'Infusion Pump QS Guide (ACME X200)', N'Manual', N'General', N'X200', N'en', NULL, N'1.0', '2023-12-01', NULL, 1, NULL, @now, @now);
GO

/* 2) Symptom/Vital playbooks */
DECLARE @now_sym DATETIME2(3) = SYSUTCDATETIME();

INSERT INTO content.Document
(ExternalRef, Title, DocType, Specialty, DeviceModel, Language, ClinicScope, VersionLabel,
 EffectiveFrom, EffectiveTo, IsActive, ContentHash, CreatedUtc, UpdatedUtc)
VALUES
(NULL, N'Symptom Playbook: Chest Pain (Adult Outpatient)', N'Guideline', N'Cardiology', NULL, N'en', NULL, N'v1.0', '2025-01-01', NULL, 1, NULL, @now_sym, @now_sym),
(NULL, N'Symptom Playbook: Headache with Neurologic Signs', N'Guideline', N'Neurology', NULL, N'en', NULL, N'v1.0', '2025-01-01', NULL, 1, NULL, @now_sym, @now_sym),
(NULL, N'Vital-Based Escalation: Adult Outpatient', N'Policy', N'General', NULL, N'en', NULL, N'v1.0', '2025-01-01', NULL, 1, NULL, @now_sym, @now_sym),
(NULL, N'Medication Quick Reference: Contrast Allergy Premedication', N'Guideline', N'Radiology', NULL, N'en', NULL, N'v2.0', '2024-10-01', NULL, 1, NULL, @now_sym, @now_sym),
(NULL, N'Discharge Criteria: Post-Sedation Outpatient MRI', N'Policy', N'Pediatrics', NULL, N'en', N'Clinic-IRV-01', N'v3.2', '2024-10-01', NULL, 1, NULL, @now_sym, @now_sym),
(NULL, N'Symptom Playbook: Cough with Low SpO2 (Adult/Peds)', N'Guideline', N'Pulmonology', NULL, N'en', NULL, N'v1.0', '2025-01-01', NULL, 1, NULL, @now_sym, @now_sym),
(NULL, N'Symptom Playbook: Dehydration (Pediatric Outpatient)', N'Guideline', N'Pediatrics', NULL, N'en', NULL, N'v1.0', '2025-01-01', NULL, 1, NULL, @now_sym, @now_sym),
(NULL, N'Symptom Playbook: Head & Neck Pain (Adult Outpatient)', N'Guideline', N'Neurology', NULL, N'en', NULL, N'v1.0', '2025-01-01', NULL, 1, NULL, @now_sym, @now_sym);
GO
/* 3) Chunks for all docs */
INSERT INTO content.Chunk (DocumentId, ChunkOrd, ChunkText, TokenCount, Language, ClinicScope, CreatedUtc, UpdatedUtc)
SELECT d.DocumentId, v.ChunkOrd, v.ChunkText, v.TokenCount, N'en', v.ClinicScope, SYSUTCDATETIME(), SYSUTCDATETIME()
FROM (VALUES
-- Pediatric MRI Sedation SOP
(N'Pediatric MRI Sedation SOP (v3.2)',1,N'Pre-scan checklist: confirm fasting status, allergies, prior reactions to sedation. Obtain consent per clinic policy.',33,N'Clinic-IRV-01'),
(N'Pediatric MRI Sedation SOP (v3.2)',2,N'Dose guidance: use weight-based dosing; monitor oxygen saturation continuously; have reversal agents available.',26,N'Clinic-IRV-01'),
(N'Pediatric MRI Sedation SOP (v3.2)',3,N'Recovery: observe minimum 60 minutes post-procedure; discharge when vitals stable and airway maintained.',24,N'Clinic-IRV-01'),

-- Adult CT Contrast Protocol
(N'Adult CT Contrast Protocol (v2.1)',1,N'Indications for iodinated contrast: evaluate vasculature or suspected masses; consider renal function before administration.',31,NULL),
(N'Adult CT Contrast Protocol (v2.1)',2,N'Contraindications: severe prior reaction to contrast, unstable asthma; premedication protocol available if risk is moderate.',29,NULL),

-- Infection Control Policy
(N'Infection Control Policy - Outpatient',1,N'Hand hygiene: perform before and after patient contact; alcohol-based rub recommended unless visibly soiled.',24,NULL),
(N'Infection Control Policy - Outpatient',2,N'Isolation: apply contact precautions for suspected infectious diarrhea; clean high-touch surfaces between patients.',24,NULL),

-- Infusion Pump QS Guide
(N'Infusion Pump QS Guide (ACME X200)',1,N'Power-on and prime tubing per on-screen prompts; verify drug library profile and concentration before starting infusion.',28,NULL),
(N'Infusion Pump QS Guide (ACME X200)',2,N'Alarm recovery: check occlusion, air-in-line, or empty bag; follow clear-line procedure; document event in device log.',27,NULL),

-- Chest Pain Playbook
(N'Symptom Playbook: Chest Pain (Adult Outpatient)',1,N'Adult chest pain with HR > 100 or radiation to jaw/left arm: prioritize ischemia. Obtain ECG within 10 minutes and vitals; initiate aspirin if not contraindicated.',42,NULL),
(N'Symptom Playbook: Chest Pain (Adult Outpatient)',2,N'If chest pain + dyspnea + risk factors (DVT/PE): consider PE rule-out pathway. Assess Wells score; if high risk, arrange imaging per protocol.',36,NULL),
(N'Symptom Playbook: Chest Pain (Adult Outpatient)',3,N'Non-cardiac features (reproducible chest wall tenderness, positional pain): consider musculoskeletal or pericarditis; provide NSAID trial if not contraindicated.',33,NULL),

-- Headache Playbook
(N'Symptom Playbook: Headache with Neurologic Signs',1,N'Severe headache with neurologic deficits (weakness, aphasia, vision loss): rule out intracranial hemorrhage before aggressive BP reduction; arrange urgent imaging.',38,NULL),
(N'Symptom Playbook: Headache with Neurologic Signs',2,N'Thunderclap onset or worst-ever headache: activate emergent evaluation pathway. Screen for meningism and focal deficits; avoid delay in imaging.',33,NULL),
(N'Symptom Playbook: Headache with Neurologic Signs',3,N'Headache with BP ≥ 180/110 and confusion or visual changes: treat as hypertensive emergency per protocol; initiate IV agent and continuous BP monitoring.',34,NULL),

-- Vital Escalation
(N'Vital-Based Escalation: Adult Outpatient',1,N'Hypotension: SBP < 90 mmHg or MAP < 65 with HR > 120 → escalate. Start IV access, 500–1000 mL isotonic bolus unless contraindicated; recheck BP q5–10 min.',35,NULL),
(N'Vital-Based Escalation: Adult Outpatient',2,N'Hypoxemia: SpO2 < 92% on room air → apply supplemental oxygen; assess work of breathing; consider bronchodilator or further evaluation per pathway.',31,NULL),
(N'Vital-Based Escalation: Adult Outpatient',3,N'Febrile neutropenia: Temp ≥ 38.5°C with ANC low or unknown → start empiric broad-spectrum antibiotics within 60 minutes; follow sepsis screening.',34,NULL),

-- Contrast Allergy Premedication
(N'Medication Quick Reference: Contrast Allergy Premedication',1,N'History of moderate prior contrast reaction: consider premedication. Prednisone 50 mg PO at 13, 7, and 1 hour pre-contrast; diphenhydramine 50 mg PO/IV 1 hour pre.',39,NULL),
(N'Medication Quick Reference: Contrast Allergy Premedication',2,N'High-risk or uncontrolled asthma: defer contrast if unstable; discuss alternatives with radiology; if urgent, follow rapid premedication protocol per policy.',32,NULL),

-- Discharge Criteria
(N'Discharge Criteria: Post-Sedation Outpatient MRI',1,N'Observe minimum 60 minutes post‑sedation. Discharge only when airway reflexes intact, SpO2 stable on room air, and child can maintain posture appropriate for age.',37,N'Clinic-IRV-01'),
(N'Discharge Criteria: Post-Sedation Outpatient MRI',2,N'Discharge instructions: adult escort for 12–24 hours, fluids as tolerated, avoid hazardous activities for 24 hours; provide contact for delayed adverse events.',36,N'Clinic-IRV-01'),

-- Cough Playbook
(N'Symptom Playbook: Cough with Low SpO2 (Adult/Peds)',1,N'Persistent cough with fever and SpO2 < 92%: consider pneumonia pathway. Obtain vitals, assess for tachypnea; start oxygen and arrange imaging as indicated.',34,NULL),
(N'Symptom Playbook: Cough with Low SpO2 (Adult/Peds)',2,N'Wheezing with prolonged exhalation: consider bronchospasm. Trial short‑acting bronchodilator; reassess SpO2 and work of breathing after treatment.',33,NULL),
(N'Symptom Playbook: Cough with Low SpO2 (Adult/Peds)',3,N'Infant with cough and poor feeding plus retractions: evaluate for bronchiolitis severity; consider suctioning and hydration; escalate per pediatric criteria.',34,NULL),

-- Dehydration Playbook
(N'Symptom Playbook: Dehydration (Pediatric Outpatient)',1,N'Pediatric dehydration: signs include decreased tears, dry mucosa, delayed cap refill. If moderate/severe, start oral rehydration or IV isotonic bolus per weight.',36,NULL),
(N'Symptom Playbook: Dehydration (Pediatric Outpatient)',2,N'Reassessment: check weight change, urine output, and heart rate every 30–60 minutes; adjust fluid plan; consider antiemetic if vomiting persists.',33,NULL),

-- Head & Neck Pain Playbook
(N'Symptom Playbook: Head & Neck Pain (Adult Outpatient)',1,N'Sudden, severe unilateral head or neck pain ± worsening with neck movement, with any of: ipsilateral Horner’s syndrome, transient ischemic symptoms, posterior circulation signs (ataxia, vertigo, diplopia) → suspect cervical artery dissection. Arrange urgent CT or MR angiography of the head and neck; involve neurology/stroke team as per protocol.',38,NULL),
(N'Symptom Playbook: Head & Neck Pain (Adult Outpatient)',2,N'Headache with neck stiffness and fever ± photophobia, altered mental status, or seizure → red flag for meningitis/encephalitis. Initiate droplet precautions, obtain labs and blood cultures; perform head CT if indicated, then lumbar puncture without delay. Start empiric antibiotics and dexamethasone per policy.',40,NULL),
(N'Symptom Playbook: Head & Neck Pain (Adult Outpatient)',3,N'Headache + neck pain with blurry or double vision, papilledema, or focal deficits (SNNOOP10 red flags): obtain urgent non-contrast head CT. If CT negative but suspicion remains high, proceed to CT angiography of head/neck and/or lumbar puncture as per protocol.',34,NULL),
(N'Symptom Playbook: Head & Neck Pain (Adult Outpatient)',4,N'Sudden “thunderclap” head/neck pain (peaks within minutes) → treat as subarachnoid haemorrhage until proven otherwise. Perform emergent non-contrast head CT (ideally within 6 hours). If CT is negative and suspicion persists, pursue lumbar puncture and/or CT angiography per local pathway.',36,NULL),
(N'Symptom Playbook: Head & Neck Pain (Adult Outpatient)',5,N'Occipital headache/neck pain after minor trauma, sudden head turning, or exertion with posterior circulation symptoms (dysarthria, ataxia, vertigo, diplopia) → consider vertebral artery dissection. Order CTA/MRA head & neck; consult neurology/stroke for antithrombotic strategy.',35,NULL)
) AS v(Title,ChunkOrd,ChunkText,TokenCount,ClinicScope)
JOIN content.Document d ON d.Title = v.Title;
GO

PRINT('Seed complete (no IF NOT EXISTS).');
