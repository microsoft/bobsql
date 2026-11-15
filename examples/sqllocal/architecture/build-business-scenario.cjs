const path = require('node:path');
const PptxGenJS = require('pptxgenjs');

const pptx = new PptxGenJS();
pptx.layout = 'LAYOUT_WIDE';
pptx.author = 'Bob Ward';
pptx.company = 'Microsoft';
pptx.subject = 'Caldova Regional Care pre-arrival patient-transfer scenario';
pptx.title = 'Caldova | Regional care must run locally';
pptx.lang = 'en-US';
pptx.theme = {
  headFontFace: 'Segoe UI Semibold',
  bodyFontFace: 'Segoe UI',
  lang: 'en-US',
};

const c = {
  bg: '07182F', panel: '0B213D', layer: '102B4B', border: '345679',
  text: 'F3F8FF', muted: 'C4D8EF', amber: 'FFC16F',
  blue: '69B8FF', teal: '54D6C7',
};
const slide = pptx.addSlide();
slide.background = { color: c.bg };

function text(value, x, y, w, h, size, color = c.text, extra = {}) {
  slide.addText(value, {
    x, y, w, h, fontFace: 'Segoe UI', fontSize: size,
    margin: 0, color, valign: 'mid', ...extra,
  });
}

function shape(kind, x, y, w, h, color, fill = c.panel, extra = {}) {
  slide.addShape(pptx.ShapeType[kind], {
    x, y, w, h, fill: { color: fill },
    line: { color, width: 1.3 }, ...extra,
  });
}

function line(x, y, w, h, color, extra = {}) {
  slide.addShape(pptx.ShapeType.line, {
    x, y, w, h, line: { color, width: 1.4, ...extra },
  });
}

function cross(x, y, size, color) {
  shape('rect', x + size * 0.36, y, size * 0.28, size, color, color);
  shape('rect', x, y + size * 0.36, size, size * 0.28, color, color);
}

function person(x, y, color) {
  shape('ellipse', x + 0.19, y, 0.28, 0.28, color, c.layer);
  shape('roundRect', x, y + 0.34, 0.66, 0.43, color, c.layer);
  cross(x + 0.26, y + 0.44, 0.14, color);
}

function stage(number, title, x, w, color) {
  shape('ellipse', x, 1.85, 0.36, 0.36, color, c.layer);
  text(String(number), x, 1.89, 0.36, 0.23, 14, color,
    { bold: true, align: 'center' });
  text(title, x + 0.51, 1.85, w - 0.51, 0.36, 21, color, { bold: true });
}

function record(title, y) {
  shape('roundRect', 0.75, y, 2.98, 0.44, c.border, c.panel);
  shape('rect', 0.92, y + 0.1, 0.22, 0.25, c.amber, c.layer);
  line(0.97, y + 0.17, 0.12, 0, c.amber);
  line(0.97, y + 0.25, 0.12, 0, c.amber);
  text(title, 1.3, y + 0.08, 2.24, 0.28, 13.6, c.muted);
}

text('Caldova | Regional care must run locally', 0.55, 0.35, 12.2, 0.6, 34,
  c.text, { bold: true, fontFace: 'Segoe UI Semibold' });
text('A regional transfer center must coordinate emergency arrivals using local records and resources.',
  0.57, 1.03, 12.1, 0.35, 16, c.muted);

shape('rect', 0.6, 1.75, 12.13, 4.72, c.border, c.bg,
  { line: { color: c.border, width: 1.2, dashType: 'dash' } });
text('CALDOVA REGIONAL CARE | LOCAL OPERATIONS', 0.75, 1.46, 7.5, 0.24,
  11.2, c.blue, { bold: true });
shape('cloud', 9.22, 1.42, 0.48, 0.27, c.amber, c.panel);
line(9.24, 1.41, 0.44, 0.29, c.amber, { width: 2 });
text('No cloud-hosted care workload', 9.87, 1.46, 2.86, 0.24,
  11.2, c.amber, { bold: true });

stage(1, 'Patient in transit', 0.75, 3.04, c.amber);
stage(2, 'Regional transfer center', 4.43, 4.43, c.blue);
stage(3, 'Receiving team', 9.75, 2.88, c.teal);

shape('roundRect', 0.95, 2.83, 2.02, 0.86, c.amber, c.layer);
shape('rect', 2.97, 3.05, 0.57, 0.64, c.amber, c.layer);
shape('rect', 3.03, 3.11, 0.44, 0.24, c.amber, '204D6F');
shape('rect', 2.28, 2.71, 0.35, 0.1, c.amber, c.amber);
cross(1.23, 3.05, 0.4, c.amber);
text('CALDOVA', 1.83, 3.17, 0.99, 0.25, 10.2, c.amber, { bold: true });
for (const x of [1.28, 2.94]) {
  shape('ellipse', x, 3.51, 0.38, 0.38, c.amber, c.bg);
  shape('ellipse', x + 0.12, 3.63, 0.14, 0.14, c.amber, c.amber);
}
shape('ellipse', 0.97, 4.03, 0.26, 0.26, c.amber, c.bg);
line(1.1, 4.075, 0, 0.09, c.amber);
line(1.1, 4.16, 0.065, 0.04, c.amber);
text('The arrival clock is running', 1.38, 4.02, 2.4, 0.28, 12.5, c.amber);
record('Field narrative', 4.53);
record('Vitals, allergies & meds', 5.07);
record('Dated patient history', 5.61);
text('Important context spans multiple records.', 0.75, 6.15, 3.04, 0.25,
  11.6, c.muted);

line(3.85, 3.32, 0.43, 0, c.blue, { endArrowType: 'triangle', width: 2.2 });
shape('rect', 4.43, 2.61, 4.43, 3.02, c.blue, c.panel,
  { line: { color: c.blue, width: 2 } });
text('Regional Care Transfer Center', 4.66, 2.79, 3.58, 0.34, 17.2,
  c.text, { bold: true });
for (const x of [8.32, 8.46, 8.6]) {
  shape('ellipse', x, 2.91, 0.055, 0.055, c.blue, c.blue);
}
shape('rect', 4.66, 3.31, 1.04, 1.73, c.border, c.bg);
text('Queue', 4.8, 3.4, 0.76, 0.24, 12, c.muted, { bold: true });
for (const [index, y] of [3.85, 4.23, 4.61].entries()) {
  shape('rect', 4.79, y, 0.78, 0.25, index === 0 ? c.blue : c.border,
    index === 0 ? '173C61' : c.panel);
  line(4.89, y + 0.12, 0.54, 0, index === 0 ? c.blue : c.border);
}
text('AI-assisted briefing', 5.95, 3.35, 2.65, 0.32, 17,
  c.blue, { bold: true });
for (const [index, label] of [
  'Current transfer facts', 'Relevant history', 'Confirm on arrival',
].entries()) {
  const y = 3.94 + index * 0.43;
  shape('rect', 5.98, y + 0.06, 0.13, 0.13, c.blue, c.blue);
  text(label, 6.25, y, 2.33, 0.27, 13.5);
}
shape('rect', 4.66, 5.17, 3.97, 0.27, c.layer, c.layer);
text('Source-linked draft | Review required', 4.83, 5.19, 3.64, 0.22, 11.5,
  c.muted, { align: 'center' });
shape('rect', 6.35, 5.65, 0.59, 0.22, c.blue, c.layer);
shape('roundRect', 5.75, 5.86, 1.79, 0.1, c.blue, c.layer);

line(9.01, 3.32, 0.52, 0, c.teal, { endArrowType: 'triangle', width: 2.2 });
shape('rect', 9.98, 2.84, 2.61, 1.12, c.teal, c.layer);
shape('rect', 10.75, 2.5, 1.07, 1.46, c.teal, c.panel);
cross(11.04, 2.69, 0.45, c.teal);
for (const x of [10.2, 10.54, 11.97, 12.31]) {
  shape('rect', x, 3.09, 0.14, 0.16, c.teal, '204D6F');
  shape('rect', x, 3.51, 0.14, 0.16, c.teal, '204D6F');
}
shape('rect', 11.03, 3.41, 0.49, 0.55, c.teal, c.layer);
person(10.48, 4.14, c.teal);
person(11.47, 4.14, c.teal);
shape('roundRect', 9.85, 5.12, 2.7, 0.94, c.teal, c.panel);
text('Know the context\nClarify handoff gaps\nPrepare for arrival',
  10.06, 5.22, 2.28, 0.72, 14.2, c.text, { breakLine: false });
text('Clinicians review and decide.', 9.75, 6.15, 2.88, 0.25, 11.6,
  c.teal, { align: 'center' });

shape('roundRect', 0.6, 6.55, 12.13, 0.44, c.border, c.layer);
text('Local patient records + local compute + local AI | Goal: a clearer handoff',
  0.82, 6.62, 11.69, 0.29, 18, c.text, { align: 'center' });

slide.addNotes(`
Business scenario: Caldova Regional Care coordinates incoming emergency patient
transfers. The patient is already in transit and the receiving team needs a
clear pre-arrival handoff. The app displays the incoming transfer queue,
destination, ETA, field narratives, observations, allergies, medications,
recent encounters, and extracted signals. This is a conceptual workflow,
not a live screenshot or a measured improvement claim. All demo data is synthetic.

The presenter-defined operating requirement is that this regional transfer
center must use local patient records, application/database compute, and AI
inference resources. The care workload cannot be hosted in the public cloud.
The shared dashed boundary places the entire care workflow inside Caldova's
regional environment; the slashed cloud labels the workload-hosting restriction.
This is a constraint of the Caldova business scenario, not a universal claim
that healthcare applications cannot use cloud services or a statement of law.
No particular regulatory, connectivity, or latency reason has been supplied.
The connected demo can still use Azure-hosted management and AVD brokering:
local care-workload hosting does not mean all cloud services are prohibited,
and this slide does not claim a fully disconnected or air-gapped deployment.

The problem illustrated is assembling relevant context spread across records
while preparing for a patient's arrival. The ambulance and hospital are
editable visual symbols, not claims about an actual patient, transport vehicle,
facility, clinical condition, ETA, or real organization.

The center monitor represents the existing Caldova Transfer Center app:
- Review the selected transfer and current operational/clinical facts.
- Find relevant history independently using an editable transfer concern.
- Generate a source-linked receiving briefing, optionally including relevant
  dated historical notes. History inclusion is off by default; the SQL-owned
  generation workflow does not require the independent preview search.
- Read current facts, separate dated historical context, and suggestions about
  what to verify or clarify on arrival. Inspect saved supporting source records.

The receiving team reviews the draft and source evidence and makes clinical
decisions. Receiving recommendations are AI-generated suggestions requiring
clinician review. The approved skill explicitly forbids diagnosing, prescribing,
recommending treatment, or placing orders. The slide does not claim autonomous
triage, diagnosis, destination/bay assignment, team notification, or treatment.

The resource band emphasizes local records, compute, and AI; the clearer handoff
is a goal, not a measured reduction in delay, errors, cost, or clinical risk.
Source provenance and persisted audit evidence support
traceability; external ledger digest verification is not configured in this demo.
Patient data and model inference run inside the organization-controlled Regional
Care environment in the connected Azure Local demo. Infrastructure is deliberately
omitted here: this slide explains why the application exists, not its architecture.

Publication scope:
This standalone generator illustrates the synthetic Caldova scenario described
above. It does not load an application, database, runbook, or another repository.
Generating this slide does not execute or verify that clinical workflow.
`);

pptx.writeFile({ fileName: path.join(__dirname, 'caldova-business-scenario.pptx') });
