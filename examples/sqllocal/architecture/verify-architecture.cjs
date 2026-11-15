const assert = require("node:assert/strict");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const { chromium } = require("playwright");

async function main() {
  const browser = await chromium.launch({ channel: "msedge", headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    const url = pathToFileURL(path.join(__dirname, "architecture-player.html"));
    await page.goto(url.href);
    await page.waitForFunction(() => Boolean(window.caldova));

    const chapters = await page.evaluate(() => window.caldova.chapters);
    const briefing = chapters.find(chapter => chapter.id === "briefing");
    const search = chapters.find(chapter => chapter.id === "search");
    const audit = chapters.find(chapter => chapter.id === "audit");
    const disconnected = chapters.find(chapter => chapter.id === "disconnected");
    assert.ok(briefing && search && audit && disconnected);
    const overview = chapters.find(chapter => chapter.id === "overview");
    assert.match(overview.steps[0].text, /Azure Virtual Desktop/);
    assert.ok(overview.steps[0].flows.includes("client-avd"));
    assert.ok(overview.steps[0].flows.includes("avd-app"));

    const retrieval = briefing.steps.find(step => step.flows.includes("sql-embed"));
    assert.ok(retrieval, "History-enabled generation must show its own embedding call");
    assert.equal(retrieval.history, true);
    assert.match(retrieval.text, /ChiefConcern/);
    assert.match(retrieval.text, /TopK = 3/);
    const currentOnly = briefing.steps.find(step => /includeHistory = false/.test(step.payload));
    assert.ok(currentOnly, "Show the current-facts-only branch");
    assert.ok(!currentOnly.flows.includes("sql-embed"));
    assert.ok(currentOnly.flows.includes("sql-chat"));
    assert.match(currentOnly.text, /ReceivingBriefing 2\.0/);
    assert.match(search.steps.at(-1).text, /does not select evidence/);
    assert.match(search.steps.map(step => step.text).join(" "), /0\.82.*0\.10/);
    assert.doesNotMatch(JSON.stringify(chapters), /ReceivingBriefing 1\.[01]|skill 1\.[01]|Include in briefing|Choose notes explicitly|Nemotron is not called by briefing generation/);

    let renderedSteps = 0;
    const layouts = [[1920, 1080], [1536, 864], [1366, 768], [1280, 720], [1024, 768]]
      .flatMap(([width, height]) => [false, true].map(exporting => ({ width, height, exporting })));
    for (const { width, height, exporting } of layouts) {
      await page.setViewportSize({ width, height });
      await page.goto(`${url.href}${exporting ? "?export=1" : ""}`);
      await page.waitForFunction(() => Boolean(window.caldova));
      for (const chapter of chapters) {
        let time = 0;
        for (const step of [chapter.summary, ...chapter.steps]) {
          const summary = step === chapter.summary;
          const expected = summary && chapter.sequence ? chapter.steps[0] : step;
          const result = await page.evaluate(({ id, time }) => {
            const state = window.caldova.render(id, time);
            const bounds = document.querySelector("aside").getBoundingClientRect();
            const stage = document.querySelector(".stage").getBoundingClientRect();
            const diagram = document.getElementById("diagram");
            const scale = diagram.getScreenCTM();
            const overlaps = (a, b) => a.width > 0 && b.width > 0
              && a.left < b.right - 0.5 && a.right > b.left + 0.5
              && a.top < b.bottom - 0.5 && a.bottom > b.top + 0.5;
            const captions = [...document.querySelectorAll("header h1, .subtitle, #counter")]
              .map(element => element.getBoundingClientRect())
              .filter(rect => rect.width > 0 && rect.height > 0);
            const topActors = ["client", "cloud", "management"].map(id =>
              document.getElementById(id).getBoundingClientRect());
            topActors.push(document.querySelector("#avd-control text").getBoundingClientRect());
            const accessCard = document.querySelector("#client rect").getBoundingClientRect();
            const title = document.querySelector("h1").getBoundingClientRect();
            const connector = document.querySelector("#avd-control path");
            const start = connector.getPointAtLength(0).matrixTransform(diagram.getScreenCTM());
            const end = connector.getPointAtLength(connector.getTotalLength()).matrixTransform(diagram.getScreenCTM());
            const cloud = document.querySelector("#cloud > rect").getBoundingClientRect();
            const localControl = document.querySelector("#local-control > rect").getBoundingClientRect();
            const boundary = document.getElementById("local-boundary").getBoundingClientRect();
            const host = document.querySelector("#avd > rect").getBoundingClientRect();
            return {
              ...state,
              sceneTitle: state.title,
              title: document.querySelector("h1").textContent,
              titleFontSize: parseFloat(getComputedStyle(document.querySelector("h1")).fontSize),
              titleCentered: Math.abs(title.left + title.width / 2 - innerWidth / 2) <= 1
                && getComputedStyle(document.querySelector("h1")).textAlign === "center",
              modeLabel: document.getElementById("mode-label").textContent,
              sqlHosting: document.getElementById("sql-hosting").textContent,
              publicPortalShown: cloud.width > 0,
              localPortalShown: localControl.width > 0,
              publicControlOutside: cloud.width === 0 || cloud.bottom <= boundary.top,
              localControlInside: localControl.width === 0 || (localControl.left >= boundary.left
                && localControl.right <= boundary.right && localControl.top >= boundary.top
                && localControl.bottom <= boundary.bottom),
              portalLabelsFit: ["cloud", "local-control"].every(id => {
                const card = document.querySelector(`#${id} > rect`).getBoundingClientRect();
                return [...document.querySelectorAll(`#${id} text`)].every(text => {
                  const label = text.getBoundingClientRect();
                  return label.left >= card.left && label.right <= card.right
                    && label.top >= card.top && label.bottom <= card.bottom;
                });
              }),
              localControlClear: localControl.width === 0 || ["#mode-label", "#foundry > rect"].every(selector =>
                !overlaps(localControl, document.querySelector(selector).getBoundingClientRect())),
              hostingLabelsFit: [["sql-hosting", "sql"], ["foundry-hosting", "foundry"], ["foundry-gpu", "foundry"]]
                .every(([labelId, nodeId]) => {
                  const label = document.getElementById(labelId).getBoundingClientRect();
                  const card = document.querySelector(`#${nodeId} > rect`).getBoundingClientRect();
                  return label.left >= card.left && label.right <= card.right
                    && label.top >= card.top && label.bottom <= card.bottom;
                }),
              avdConnected: cloud.width === 0 || (Math.abs(start.x - cloud.left) <= 1
                && start.y >= cloud.top && start.y <= cloud.bottom
                && Math.abs(end.x - host.right) <= 1 && end.y >= host.top && end.y <= host.bottom),
              store: document.getElementById("store-title").textContent,
              immutable: document.getElementById("ledger-immutable").getBoundingClientRect().width > 0,
              immutableFits: (() => {
                const badge = document.getElementById("ledger-immutable").getBoundingClientRect();
                const store = document.querySelector("#store > rect").getBoundingClientRect();
                const title = document.getElementById("store-title").getBoundingClientRect();
                return badge.width === 0 || (badge.left >= store.left && badge.right <= store.right
                  && badge.top >= store.top && badge.bottom <= store.bottom && !overlaps(badge, title));
              })(),
              history: document.getElementById("result-detail").textContent,
              selectedView: [...document.querySelectorAll(".chapter-nav button")].findIndex(button =>
                button.hasAttribute("aria-current")),
              viewButtonCount: document.querySelectorAll(".navigation button").length,
              categoryColors: ["cloud", "avd", "sql", "foundry"].map(id =>
                getComputedStyle(document.querySelector(`#${id} > rect`)).stroke),
              brokenSvg: Boolean(document.querySelector("parsererror")),
              fits: document.documentElement.scrollWidth <= innerWidth
                && document.documentElement.scrollHeight <= innerHeight
                && bounds.bottom <= innerHeight,
              diagramDominates: stage.width >= innerWidth * 0.95
                && stage.height >= innerHeight * 0.85
                && diagram.viewBox.baseVal.width * scale.a >= innerWidth * 0.93,
              topClear: captions.every((rect, index) =>
                captions.slice(index + 1).every(other => !overlaps(rect, other))
                && topActors.every(actor => !overlaps(rect, actor)))
                && bounds.bottom < document.getElementById("local-boundary").getBoundingClientRect().top,
              remoteAccessShown: document.getElementById("avd").getBoundingClientRect().width > 0,
              sessionHostInside: (() => {
                const host = document.getElementById("avd").getBoundingClientRect();
                const local = document.getElementById("local-boundary").getBoundingClientRect();
                return host.width === 0 || (host.left >= local.left && host.right <= local.right
                  && host.top >= local.top && host.bottom <= local.bottom);
              })(),
              browserAndAppInsideHost: (() => {
                const host = document.querySelector("#avd > rect").getBoundingClientRect();
                return host.width === 0 || ["#avd-browser", "#app > rect"].every(selector => {
                  const child = document.querySelector(selector).getBoundingClientRect();
                  return child.left >= host.left && child.right <= host.right
                    && child.top >= host.top && child.bottom <= host.bottom;
                });
              })(),
              accessTextFits: [...document.querySelectorAll("#client text")].every(text =>
                text.getBoundingClientRect().right <= accessCard.right)
                && [...document.querySelectorAll("#avd text")].every(text =>
                  text.getBoundingClientRect().right <= document.querySelector("#avd rect").getBoundingClientRect().right),
              active: [...document.querySelectorAll(".wire.active")].map(route => route.id),
            };
          }, { id: chapter.id, time: summary ? undefined : time });
          assert.equal(result.sceneTitle, expected.title);
          assert.equal(result.title, "Caldova Regional Care Transfer Center");
          assert.ok(result.titleFontSize >= 30, "The central title must be larger than the previous 22px heading");
          assert.ok(result.titleCentered, "The application title must be centered at the top");
          assert.equal(result.modeLabel, step.disconnected ? "Disconnected deployment" : "Connected deployment");
          assert.match(result.sqlHosting, /Azure Local VM with Windows Server 2025/);
          assert.equal(result.publicPortalShown, !step.disconnected);
          assert.equal(result.localPortalShown, Boolean(step.disconnected));
          assert.ok(result.publicControlOutside, "The connected Azure portal/control plane must be outside Azure Local");
          assert.ok(result.localControlInside, "The disconnected Azure portal/control plane must be inside Azure Local");
          assert.ok(result.portalLabelsFit, "Portal and control plane labels must fit their cards");
          assert.ok(result.localControlClear, "The local control plane must not overlap mode labels or Foundry");
          assert.ok(result.hostingLabelsFit, "SQL VM and Foundry AKS/GPU labels must fit inside their components");
          assert.ok(result.avdConnected, "The AVD connector must touch both Azure and the local session host");
          assert.equal(result.store, (expected.store || chapter.store)[0]);
          assert.equal(result.immutable, Boolean(expected.immutable));
          assert.ok(result.immutableFits, "The immutable lock and label must fit without overlapping the ledger title");
          assert.equal(result.selectedView, chapters.indexOf(chapter), "The selected view's bottom button must be highlighted");
          assert.equal(result.viewButtonCount, 5, "There must be five single-level navigation buttons");
          assert.equal(new Set(result.categoryColors).size, 4, "AVD, VM, SQL, and Foundry must retain distinct colors");
          assert.deepEqual(result.active.sort(), [...expected.flows].sort());
          assert.equal(result.brokenSvg, false);
          assert.ok(result.fits, `Layout overflow: ${chapter.id}, ${step.title}, export=${exporting}`);
          assert.ok(result.diagramDominates, `Diagram must dominate the viewport: ${chapter.id}, export=${exporting}`);
          assert.ok(result.topClear, `Top text collision: ${chapter.id}, ${step.title}, ${width}x${height}, export=${exporting}`);
          assert.equal(result.remoteAccessShown, !step.disconnected, "Show AVD access for the current connected demo only");
          assert.ok(result.sessionHostInside, "The AVD session host runs inside Azure Local");
          assert.ok(result.browserAndAppInsideHost, "Both browser and ASP.NET app must be inside the AVD VM");
          assert.ok(result.accessTextFits, "AVD labels must fit the access card");
          if (step.history) assert.equal(result.history, "Include history: SQL top 3");
          if (!summary) time += step.duration;
          renderedSteps++;
        }
      }
    }

    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.clock.install();
    await page.goto(url.href);
    assert.equal(await page.locator('input[type="range"], #play, #previous, #next, #restart, #step-nav').count(), 0);
    assert.equal(await page.locator("details, .flow-details").count(), 0, "Remove Flow details from the player");
    for (const chapter of chapters) {
      await page.getByRole("navigation", { name: "Architecture sections" })
        .getByRole("button", { name: chapter.label, exact: true }).click();
      await page.clock.fastForward(60000);
      assert.equal(await page.locator("body").getAttribute("data-chapter"), chapter.id,
        "Each button must show its complete flow without automatic advancement");
      assert.equal(await page.locator("body").getAttribute("data-step"), "-1");
      assert.equal(await page.locator('.chapter-nav button[aria-current]').count(), 1);
      assert.equal(await page.locator('.chapter-nav button[aria-current]').textContent(), chapter.label);
      const buttons = await page.locator(".chapter-nav button").evaluateAll(elements => elements.map(button => {
        const style = getComputedStyle(button);
        return {
          selected: button.hasAttribute("aria-current"),
          border: style.borderTopColor,
          background: style.backgroundColor,
          text: style.color,
        };
      }));
      assert.equal(new Set(buttons.map(button => button.border)).size, 5, "Each view must have its own button color");
      for (const button of buttons) {
        if (button.selected) {
          assert.equal(button.background, button.border, "The selected button must fill solid with its own color");
          const luminance = color => {
            const channels = color.match(/[\d.]+/g).slice(0, 3).map(Number).map(value => {
              const normalized = value / 255;
              return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
            });
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
          };
          const values = [luminance(button.text), luminance(button.background)].sort((a, b) => a - b);
          assert.ok((values[1] + 0.05) / (values[0] + 0.05) >= 4.5, "Solid-fill button labels must remain readable");
        } else {
          assert.equal(button.background, "rgba(0, 0, 0, 0)", "Inactive buttons must return to an outline");
          assert.equal(button.text, button.border);
        }
      }
      assert.doesNotMatch(await page.locator("#counter").textContent(), /STEP/);
      const active = await page.locator(".wire.active").evaluateAll(routes => routes.map(route => route.id));
      assert.deepEqual(active.sort(), [...(chapter.sequence ? chapter.steps.at(-1) : chapter.summary).flows].sort());
    }
    const packetVisible = route => page.locator(`.packet[data-route="${route}"]`)
      .evaluateAll(dots => dots.some(dot => Number(dot.getAttribute("opacity")) > 0));
    await page.getByRole("button", { name: search.label, exact: true }).click();
    await page.clock.runFor(900);
    assert.ok(await packetVisible("sql-embed"), "Animate the query embedding request");
    assert.equal(await packetVisible("embed-sql"), false, "The embedding response follows the request");
    await page.clock.runFor(1800);
    assert.equal(await packetVisible("sql-embed"), false);
    assert.ok(await packetVisible("embed-sql"), "Animate the returned embedding");
    await page.clock.runFor(1800);
    assert.equal(await packetVisible("sql-embed"), false);
    assert.equal(await packetVisible("embed-sql"), false, "Stop model animation after the embedding returns");
    await page.clock.fastForward(60000);
    assert.equal(await packetVisible("sql-embed"), false, "Do not repeat the model call animation");
    assert.equal(await packetVisible("embed-sql"), false);
    await page.getByRole("button", { name: briefing.label, exact: true }).click();
    for (const interval of [900, 1800, 1800]) {
      await page.clock.runFor(interval);
      for (const route of ["sql-embed", "embed-sql"]) {
        assert.equal(await packetVisible(route), false, `Briefing must not animate ${route}`);
      }
    }
    assert.ok(await packetVisible("sql-chat"), "Keep the Briefing generation path animated");
    const assertAuditTraffic = async time => {
      const stage = Math.min(4, Math.floor(time / 1800));
      assert.equal(await page.locator("body").getAttribute("data-stage"), String(stage));
      assert.equal(await page.locator("#ledger-immutable").isVisible(), stage === 4,
        "Show the immutable lock only after the successful briefing and audit have been saved");
      for (const [route, activeStage] of [["sql-chat", 1], ["chat-sql", 2], ["work-store", 3], ["audit-read", 4]]) {
        assert.equal(await packetVisible(route), stage === activeStage,
          `Audit must sequence ${route} after its prerequisite, at ${time} ms`);
      }
      assert.equal(await packetVisible("sql-embed"), false);
      assert.equal(await packetVisible("embed-sql"), false);
    };
    await page.getByRole("button", { name: audit.label, exact: true }).click();
    let auditTime = 0;
    for (const time of [900, 2700, 4500, 6300, 8100, 17966]) {
      await page.clock.runFor(time - auditTime);
      auditTime = time;
      await assertAuditTraffic(time);
    }
    await page.clock.fastForward(60000);
    assert.equal(await packetVisible("sql-chat"), false, "Do not repeat generation after the audit is saved");
    assert.ok(await page.locator("#ledger-immutable").isVisible());
    await page.getByRole("button", { name: audit.label, exact: true }).click();
    await page.clock.runFor(2700);
    await assertAuditTraffic(2700);
    await page.getByRole("button", { name: disconnected.label, exact: true }).click();
    assert.equal(await page.locator("#cloud").isVisible(), false);
    assert.equal(await page.locator("#avd").isVisible(), false);
    assert.equal(await page.locator("#avd-control").isVisible(), false);
    assert.equal(await page.locator("#management").isVisible(), false);
    assert.ok(await page.locator("#local-control").isVisible());
    assert.equal(await page.locator("#client-access-label").textContent(), "LOCAL ACCESS");
    assert.equal(await page.locator("#counter").textContent(), "05 / 05");
    await page.clock.runFor(900);
    assert.ok(await packetVisible("client-app-local"), "Disconnected mode uses local browser access");
    await page.getByRole("button", { name: overview.label, exact: true }).click();
    assert.ok(await page.locator("#cloud").isVisible());
    assert.ok(await page.locator("#avd").isVisible());
    assert.equal(await page.locator("#local-control").isVisible(), false);
    for (const chapter of chapters) {
      await page.goto(`${url.href}?export=1&buttons=1&chapter=${chapter.id}`);
      assert.ok(await page.locator(".navigation").isVisible(), "Slide videos must retain the phase buttons");
      for (const time of [0, 900, 2700, 4500, 6300, 8100, 17966]) {
        await page.evaluate(({ id, time }) => window.caldova.render(id, undefined, time),
          { id: chapter.id, time });
        const selected = page.locator(".chapter-nav button[aria-current]");
        assert.equal(await selected.textContent(), chapter.label, "Keep the correct phase pressed for every video");
        assert.ok(await selected.evaluate(button => {
          const style = getComputedStyle(button);
          return style.backgroundColor === style.borderTopColor;
        }));
        assert.equal(await page.locator("body").getAttribute("data-step"), "-1",
          "Video exports show a complete phase, not timed substeps");
        for (const route of chapter.staticFlows || []) {
          assert.equal(await packetVisible(route), false, "Retain the model-animation restrictions in videos");
        }
        if (chapter.id === "search") {
          assert.equal(await packetVisible("sql-embed"), time === 900);
          assert.equal(await packetVisible("embed-sql"), time === 2700);
        }
        if (chapter.id === "audit" && time > 0) await assertAuditTraffic(time);
      }
    }
    assert.deepEqual(errors, [], "No browser script errors");
    console.log(`Verified ${renderedSteps} layouts, five fixed-phase video views with solid selected buttons, portal/control plane placement, model-animation exclusions, and disconnected/local-access mode.`);
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
