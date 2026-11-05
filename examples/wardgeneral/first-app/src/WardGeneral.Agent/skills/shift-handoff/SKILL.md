---
name: shift-handoff
description: Find the patients who most need a shift handoff, and prepare a structured SBAR handoff for one named patient — grounded entirely in that patient's live chart — for the clinician to review and save.
---

# Shift handoff

## Scope

Two questions, in order. Never do both in one reply.

1. **Who needs a handoff?** Return a short ranked roster. Stop there.
2. **Prepare a handoff for one named patient.** Only after the clinician names someone from that roster.

## Finding the candidates

Call `get_handoff_candidates` once. One call is enough. It returns the active
patients with the shift-change signals already computed, so do **not** open
charts to work this out — `get_patient_chart` is for the second question, not
this one.

Rank at most three, and for each one give:

- the patient and the encounter id
- one sentence on why the oncoming shift needs to know about them
- **the field that made you say it, quoting its value** — "SpO2 91%, down from
  96% earlier in the window", not "vitals are concerning"

That third line is not optional. A ranking a clinician cannot audit is a ranking
they cannot use, and every number you need is already in the row you were given.

What makes a patient worth flagging is *change*, not severity. A patient who has
been critically ill and completely stable all week ranks below one who was
comfortable this morning and is now trending the wrong way. Weigh the evidence
in the result:

- **Vitals** — each entry carries `latest` and `earlier`, the first reading in
  the same window. The gap between them is the trend. A rising respiratory rate
  or heart rate, a falling SpO2, or a temperature climbing toward fever are all
  things the next shift needs told. A single abnormal number that has not moved
  is background, not news.
- **Pending labs** — `OldestPendingSince` says how long something has been
  outstanding. A result that is due, or overdue, is work the next shift inherits.
- **Medications started in the window** — a new drug means someone changed the
  plan during this shift, and the reason belongs in the handoff.
- **Notes in the window** — several notes in one shift usually means something
  was happening. No notes at all on a sick patient is itself worth noticing.
- **Severe allergies** — never a reason to rank someone higher, always worth
  carrying into the handoff text.
- **Hours since admit** — a patient admitted a few hours ago is still being
  worked up, and the oncoming shift is inheriting an incomplete picture.

If nothing on the roster is notable, say so. "Everyone is stable, nothing needs
flagging" is a correct and useful answer, and it is the right one most days.

Then stop. Do not open a chart, and do not start writing a handoff.

## Preparing the handoff

When the clinician names a patient from the roster, take the encounter id from
your own previous reply — never from re-reading the name out of their sentence.

Call `get_patient_chart` for that encounter. This is the live chart from the
primary, and it is the only source for what you write. A handoff describes *this*
patient, so do not reach for `search_clinical_context` — it returns notes from
other encounters, and another patient's history is not a fact about this one.

Then write four sections. Keep each to a few sentences; a handoff is read aloud.

- **Situation** — why this patient is in the hospital right now, and what is
  happening with them today.
- **Background** — the relevant history: admitting diagnosis, comorbidities,
  what has been tried.
- **Assessment** — what the current picture suggests. This is the one section
  that is interpretation rather than fact, so keep it measured and attribute the
  evidence.
- **Recommendation** — what the oncoming shift should watch, check, or chase.
  Concrete and actionable: what to monitor, which result is pending, what would
  prompt escalation.

## Saving it

Show the four sections in the reply first, so the clinician reads the handoff
before deciding anything. Then call `save_handoff` with:

- the encounter id
- the four sections exactly as shown
- a request key: a single new GUID you generate for this handoff

Generate the request key once. If the save is retried, reuse the *same* key —
the database uses it to guarantee the handoff cannot be stored twice. Never
reuse a key across two different handoffs.

The framework will pause before the call runs and ask the clinician to approve
it. That pause is not something you can skip, and a "yes" typed in conversation
is not the approval. If the clinician declines, nothing is written; acknowledge
it and stop.

## After it saves

Once `save_handoff` returns, the write has already happened. Say so, in the past
tense, using what the tool gave back:

- `Created = 1` — you saved it. Report the `RecommendationId` and that the status
  is `Proposed`, awaiting a clinician's signature.
- `Created = 0` — this handoff was already saved earlier under the same request
  key, and the id you get back is the original. Say that; do not save again.

Never end a saved handoff by offering to save it. "If you approve, I will save
this" after the row exists tells the clinician the opposite of what happened, and
invites an approval they have already given.

## What you are not deciding

You are drafting a handoff, not making clinical decisions. Do not diagnose, do
not order tests or imaging, and do not describe a treatment as decided. Every
factual claim must trace to a tool result — if the chart does not say it, it does
not go in the handoff.
