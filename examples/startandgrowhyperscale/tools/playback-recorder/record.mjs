// Records each Caldova app sequence (playback mode) to its own native 4K (3840x2160) MP4.
// Pages are captured at full resolution (~9 fps on a typical machine); the pointer and click
// ripples are drawn in a second pass at 25 fps from the recorded pointer track, so motion stays smooth.
// Usage: node record.mjs [clipName ...]   (default: all clips, in order)
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import ffmpegPath from 'ffmpeg-static';

const BASE = process.env.CALDOVA_URL ?? 'http://localhost:5096';
const OUT = process.env.CLIP_DIR ?? path.resolve('clips');
const FPS = 25;
const CW = 1536, CH = 864, DSF = 2.5;   // CSS viewport (125% of 1920x1080) rendered at 2.5x
const W = CW * DSF, H = CH * DSF;       // 3840x2160 output
const CURSOR = { w: 28 * DSF, h: 28 * DSF, hotX: 3 * DSF, hotY: 2 * DSF };
const RING = { size: 44 * DSF, ms: 380 };
mkdirSync(OUT, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));
let mouse = { x: CW / 2, y: CH / 2 };
let active = null; // clip currently recording; receives pointer and click events

function ffmpeg(args, cwd) {
  const p = spawn(ffmpegPath, ['-y', '-loglevel', 'error', ...args], { cwd, stdio: ['pipe', 'inherit', 'inherit'] });
  return { proc: p, done: new Promise((resolve, reject) => p.on('close', code => code === 0 ? resolve() : reject(new Error(`ffmpeg exited ${code}`)))) };
}

async function makeOverlays(browser) {
  const page = await (await browser.newContext({ viewport: { width: 200, height: 200 }, deviceScaleFactor: 1 })).newPage();
  const cursorSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${CURSOR.w}" height="${CURSOR.h}" viewBox="0 0 28 28"><path d="M3 2 L3 22 L8.5 17 L12.5 26 L16 24.5 L12 15.5 L19.5 15.5 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
  const ringSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${RING.size}" height="${RING.size}" viewBox="0 0 44 44"><circle cx="22" cy="22" r="18" fill="rgba(197,138,22,.18)" stroke="rgba(197,138,22,.95)" stroke-width="3"/></svg>`;
  for (const [file, svg] of [['cursor.png', cursorSvg], ['ring.png', ringSvg]]) {
    await page.setContent(`<body style="margin:0;background:transparent">${svg}</body>`);
    await page.locator('svg').screenshot({ path: path.join(OUT, file), omitBackground: true });
  }
  await page.context().close();
}

async function pointer(page, x, y) {
  await page.mouse.move(x, y);
  mouse = { x, y };
  active?.track.push([Date.now() - active.t0, x, y]);
}

// Eased pointer glide; each intermediate position is logged for the cursor overlay.
async function glide(page, x, y) {
  const from = { ...mouse };
  const dist = Math.hypot(x - from.x, y - from.y);
  const duration = Math.min(950, Math.max(320, 260 + dist * 0.75));
  const t = Date.now();
  for (;;) {
    const k = Math.min(1, (Date.now() - t) / duration);
    const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
    await pointer(page, from.x + (x - from.x) * e, from.y + (y - from.y) * e);
    if (k >= 1) break;
    await sleep(12);
  }
}

async function moveTo(page, locator, settle = 350) {
  await locator.waitFor({ state: 'visible' });
  for (let i = 0; i < 3; i++) {
    const b = await locator.boundingBox();
    if (b && b.y >= 90 && b.y + Math.min(b.height, CH / 2) <= CH - 30) break;
    if (b) await scrollBy(page, b.y - CH / 3);
  }
  const box = await locator.boundingBox();
  if (!box) throw new Error('Element not visible');
  await glide(page, box.x + box.width / 2, box.y + box.height / 2);
  await sleep(settle);
}

async function click(page, locator) {
  await moveTo(page, locator);
  active?.clicks.push([Date.now() - active.t0, mouse.x, mouse.y]);
  await page.mouse.down();
  await sleep(90);
  await page.mouse.up();
  await sleep(250);
}

async function wander(page, points, pause = 600) {
  for (const [x, y] of points) {
    await glide(page, x, y);
    await sleep(pause);
  }
}

async function scrollBy(page, total, step = 60) {
  const n = Math.max(1, Math.round(Math.abs(total) / step));
  for (let i = 0; i < n; i++) { await page.mouse.wheel(0, Math.sign(total) * step); await sleep(28); }
  await sleep(400);
}

async function scrollToTop(page) {
  const y = await page.evaluate(() => window.scrollY);
  if (y > 0) await scrollBy(page, -y);
}

class Clip {
  constructor(page, name) { this.page = page; this.name = name; }
  async start() {
    const prefix = `${String(order.indexOf(this.name) + 1).padStart(2, '0')}-${this.name}`;
    this.file = `${prefix}.mp4`;
    this.raw = `${prefix}.raw.mkv`;
    this.cmds = `${prefix}.cmds.txt`;
    // Pass 1: full-resolution page frames, held to a constant 25 fps, near-lossless.
    this.ff = ffmpeg(['-f', 'image2pipe', '-c:v', 'mjpeg', '-framerate', String(FPS), '-i', '-',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '10', '-pix_fmt', 'yuv420p', this.raw], OUT);
    this.cdp = await this.page.context().newCDPSession(this.page);
    this.latest = null;
    this.capturing = true;
    this.frames = 0;
    this.capture = (async () => {
      while (this.capturing) {
        try {
          const shot = await this.cdp.send('Page.captureScreenshot', { format: 'jpeg', quality: 92, optimizeForSpeed: true });
          this.latest = Buffer.from(shot.data, 'base64');
          this.frames++;
        } catch { await sleep(20); }
      }
    })();
    while (!this.latest) await sleep(20);
    this.t0 = Date.now();
    this.track = [[0, mouse.x, mouse.y]];
    this.clicks = [];
    this.written = 0;
    this.timer = setInterval(() => this.pump(), 1000 / FPS / 2);
    active = this;
    console.log(`● recording ${this.name}`);
  }
  pump() {
    const due = Math.floor((Date.now() - this.t0) / 1000 * FPS);
    while (this.written < due) { this.ff.proc.stdin.write(this.latest); this.written++; }
  }
  commands() {
    const lines = [];
    let j = 0, last = '';
    for (let f = 0; f < this.written; f++) {
      const ms = f * 1000 / FPS;
      while (j + 1 < this.track.length && this.track[j + 1][0] <= ms) j++;
      const [, x, y] = this.track[j];
      const cx = Math.round(x * DSF - CURSOR.hotX), cy = Math.round(y * DSF - CURSOR.hotY);
      const ring = this.clicks.find(([t]) => ms >= t && ms < t + RING.ms);
      const rx = ring ? Math.round(ring[1] * DSF - RING.size / 2) : -2000;
      const ry = ring ? Math.round(ring[2] * DSF - RING.size / 2) : -2000;
      const key = `${cx},${cy},${rx},${ry}`;
      if (key === last) continue;
      last = key;
      lines.push(`${(ms / 1000).toFixed(3)} overlay@cur x ${cx}, overlay@cur y ${cy}, overlay@ring x ${rx}, overlay@ring y ${ry};`);
    }
    return lines.join('\n');
  }
  async stop() {
    this.pump();
    active = null;
    clearInterval(this.timer);
    this.capturing = false;
    await this.capture;
    await this.cdp.detach().catch(() => { });
    this.ff.proc.stdin.end();
    await this.ff.done;
    const seconds = this.written / FPS;
    writeFileSync(path.join(OUT, this.cmds), this.commands());
    // Pass 2: draw the pointer and click ripples at 25 fps, then encode the deliverable.
    const graph = `[0:v]sendcmd=f=${this.cmds}[v];[v][1:v]overlay@ring=x=-2000:y=-2000:eval=frame:shortest=1[r];` +
      `[r][2:v]overlay@cur=x=-2000:y=-2000:eval=frame:shortest=1,format=yuv420p`;
    await ffmpeg(['-i', this.raw, '-loop', '1', '-i', 'ring.png', '-loop', '1', '-i', 'cursor.png',
      '-filter_complex', graph, '-c:v', 'libx264', '-preset', 'medium', '-crf', '17', '-r', String(FPS),
      '-movflags', '+faststart', this.file], OUT).done;
    rmSync(path.join(OUT, this.raw), { force: true });
    rmSync(path.join(OUT, this.cmds), { force: true });
    console.log(`■ ${this.name}: ${seconds.toFixed(1)} s, page capture ${(this.frames / seconds).toFixed(1)} fps → ${path.join(OUT, this.file)}`);
  }
}

async function record(page, name, body) {
  const clip = new Clip(page, name);
  await clip.start();
  try { await body(); } finally { await clip.stop(); }
}

async function ready(page, url) {
  await page.goto(BASE + url);
  await page.waitForLoadState('networkidle');
  await sleep(2500); // Blazor circuit connects
  await page.mouse.move(mouse.x, mouse.y);
}
const text = (page, s) => page.getByText(s, { exact: false }).first();

const clips = {
  async 'p1-run'(page) {
    await ready(page, '/');
    await record(page, 'p1-run', async () => {
      await sleep(3000);
      await wander(page, [[560, 450], [1200, 500]], 700);
      await click(page, page.getByRole('button', { name: /Run/ }));
      await text(page, 'Clinic day complete').waitFor({ timeout: 15 * 60_000 });
      await sleep(4000);
      await click(page, page.getByText('Behind the chart · SQL workload and samples'));
      await sleep(600);
      await moveTo(page, page.locator('details.panel pre.code'), 400);
      await sleep(6000);
      await scrollToTop(page);
      await sleep(2000);
    });
  },
  async 'p1-paused'(page) {
    await text(page, 'Paused · no compute charges').waitFor({ timeout: 6 * 60_000 });
    await sleep(2000);
    await record(page, 'p1-paused', async () => {
      await sleep(3000);
      await wander(page, [[1200, 560], [1240, 720], [640, 640]], 1500);
      await sleep(5000);
    });
  },
  async 'p1-resume'(page) {
    await record(page, 'p1-resume', async () => {
      await sleep(2500);
      await click(page, page.getByRole('button', { name: /Sign in \(resume\)/ }));
      await text(page, 'First sign-in completed in').waitFor({ timeout: 90_000 });
      await sleep(7000);
    });
  },
  async 'p2-acquisitions'(page) {
    await ready(page, '/network');
    await record(page, 'p2-acquisitions', async () => {
      await sleep(3000);
      await wander(page, [[340, 300], [770, 300], [1200, 300]], 1400);
      await moveTo(page, page.getByRole('heading', { name: /One scheduling network/ }), 500);
      await sleep(5000);
    });
  },
  async 'p2-verify'(page) {
    await ready(page, '/verify');
    await record(page, 'p2-verify', async () => {
      await sleep(3000);
      await click(page, page.getByRole('button', { name: /Check network/ }));
      await text(page, '✓ Reachable').waitFor({ timeout: 15_000 });
      await sleep(1500);
      await wander(page, [[340, 420], [770, 420], [1200, 420]], 1100);
      await moveTo(page, page.getByRole('heading', { name: 'What the app runs' }), 400);
      await sleep(6000);
    });
  },
  async 'p2-scale'(page) {
    await ready(page, '/pool');
    const reset = page.getByRole('button', { name: /Reset/ });
    if (await reset.isEnabled()) await reset.click();
    await sleep(1000);
    await record(page, 'p2-scale', async () => {
      await sleep(3000);
      await click(page, page.getByRole('button', { name: /Start workload/ }));
      await sleep(25_000);
      await click(page, page.getByRole('button', { name: 'Scale pool to 16 vCores' }));
      await text(page, 'Scale complete').waitFor({ timeout: 120_000 });
      await sleep(12_000);
    });
  },
  async 'p2-growth'(page) {
    if (!page.url().endsWith('/pool')) throw new Error('Run p2-scale first; growth continues the same workload.');
    await record(page, 'p2-growth', async () => {
      await sleep(2000);
      await click(page, page.getByRole('button', { name: 'Load Northbrook encounter history' }));
      await sleep(1500);
      await moveTo(page, page.locator('table.pool-storage'), 500);
      await text(page, 'History loaded').waitFor({ timeout: 180_000 });
      await sleep(3000);
      await scrollBy(page, 400);
      await sleep(6000);
    });
  },
  async 'p2-search-book'(page, browser) {
    await ready(page, '/appointments');
    const colleague = await (await browser.newContext({ viewport: { width: CW, height: CH }, deviceScaleFactor: DSF })).newPage();
    await record(page, 'p2-search-book', async () => {
      await sleep(3000);
      await click(page, page.getByRole('button', { name: /Find openings/ }));
      await sleep(4500);
      await click(page, page.getByLabel('Search the entire network'));
      await click(page, page.getByRole('button', { name: /Find openings/ }));
      await sleep(4500);
      await moveTo(page, page.locator('table.slots'), 2500);
      const summary = page.getByText('Behind the view · native cross-database joins');
      await click(page, summary);
      await sleep(600);
      await moveTo(page, page.locator('details.panel pre.code'), 400);
      await sleep(7000);
      await scrollToTop(page);
      await moveTo(page, page.locator('table.slots'), 800);
      await click(page, page.locator('table.slots tbody tr').first().getByRole('button', { name: 'Book slot' }));
      await sleep(3000);
      await moveTo(page, page.getByRole('heading', { name: /^Booking · one transaction/ }), 400);
      await sleep(8000);
      // A colleague in another session books the next Ridgeview opening first.
      await colleague.goto(BASE + '/appointments');
      await colleague.waitForLoadState('networkidle');
      await sleep(2500);
      await colleague.getByLabel('Search the entire network').check();
      await colleague.getByRole('button', { name: /Find openings/ }).click();
      await colleague.locator('table.slots tbody tr').first().waitFor();
      await colleague.locator('table.slots tbody tr').first().getByRole('button', { name: 'Book slot' }).click();
      await sleep(1500);
      await scrollToTop(page);
      await moveTo(page, page.locator('table.slots'), 800);
      await click(page, page.locator('table.slots tbody tr').first().getByRole('button', { name: 'Book slot' }));
      await sleep(5000);
      await scrollToTop(page);
      await moveTo(page, page.locator('#specialty'), 500);
      await page.locator('#specialty').selectOption('Pediatrics');
      await sleep(800);
      await click(page, page.getByRole('button', { name: /Find openings/ }));
      await sleep(7000);
    });
    await colleague.context().close();
  },
};

const order = ['p1-run', 'p1-paused', 'p1-resume', 'p2-acquisitions', 'p2-verify', 'p2-scale', 'p2-growth', 'p2-search-book'];
const selected = process.argv.slice(2).length ? process.argv.slice(2) : order;
const browser = await chromium.launch({ channel: 'msedge', headless: true, args: [`--force-device-scale-factor=${DSF}`, `--window-size=${CW},${CH}`] });
const context = await browser.newContext({ viewport: { width: CW, height: CH }, deviceScaleFactor: DSF });
await makeOverlays(browser);
const page = await context.newPage();
try {
  for (const name of selected) {
    if (!clips[name]) throw new Error(`Unknown clip ${name}`);
    await clips[name](page, browser);
  }
} finally {
  await browser.close();
}
