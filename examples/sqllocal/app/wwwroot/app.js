const queueElement = document.querySelector("#transfer-queue");
const queueCountElement = document.querySelector("#queue-count");
const detailElement = document.querySelector("#transfer-detail");
const detailTitleElement = document.querySelector("#detail-title");
const priorityElement = document.querySelector("#priority");
const briefingElement = document.querySelector("#briefing-content");
const refreshButton = document.querySelector("#refresh");
const statusText = document.querySelector("#system-status");
const statusDot = document.querySelector("#status-dot");
const auditPanel = document.querySelector("#audit-panel");
const auditElement = document.querySelector("#audit-history");
const refreshAuditButton = document.querySelector("#refresh-audit");
const generateButton = document.querySelector("#generate-briefing");
const includeHistoryInput = document.querySelector("#include-history");

let selectedTransferNumber = null;
let selectionVersion = 0;
let auditLoadVersion = 0;

const api = async (url, options) => {
  const response = await fetch(url, options);
  if (!response.ok) {
    const problem = await response.json().catch(() => null);
    throw new Error(problem?.detail || problem?.title || `Request failed (${response.status})`);
  }
  return response.json();
};

const element = (tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};

const formatValue = (value, unit) => value == null ? "Not recorded" : `${value}${unit ? ` ${unit}` : ""}`;
const formatDate = (value) => new Intl.DateTimeFormat("en", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));

function setConnection(status, text) {
  statusDot.className = status;
  statusText.textContent = text;
}

function showError(target, message) {
  target.replaceChildren();
  const state = element("div", "empty-state error-state");
  state.append(element("strong", null, "Unable to load data"), element("span", null, message));
  target.append(state);
}

async function loadQueue() {
  refreshButton.disabled = true;
  try {
    const transfers = await api("/api/transfers");
    queueCountElement.textContent = transfers.length;
    queueElement.replaceChildren();

    for (const transfer of transfers) {
      const button = element("button", `transfer-card${transfer.transferNumber === selectedTransferNumber ? " active" : ""}`);
      button.type = "button";
      button.dataset.transferNumber = transfer.transferNumber;

      const eta = element("div", "eta", transfer.etaMinutes);
      eta.append(element("span", null, "MIN"));
      const content = element("div");
      content.append(
        element("div", "transfer-name", `${transfer.givenName} ${transfer.familyName} · ${transfer.age}`),
        element("div", "transfer-meta", `${transfer.transportUnit} → ${transfer.destinationName}\n${transfer.chiefConcern} · Priority ${transfer.priorityCode}`),
        element("span", `severity${transfer.priorityCode === 1 ? " critical" : ""}`, transfer.priorityCode === 1 ? "Immediate review" : transfer.transferStatus)
      );
      button.append(eta, content);
      button.addEventListener("click", () => selectTransfer(transfer.transferNumber));
      queueElement.append(button);
    }

    setConnection("connected", "Regional systems connected");
    if (!selectedTransferNumber && transfers.length > 0) await selectTransfer(transfers[0].transferNumber);
  } catch (error) {
    setConnection("failed", "Database unavailable");
    showError(queueElement, error.message);
  } finally {
    refreshButton.disabled = false;
  }
}

async function selectTransfer(transferNumber) {
  const version = ++selectionVersion;
  includeHistoryInput.checked = false;
  includeHistoryInput.disabled = true;
  generateButton.disabled = true;
  generateButton.textContent = "Generate receiving briefing";
  selectedTransferNumber = transferNumber;
  auditElement.replaceChildren();
  if (auditPanel.open) loadAuditHistory();
  document.querySelectorAll(".transfer-card").forEach(card => {
    card.classList.toggle("active", card.dataset.transferNumber === transferNumber);
  });
  briefingElement.replaceChildren(createEmpty("Briefing pending", "Generate a draft after reviewing the transfer packet."));
  detailElement.replaceChildren(createLoading("Loading regional records"));

  try {
    const detail = await api(`/api/transfers/${encodeURIComponent(transferNumber)}`);
    if (version !== selectionVersion) return;
    renderDetail(detail);
    includeHistoryInput.disabled = false;
    generateButton.disabled = false;
  } catch (error) {
    if (version !== selectionVersion) return;
    showError(detailElement, error.message);
  }
}

function createLoading(text) {
  const state = element("div", "empty-state");
  state.append(element("div", "spinner"), element("strong", null, text));
  return state;
}

function createEmpty(title, text) {
  const state = element("div", "empty-state");
  state.append(element("strong", null, title), element("span", null, text));
  return state;
}

function renderDetail(detail) {
  const transfer = detail.transfer;
  detailTitleElement.textContent = transfer.encounterNumber;
  priorityElement.textContent = `P${transfer.priorityCode}`;
  detailElement.replaceChildren();

  const patientRow = element("div", "patient-row");
  const patient = element("div");
  patient.append(
    element("div", "patient-name", `${transfer.givenName} ${transfer.familyName}`),
    element("div", "patient-meta", `${transfer.age} years · MRN ${transfer.regionalRecordNumber}`)
  );
  const arrival = element("div", "arrival");
  arrival.append(
    element("strong", null, `ETA ${transfer.etaMinutes} minutes`),
    element("span", null, `${transfer.destinationName}${transfer.destinationBay ? ` · ${transfer.destinationBay}` : ""}`)
  );
  patientRow.append(patient, arrival);

  const vitals = element("div", "vitals");
  for (const observation of detail.observations) {
    const card = element("div", `vital${observation.isAlert ? " alert" : ""}`);
    card.append(
      element("span", null, observation.name),
      element("strong", null, formatValue(observation.textValue ?? observation.numericValue, observation.textValue ? null : observation.unit))
    );
    vitals.append(card);
  }

  const narrativeSection = element("section");
  narrativeSection.append(element("h3", null, "Paramedic narrative"));
  const narrative = detail.narratives[0];
  narrativeSection.append(element("p", "narrative", narrative?.text || "No field narrative received."));

  const signalSection = element("section");
  signalSection.append(element("h3", null, "Extracted signals"));
  const signals = element("div", "signals");
  for (const signal of detail.signals) {
    const chip = element("span", "signal");
    chip.append(element("strong", null, signal.type), document.createTextNode(signal.value));
    signals.append(chip);
  }
  if (detail.signals.length === 0) signals.append(element("span", "patient-meta", "Signals are extracted when a briefing is generated."));
  signalSection.append(signals);

  const facts = element("div", "facts");
  facts.append(
    createFact("Active allergies", detail.allergies.map(item => `${item.name}${item.reaction ? ` (${item.reaction})` : ""}`).join(" · ") || "None recorded"),
    createFact("Active medications", detail.medications.map(item => item.name).join(" · ") || "None recorded"),
    createFact("Recent encounter", detail.recentEncounters[0] ? `${detail.recentEncounters[0].type} · ${formatDate(detail.recentEncounters[0].startedAt)}` : "None recorded"),
    createFact("Transfer status", `${transfer.transferStatus}${transfer.receivingTeamNotifiedAt ? " · Receiving team notified" : ""}`)
  );

  detailElement.append(patientRow, vitals, narrativeSection, signalSection, facts, createHistorySection(transfer));
}

function createHistorySection(transfer) {
  const section = element("section", "history-section");
  section.append(
    element("h3", null, "Patient history"),
    element("p", "patient-meta", "Search this patient's dated notes. Historical findings are separate from the current transfer.")
  );
  const form = element("form", "history-search");
  const label = element("label", null, "Search concern");
  const input = element("textarea");
  input.id = "history-query";
  input.rows = 2;
  input.value = transfer.chiefConcern.toLowerCase() === "chest pressure"
    ? "tight squeezing feeling in the center of the chest on exertion"
    : transfer.chiefConcern;
  input.required = true;
  input.maxLength = 4000;
  label.htmlFor = input.id;
  const button = element("button", "secondary", "Find relevant history");
  button.type = "submit";
  input.addEventListener("keydown", event => {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      if (!button.disabled) form.requestSubmit(button);
    }
  });
  const results = element("div", "history-results");
  results.id = "history-results";
  results.setAttribute("aria-live", "polite");
  form.append(label, input, button);
  form.addEventListener("submit", async event => {
    event.preventDefault();
    const version = selectionVersion;
    if (!input.value.trim()) {
      showError(results, "Enter a concern to search this patient's history.");
      return;
    }
    button.disabled = true;
    button.textContent = "Searching history…";
    results.setAttribute("aria-busy", "true");
    results.replaceChildren(createLoading("Searching dated patient notes with Nemotron"));
    try {
      const notes = await api(`/api/transfers/${encodeURIComponent(transfer.transferNumber)}/history-search`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: input.value.trim(), topK: 3 })
      });
      if (version !== selectionVersion) return;
      renderHistory(results, notes);
    } catch (error) {
      if (version !== selectionVersion) return;
      showError(results, error.message);
    } finally {
      button.disabled = false;
      button.textContent = "Find relevant history";
      results.setAttribute("aria-busy", "false");
    }
  });
  section.append(form, results);
  return section;
}

function renderHistory(target, notes) {
  target.replaceChildren();
  if (notes.length === 0) {
    target.append(createEmpty("No matching historical notes",
      "No dated notes for this patient passed the search relevance filter. This does not mean the patient has no history."));
    return;
  }
  target.append(element("p", "patient-meta",
    `${notes.length} historical notes passed the search relevance filter · Cosine distance: lower is closer, not clinical confidence.`));
  for (const [index, note] of notes.entries()) {
    const card = element("article", "history-note");
    card.append(
      element("strong", null, `${index + 1}. ${note.title}`),
      element("div", "patient-meta",
        `${formatDate(note.recordedAt)} · Distance ${note.cosineDistance.toFixed(3)}${note.isSynthetic ? " · Synthetic" : ""}`),
      element("p", "history-excerpt",
        note.noteText.length > 170 ? `${note.noteText.slice(0, 170)}…` : note.noteText)
    );
    const source = element("details", "history-source");
    source.append(
      element("summary", null, `View source · ${note.sourceCode}`),
      element("p", null, note.noteText),
      element("div", "patient-meta", `${note.authoredBy} · Note ${note.historicalNoteId} · ${note.modelId}`)
    );
    card.append(source);
    target.append(card);
  }
  target.append(element("p", "history-boundary",
    "Preview only. Use Include relevant history in the briefing pane to retrieve notes using the current transfer concern."));
}

function createFact(label, value) {
  const fact = element("div", "fact");
  fact.append(element("span", null, label), document.createTextNode(value));
  return fact;
}

async function generateBriefing() {
  const version = selectionVersion;
  const transferNumber = selectedTransferNumber;
  const includeHistory = includeHistoryInput.checked;
  const button = generateButton;
  includeHistoryInput.disabled = true;
  button.disabled = true;
  button.textContent = "Generating…";
  briefingElement.replaceChildren(createLoading(
    includeHistory ? "Retrieving up to three historical notes and generating a grounded briefing" : "Generating a briefing from current transfer records"));
  try {
    const briefing = await api(`/api/transfers/${encodeURIComponent(transferNumber)}/briefings`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ includeHistory })
    });
    if (version !== selectionVersion) return;
    renderBriefing(briefing);
    button.textContent = "Regenerate briefing";
  } catch (error) {
    if (version !== selectionVersion) return;
    showError(briefingElement, error.message);
    button.textContent = "Try again";
  } finally {
    if (version === selectionVersion) {
      button.disabled = false;
      includeHistoryInput.disabled = false;
      if (auditPanel.open) await loadAuditHistory();
    }
  }
}

function renderBriefing(briefing) {
  briefingElement.replaceChildren();
  const banner = element("div", "ai-banner");
  banner.append(element("strong", null, "AI-generated draft · Clinician review required"));
  briefingElement.append(banner, element("p", "summary", briefing.summary));

  const keyContext = briefing.items.filter(item => item.sectionName === "KeyContext");
  const confirm = briefing.items.filter(item => item.sectionName === "ConfirmOnArrival");
  const recommendations = createBriefSection("Receiving recommendations", confirm, "confirm");
  recommendations.insertBefore(
    element("p", "recommendation-note", "AI-generated suggestions for receiving the patient · Clinician review required"),
    recommendations.querySelector("ul")
  );
  briefingElement.append(recommendations, createBriefSection("Key context", keyContext));
  const historicalContext = briefing.items.filter(item => item.sectionName === "HistoricalContext");
  if (historicalContext.length) {
    const section = element("section", "brief-section historical-context");
    section.append(element("h3", null, "Historical context · Dated evidence"));
    for (const item of historicalContext) {
      const source = briefing.sources.find(source => source.packetSourceId === item.packetSourceId);
      const citation = element("details", "history-source");
      citation.append(
        element("summary", null, `${source.title} · ${formatDate(source.recordedAt)} · Note ${source.recordKey}`),
        element("p", null, source.noteText),
        element("div", "patient-meta", `${source.authoredBy} · Saved source snapshot`)
      );
      section.append(element("p", "summary", item.text), citation);
    }
    briefingElement.append(section);
  }

  const provenance = element("div", "provenance");
  provenance.append(element("p", null, `Briefing ${briefing.briefingId} · ReceivingBriefing ${briefing.skillVersion} · ${briefing.modelId} · ${briefing.durationMs.toLocaleString()} ms · ${briefing.reviewStatus}`));
  const sourceList = element("div", "source-list");
  for (const source of briefing.sources) sourceList.append(element("span", null,
    source.type === "HistoricalNote" ? `History: ${source.title}` : source.type));
  provenance.append(sourceList);
  provenance.append(element("p", "history-boundary",
    historicalContext.length
      ? `Evidence supplied: 7 regional source groups + ${historicalContext.length} historical ${historicalContext.length === 1 ? "note" : "notes"}. Citations show the saved evidence.`
      : "Evidence supplied: the original seven regional source groups. No historical notes were included."));
  briefingElement.append(provenance);
}

function createBriefSection(title, items, modifier = "") {
  const section = element("section", `brief-section ${modifier}`.trim());
  section.append(element("h3", null, title));
  const list = element("ul");
  for (const item of items) list.append(element("li", null, item.text));
  section.append(list);
  return section;
}

async function loadAuditHistory() {
  const transferNumber = selectedTransferNumber;
  if (!transferNumber) {
    auditElement.replaceChildren(createEmpty("No transfer selected", "Choose a transfer to view its AI audit history."));
    return;
  }
  const version = selectionVersion;
  const loadVersion = ++auditLoadVersion;
  refreshAuditButton.disabled = true;
  auditElement.replaceChildren(createLoading("Loading ledger records"));
  try {
    const entries = await api(`/api/transfers/${encodeURIComponent(transferNumber)}/audit`);
    if (version !== selectionVersion || loadVersion !== auditLoadVersion) return;
    auditElement.replaceChildren();
    if (!entries.length) {
      auditElement.append(createEmpty("No ledger records yet", "New completed AI calls appear here. Earlier interactions were not backfilled."));
    }
    for (const entry of entries) {
      const card = element("article", "history-note");
      card.append(
        element("strong", null, `Call ${entry.modelInvocationId} · ${entry.invocationStatus}`),
        element("p", "patient-meta", `${entry.modelId} · ${entry.skillName} ${entry.skillVersion}`),
        element("p", "patient-meta",
          `${formatDate(entry.startedAt)} · ${entry.durationMs.toLocaleString()} ms · HTTP ${entry.httpStatusCode ?? "not received"}`),
        element("p", "patient-meta",
          `Ledger transaction ${entry.ledgerTransactionId}${entry.briefingId ? ` · Briefing ${entry.briefingId}` : ""}`)
      );
      if (entry.errorMessage) card.append(element("p", "error-state", entry.errorMessage));
      for (const [label, json] of [["Request JSON", entry.requestJson], ["Response JSON", entry.responseJson]]) {
        const source = element("details", "history-source");
        source.append(element("summary", null, label), element("pre", "audit-json", json ?? "No response received."));
        card.append(source);
      }
      auditElement.append(card);
    }
  } catch (error) {
    if (version !== selectionVersion || loadVersion !== auditLoadVersion) return;
    showError(auditElement, error.message);
  } finally {
    if (loadVersion === auditLoadVersion) refreshAuditButton.disabled = false;
  }
}

document.querySelector("#open-audit").addEventListener("click", () => {
  auditPanel.showModal();
  loadAuditHistory();
});
refreshAuditButton.addEventListener("click", loadAuditHistory);
generateButton.addEventListener("click", generateBriefing);
refreshButton.addEventListener("click", loadQueue);
loadQueue();