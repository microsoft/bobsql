/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   reseed-notes.sql : TARGETED rebuild of clinical.ClinicalNote ONLY.

   Rebuilds the clinical-note corpus with the decorrelated, condition-anchored
   generator (fixes the ~95%-duplicate seed), then leaves an EMPTY
   clinical.ClinicalNoteEmbeddings table ready for the overnight driver
   deploy/generate-embeddings.ps1. Patients / encounters / labs / meds are
   left UNTOUCHED (a full 05-seed re-run would reshuffle NEWID-based patient
   names + demographics, so we deliberately do not do that here).

   NOTE-GENERATION BLOCK BELOW IS KEPT IN SYNC WITH 05-seed.sql section 10.
   If you change the generator, change it in both places (05-seed.sql is the
   canonical seed; this file is a live-DB maintenance helper).

   RUN (passwordless, Entra token):
     $tk = (az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv)
     & '<kit>\sqlsimtools\sqlsim\build\x64\Release\sqlsim.exe' `
         -S collierhealth-17.database.windows.net -d wardgeneral -T $tk -N s `
         -i '<kit>\presentations\hyperscale-developer\build\sql\..\..\build\sql\reseed-notes.sql'

   THEN (async, resumable, safe in the background):
     & '<kit>\presentations\hyperscale-developer\build\deploy\generate-embeddings.ps1'
   ...which finishes by (re)creating the DiskANN vector index (>= 100 notes).

   All data is synthetic — no real PHI.
   ============================================================================ */
SET NOCOUNT ON;
GO

/* ---- 1. Release the embeddings FK + DiskANN index, drop the companion table -- */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'VIX_ClinicalNoteEmbeddings_Embedding')
    DROP INDEX VIX_ClinicalNoteEmbeddings_Embedding ON clinical.ClinicalNoteEmbeddings;
IF OBJECT_ID('clinical.ClinicalNoteEmbeddings', 'U') IS NOT NULL
    DROP TABLE clinical.ClinicalNoteEmbeddings;
GO

/* ---- 2. Clear the notes (now unreferenced) ---------------------------------- */
TRUNCATE TABLE clinical.ClinicalNote;
GO

/* ---- 3. Regenerate notes (SYNC WITH 05-seed.sql section 10) ------------------ */
PRINT N'--- clinical.ClinicalNote (targeted re-seed) ---';
INSERT INTO clinical.ClinicalNote
    (EncounterId, AuthorProviderId, NoteType, NoteText, CreatedAt)
SELECT
    e.EncounterId,
    e.AttendingProviderId,
    CHOOSE((x.r_type % 3) + 1, N'Progress', N'Consult', N'Discharge'),
    CONCAT(
        N'Subjective: Patient reports ',
        CHOOSE(x.cond + 1,
            CHOOSE((x.r_sub % 6) + 1, N'an incidental severely elevated blood-pressure reading found at a routine visit, ', N'a throbbing headache with home readings persistently above goal, ', N'blurred vision and epistaxis with a markedly elevated pressure at triage, ', N'chest discomfort and dyspnea in the setting of very high blood pressure, ', N'symptoms after running out of antihypertensive medications weeks ago, ', N'dizziness and palpitations with labile home blood-pressure readings, '),
            CHOOSE((x.r_sub % 6) + 1, N'increased thirst, polyuria, and fatigue with very high home glucose readings, ', N'nausea, vomiting, and abdominal pain with deep rapid breathing, ', N'confusion and lethargy with profoundly elevated blood glucose, ', N'a painful, slow-healing foot ulcer with surrounding redness, ', N'recurrent hypoglycemic episodes after a recent insulin adjustment, ', N'an incidentally elevated glucose found on routine screening, '),
            CHOOSE((x.r_sub % 6) + 1, N'progressive dyspnea on exertion, orthopnea, and bilateral leg swelling, ', N'acute severe breathlessness with pink frothy sputum at rest, ', N'a three-kilogram weight gain over the week with worsening edema, ', N'fatigue and early satiety with increasing abdominal distension, ', N'paroxysmal nocturnal dyspnea requiring several pillows to sleep, ', N'worsening swelling after dietary indiscretion and missed diuretic doses, '),
            CHOOSE((x.r_sub % 6) + 1, N'fevers, chills, and a productive cough with green sputum, ', N'pleuritic chest pain with shortness of breath and subjective fevers, ', N'worsening cough and breathlessness with new confusion, ', N'cough and fever shortly after a recent hospitalization, ', N'sudden high fever and rigors with rapid breathing, ', N'a gradual cough and malaise with reduced appetite over a week, '),
            CHOOSE((x.r_sub % 6) + 1, N'dysuria, urinary frequency, and suprapubic discomfort, ', N'flank pain, fever, and rigors with nausea, ', N'burning with urination and new urinary urgency with malaise, ', N'foul-smelling urine and new confusion at home, ', N'urinary symptoms in the setting of a chronic indwelling catheter, ', N'lower abdominal pain and blood in the urine with frequency, '),
            CHOOSE((x.r_sub % 6) + 1, N'periumbilical pain migrating to the right lower quadrant with nausea, ', N'sharp right lower quadrant abdominal pain with anorexia and low-grade fever, ', N'diffuse abdominal pain with high fever and rigidity, ', N'right lower quadrant pain with repeated vomiting over the past day, ', N'worsening abdominal pain now on the first post-operative day, ', N'intermittent right-sided abdominal pain over several days, '),
            CHOOSE((x.r_sub % 6) + 1, N'crushing substernal chest pressure radiating to the left arm and jaw with diaphoresis, ', N'exertional chest tightness relieved by rest, consistent with stable angina, ', N'pleuritic, positional chest pain that improves when leaning forward, ', N'sharp left-sided chest pain reproducible on palpation of the chest wall, ', N'burning retrosternal discomfort worse after meals and when lying flat, ', N'sudden tearing chest pain radiating to the back between the shoulder blades, '),
            CHOOSE((x.r_sub % 6) + 1, N'a transient loss of consciousness while standing, with rapid full recovery, ', N'a syncopal episode preceded by palpitations and chest discomfort, ', N'lightheadedness and one witnessed fainting episode without warning, ', N'a loss of consciousness during exertion with slow recovery, ', N'recurrent fainting when rising from a seated position, ', N'a brief blackout after prolonged standing in a warm room, '),
            CHOOSE((x.r_sub % 6) + 1, N'sudden right-sided weakness and slurred speech noted on waking, ', N'acute facial droop and difficulty finding words witnessed by family, ', N'transient right-arm weakness that resolved within the hour, ', N'a sudden severe headache with neck stiffness and vomiting, ', N'acute vertigo, imbalance, and double vision, ', N'progressive left-sided numbness and confusion over hours, '),
            CHOOSE((x.r_sub % 6) + 1, N'increased dyspnea, wheeze, and a change in sputum color and volume, ', N'severe breathlessness with accessory muscle use and difficulty speaking, ', N'worsening breathlessness and cough despite home inhaler use, ', N'progressive dyspnea after a recent upper respiratory infection, ', N'wheezing and chest tightness with reduced exercise tolerance, ', N'increasing cough and sputum with a low-grade fever, ')),
        CHOOSE((x.r_hpi % 4) + 1,
            N'with a gradual progression over several days. ',
            N'with an abrupt onset that peaked within hours. ',
            N'following an intermittent course that is worse in the evenings. ',
            N'with no clear precipitating factors and no prior similar episodes. '),
        N'Pain scored ', v.pain, N' out of 10. ',
        CHOOSE((x.r_pmh % 4) + 1,
            N'Adherent to home medications with no new agents or supplements. ',
            N'Reports occasional missed doses of maintenance therapy. ',
            N'Recently started a new medication prescribed by an outside provider. ',
            N'Takes only as-needed analgesics at home. '),
        CHOOSE((x.r_fh % 4) + 1,
            N'Family history significant for premature coronary artery disease. ',
            N'Family history notable for type 2 diabetes and stroke. ',
            N'No significant family history elicited. ',
            N'Family history of malignancy in a first-degree relative. '),
        CHAR(13), CHAR(10),
        N'Objective: T ', v.tempInt, N'.', v.tempTenth,
        N'C, HR ', v.hr,
        N', BP ', v.bpSys, N'/', v.bpDia,
        N', RR ', v.rr,
        N', SpO2 ', v.spo2,
        N'% on room air. ',
        CHOOSE((x.r_gen % 4) + 1,
            N'Patient appears comfortable, in no acute distress. ',
            N'Patient appears fatigued but interactive and cooperative. ',
            N'Patient is ill-appearing but hemodynamically stable. ',
            N'Patient is alert and in mild distress. '),
        N'HEENT atraumatic and normocephalic, mucous membranes moist; neck supple without JVD. ',
        CHOOSE((x.r_card % 4) + 1,
            N'Cardiac exam regular rate and rhythm without murmurs, rubs, or gallops. ',
            N'Cardiac exam with a soft II/VI systolic ejection murmur at the base. ',
            N'Cardiac rhythm irregularly irregular, consistent with atrial fibrillation. ',
            N'Tachycardic but regular, with no appreciable murmur. '),
        CHOOSE((x.r_lung % 4) + 1,
            N'Lungs clear to auscultation bilaterally without rales or wheezing. ',
            N'Bibasilar crackles noted, worse on the right. ',
            N'Scattered expiratory wheezes throughout both lung fields. ',
            N'Decreased breath sounds at the right base. '),
        CHOOSE((x.r_abd % 3) + 1,
            N'Abdomen soft, non-tender, with normoactive bowel sounds. ',
            N'Abdomen with right lower quadrant tenderness and voluntary guarding. ',
            N'Abdomen mildly distended, non-tender, without rebound. '),
        CHOOSE((x.r_ext % 3) + 1,
            N'Extremities warm and well perfused with 2+ pulses and no edema. ',
            N'Bilateral lower extremity pitting edema to the knees. ',
            N'Unilateral calf swelling and tenderness noted. '),
        CASE WHEN x.cond = 8
             THEN N'Neurologic exam notable for right-sided facial droop, pronator drift, and dysarthria. '
             ELSE N'Neurologic exam grossly intact, alert and oriented to person, place, time, and situation. '
        END,
        CHAR(13), CHAR(10),
        N'Assessment: ',
        CHOOSE(x.cond + 1,
            CHOOSE((x.r_assess % 6) + 1, N'Hypertensive emergency with acute end-organ involvement; admitted for IV therapy. ', N'Hypertensive urgency without end-organ damage; oral agents up-titrated. ', N'Newly diagnosed stage 2 essential hypertension; combination therapy started. ', N'Uncontrolled hypertension from medication nonadherence; regimen restarted. ', N'White-coat hypertension; ambulatory monitoring arranged without acute treatment. ', N'Secondary hypertension suspected; workup for renal and endocrine causes begun. '),
            CHOOSE((x.r_assess % 6) + 1, N'Diabetic ketoacidosis; started on an insulin infusion and fluid resuscitation. ', N'Hyperosmolar hyperglycemic state; aggressive rehydration and insulin begun. ', N'Type 2 diabetes, markedly uncontrolled, without acute metabolic decompensation. ', N'Diabetic foot ulcer with local infection; antibiotics and wound care started. ', N'Recurrent hypoglycemia from insulin excess; regimen reduced and education given. ', N'Newly diagnosed type 2 diabetes; lifestyle counseling and metformin initiated. '),
            CHOOSE((x.r_assess % 6) + 1, N'Acute decompensated heart failure with reduced ejection fraction, volume overloaded. ', N'Flash pulmonary edema requiring noninvasive positive-pressure ventilation. ', N'Heart failure with preserved ejection fraction, congested on examination. ', N'Right-sided heart failure with hepatic congestion and peripheral edema. ', N'Acute on chronic systolic heart failure exacerbation, diuresing appropriately. ', N'Heart failure exacerbation precipitated by nonadherence and dietary sodium. '),
            CHOOSE((x.r_assess % 6) + 1, N'Community-acquired pneumonia, lower lobe, responding to empiric antibiotics. ', N'Community-acquired pneumonia with a parapneumonic effusion on imaging. ', N'Severe community-acquired pneumonia with sepsis and hypoxemia. ', N'Healthcare-associated pneumonia; broadened antibiotic coverage started. ', N'Community-acquired pneumonia with mild hypoxemia requiring supplemental oxygen. ', N'Atypical pneumonia suspected; macrolide therapy initiated. '),
            CHOOSE((x.r_assess % 6) + 1, N'Uncomplicated cystitis; urinalysis consistent with a lower urinary tract infection. ', N'Acute pyelonephritis with systemic signs; intravenous antibiotics started. ', N'Urinary tract infection with early urosepsis; hemodynamically monitored. ', N'Complicated urinary tract infection with delirium in an older adult. ', N'Catheter-associated urinary tract infection; the catheter was exchanged. ', N'Hemorrhagic cystitis; infection treated and hematuria monitored. '),
            CHOOSE((x.r_assess % 6) + 1, N'Acute appendicitis without perforation; surgical evaluation obtained. ', N'Perforated appendicitis with localized peritonitis; urgent surgery planned. ', N'Appendicitis with generalized peritonitis and sepsis. ', N'Uncomplicated appendicitis confirmed on imaging; appendectomy scheduled. ', N'Acute appendicitis, post-operative day one, recovering after laparoscopic appendectomy. ', N'Suspected appendicitis; serial examinations and imaging in progress. '),
            CHOOSE((x.r_assess % 6) + 1, N'ST-elevation myocardial infarction; activated the cardiac catheterization laboratory. ', N'Non-ST-elevation myocardial infarction with a rising troponin; dual antiplatelet therapy started. ', N'Unstable angina; admitted for serial troponins and inpatient risk stratification. ', N'Acute pericarditis with diffuse ST changes; anti-inflammatory therapy started. ', N'Non-cardiac chest pain, likely gastroesophageal reflux; cardiac workup reassuring. ', N'Musculoskeletal costochondritis; acute coronary syndrome excluded by serial troponins. '),
            CHOOSE((x.r_assess % 6) + 1, N'Vasovagal syncope; orthostatic and cardiac causes considered and unlikely. ', N'Cardiac syncope from a suspected arrhythmia; telemetry monitoring initiated. ', N'Orthostatic hypotension, likely medication-related and volume-depleted. ', N'Exertional syncope concerning for structural heart disease; echocardiogram ordered. ', N'Syncope of undetermined etiology; telemetry monitoring in place. ', N'Situational syncope with a clear precipitant and reassuring workup. '),
            CHOOSE((x.r_assess % 6) + 1, N'Acute ischemic stroke within the thrombolysis window; stroke team activated. ', N'Acute ischemic stroke outside the thrombolysis window; admitted for workup. ', N'Transient ischemic attack with resolved deficit; urgent secondary prevention. ', N'Subarachnoid hemorrhage suspected; emergent imaging and neurosurgery consulted. ', N'Posterior circulation stroke with brainstem signs. ', N'Cerebral infarction with residual deficit; stroke protocol initiated. '),
            CHOOSE((x.r_assess % 6) + 1, N'COPD exacerbation, likely infective trigger, on bronchodilators and steroids. ', N'Severe COPD exacerbation with respiratory acidosis requiring noninvasive ventilation. ', N'Acute COPD exacerbation with hypoxemia; responding to nebulized therapy. ', N'COPD exacerbation triggered by a viral infection; supportive care started. ', N'COPD exacerbation with bronchospasm; intensified bronchodilator therapy. ', N'COPD exacerbation with a bacterial trigger; antibiotics initiated. ')),
        CHOOSE((x.r_comorb % 4) + 1,
            N'Comorbid hypertension, hyperlipidemia, and type 2 diabetes, well controlled. ',
            N'Comorbid COPD and stage 3 chronic kidney disease. ',
            N'History of atrial fibrillation maintained on anticoagulation. ',
            N'No significant chronic comorbidities identified. '),
        CHAR(13), CHAR(10),
        N'Plan: ',
        CHOOSE(x.cond + 1,
            CHOOSE((x.r_plan % 6) + 1, N'Admit to a monitored bed for IV antihypertensive titration and end-organ surveillance. ', N'Up-titrate oral agents, observe for several hours, and arrange close follow-up. ', N'Start a thiazide plus an ACE inhibitor and counsel on sodium restriction. ', N'Reconcile medications, address adherence barriers, and resume the prior regimen. ', N'Reassure, initiate home blood-pressure logging, and follow up in clinic. ', N'Order renal ultrasound and aldosterone-renin testing for secondary causes. '),
            CHOOSE((x.r_plan % 6) + 1, N'Start an insulin drip with hourly glucose and electrolyte monitoring. ', N'Give aggressive isotonic fluids, correct electrolytes, and transition to subcutaneous insulin. ', N'Adjust the insulin regimen and engage diabetes education for glycemic control. ', N'Offload the ulcer, provide wound care, and start empiric antibiotics. ', N'Reduce insulin dosing, review carbohydrate intake, and reinforce glucose monitoring. ', N'Start metformin, provide dietary counseling, and arrange endocrinology follow-up. '),
            CHOOSE((x.r_plan % 6) + 1, N'Diurese with IV furosemide and monitor daily weights and electrolytes. ', N'Provide noninvasive ventilation, nitrates, and aggressive diuresis in a monitored bed. ', N'Diurese, optimize afterload reduction, and evaluate diastolic function. ', N'Diurese cautiously, evaluate for pulmonary hypertension, and monitor renal function. ', N'Optimize guideline-directed medical therapy and restrict fluid and sodium. ', N'Reinforce adherence, provide dietary education, and arrange close follow-up. '),
            CHOOSE((x.r_plan % 6) + 1, N'Start empiric antibiotics and supplemental oxygen after obtaining blood cultures. ', N'Continue antibiotics, evaluate the effusion with ultrasound, and consider drainage. ', N'Initiate the sepsis bundle with fluids, broad antibiotics, and monitored admission. ', N'Broaden antibiotic coverage per exposure history and de-escalate on cultures. ', N'Continue antibiotics, trend oxygenation, and encourage incentive spirometry. ', N'Start a macrolide, treat as an outpatient if stable, and follow up closely. '),
            CHOOSE((x.r_plan % 6) + 1, N'Start oral antibiotics, encourage hydration, and follow up if symptoms persist. ', N'Give intravenous antibiotics, obtain cultures, and monitor renal function. ', N'Provide fluids, broad antibiotics, and monitored observation for sepsis. ', N'Treat the infection, address the delirium, and review for reversible causes. ', N'Exchange the catheter, obtain cultures, and start targeted antibiotics. ', N'Treat the infection, ensure hydration, and monitor the hematuria. '),
            CHOOSE((x.r_plan % 6) + 1, N'Keep NPO with IV fluids and analgesia; surgery consulted for operative planning. ', N'Proceed to urgent appendectomy with broad antibiotics and fluid resuscitation. ', N'Arrange emergent surgery, sepsis management, and monitored-bed admission. ', N'Proceed to laparoscopic appendectomy with perioperative antibiotics. ', N'Continue post-operative pain control, advance diet, and watch for infection. ', N'Perform serial abdominal exams, repeat imaging, and surgical reassessment. '),
            CHOOSE((x.r_plan % 6) + 1, N'Proceed to emergent percutaneous coronary intervention with interventional cardiology. ', N'Admit to telemetry, load antiplatelets and anticoagulation, and trend high-sensitivity troponin. ', N'Obtain serial electrocardiograms and troponins with cardiology consultation for possible catheterization. ', N'Start high-dose NSAIDs and colchicine with outpatient cardiology follow-up. ', N'Trial proton-pump inhibitor therapy and discharge with gastroenterology follow-up. ', N'Provide reassurance and analgesia, and discharge with return precautions and primary-care follow-up. '),
            CHOOSE((x.r_plan % 6) + 1, N'Hydrate, review medications, and counsel on trigger avoidance. ', N'Arrange telemetry monitoring, cardiology consultation, and an echocardiogram. ', N'Replete volume, review medications, and reassess orthostatic vitals. ', N'Obtain urgent echocardiography, restrict activity, and arrange cardiology evaluation. ', N'Continue telemetry monitoring, orthostatic vitals, and an echocardiogram. ', N'Reassure, hydrate, and arrange outpatient follow-up. '),
            CHOOSE((x.r_plan % 6) + 1, N'Pursue emergent thrombolysis evaluation, imaging, and stroke-unit admission. ', N'Admit to the stroke unit, obtain MRI, and start secondary-prevention therapy. ', N'Arrange expedited carotid imaging, antiplatelets, and risk-factor management. ', N'Obtain emergent CT and neurosurgical consultation with blood-pressure control. ', N'Obtain neurology consultation, dysphagia screening, and close neurologic monitoring. ', N'Provide stroke-unit care, dysphagia screening, and early rehabilitation. '),
            CHOOSE((x.r_plan % 6) + 1, N'Give nebulized bronchodilators, systemic steroids, and titrated oxygen. ', N'Provide noninvasive ventilation, steroids, and monitored-bed admission. ', N'Admit for respiratory support and continue bronchodilator therapy. ', N'Provide supportive care, bronchodilators, and monitor for bacterial superinfection. ', N'Intensify bronchodilators, add steroids, and reassess oxygenation. ', N'Start antibiotics, continue bronchodilators and steroids, and trend oxygenation. ')),
        CHOOSE((x.r_plan2 % 3) + 1,
            N'Repeat basic metabolic panel and complete blood count in the morning. ',
            N'Continue telemetry monitoring overnight. ',
            N'Case management engaged for discharge planning. '),
        N'Patient and family educated on medication reconciliation and dietary modification. ',
        CHOOSE((x.r_fu % 3) + 1,
            N'Follow up with primary care within seven days. ',
            N'Follow up in the appropriate specialty clinic in two weeks. ',
            N'Return precautions reviewed; follow up as needed. ')
    ),
    DATEADD(SECOND,
        ABS(CHECKSUM(NEWID())) % (ABS(DATEDIFF(SECOND, e.AdmitTime, COALESCE(e.DischargeTime, SYSUTCDATETIME()))) + 1),
        e.AdmitTime)
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 2) gs
CROSS APPLY (SELECT
        cond     = (e.EncounterId * 7 + 1) % 10,
        r_type   = ABS(CHECKSUM(NEWID())),
        r_sub    = ABS(CHECKSUM(NEWID())),
        r_hpi    = ABS(CHECKSUM(NEWID())),
        r_pmh    = ABS(CHECKSUM(NEWID())),
        r_fh     = ABS(CHECKSUM(NEWID())),
        r_gen    = ABS(CHECKSUM(NEWID())),
        r_card   = ABS(CHECKSUM(NEWID())),
        r_lung   = ABS(CHECKSUM(NEWID())),
        r_abd    = ABS(CHECKSUM(NEWID())),
        r_ext    = ABS(CHECKSUM(NEWID())),
        r_assess = ABS(CHECKSUM(NEWID())),
        r_comorb = ABS(CHECKSUM(NEWID())),
        r_plan   = ABS(CHECKSUM(NEWID())),
        r_plan2  = ABS(CHECKSUM(NEWID())),
        r_fu     = ABS(CHECKSUM(NEWID())),
        r_t      = ABS(CHECKSUM(NEWID())),
        r_t2     = ABS(CHECKSUM(NEWID())),
        r_hr     = ABS(CHECKSUM(NEWID())),
        r_bs     = ABS(CHECKSUM(NEWID())),
        r_bd     = ABS(CHECKSUM(NEWID())),
        r_rr     = ABS(CHECKSUM(NEWID())),
        r_sp     = ABS(CHECKSUM(NEWID())),
        r_pn     = ABS(CHECKSUM(NEWID()))
    ) x
CROSS APPLY (SELECT
        tempInt   = CASE WHEN x.cond IN (3, 4, 5) THEN 38 WHEN x.cond IN (2, 9) THEN 37 ELSE 36 + (x.r_t % 2) END,
        tempTenth = x.r_t2 % 10,
        hr        = CASE WHEN x.cond = 7 THEN 50 + (x.r_hr % 60)
                         WHEN x.cond IN (2, 3, 6, 9) THEN 90 + (x.r_hr % 35)
                         ELSE 62 + (x.r_hr % 40) END,
        bpSys     = CASE WHEN x.cond = 0 THEN 150 + (x.r_bs % 35)
                         WHEN x.cond = 7 THEN 88 + (x.r_bs % 22)
                         ELSE 108 + (x.r_bs % 40) END,
        bpDia     = CASE WHEN x.cond = 0 THEN 92 + (x.r_bd % 18)
                         WHEN x.cond = 7 THEN 52 + (x.r_bd % 16)
                         ELSE 62 + (x.r_bd % 26) END,
        rr        = CASE WHEN x.cond IN (3, 9) THEN 20 + (x.r_rr % 8) ELSE 12 + (x.r_rr % 8) END,
        spo2      = CASE WHEN x.cond IN (2, 3, 9) THEN 86 + (x.r_sp % 8) ELSE 95 + (x.r_sp % 5) END,
        pain      = CASE WHEN x.cond IN (5, 6) THEN 5 + (x.r_pn % 5)
                         WHEN x.cond IN (0, 1, 8) THEN (x.r_pn % 3)
                         ELSE 2 + (x.r_pn % 5) END
    ) v
WHERE ((e.EncounterId + gs.value) % 4) <> 0;   -- ~1.25 notes per encounter
GO

/* ---- 4. Recreate the EMPTY embeddings table (SYNC WITH 06-ai-embeddings.sql) - */
CREATE TABLE clinical.ClinicalNoteEmbeddings
(
    NoteId        INT                   NOT NULL,
    Embedding     VECTOR(3072, float16) NOT NULL,
    GeneratedAt   DATETIME2(3)          NOT NULL CONSTRAINT DF_NoteEmb_GeneratedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ClinicalNoteEmbeddings PRIMARY KEY CLUSTERED (NoteId),
    CONSTRAINT FK_ClinicalNoteEmbeddings_Note
        FOREIGN KEY (NoteId) REFERENCES clinical.ClinicalNote (NoteId)
);
GO

/* ---- 5. Report --------------------------------------------------------------- */
SELECT
    notes            = (SELECT COUNT(*) FROM clinical.ClinicalNote),
    distinct_notes   = (SELECT COUNT(DISTINCT HASHBYTES('SHA2_256', NoteText)) FROM clinical.ClinicalNote),
    embeddings_ready = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings);
GO
