import { chromium } from 'playwright-core';
import ffmpeg from 'ffmpeg-static';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile, access } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { once } from 'node:events';

const root = dirname(fileURLToPath(import.meta.url));
const output = join(root, 'output');
const check = process.argv.includes('--check');
const dark = process.argv.includes('--dark');
const basename = `caldova-architecture${dark ? '-dark' : ''}`;
const fps = 30;
const duration = 30;
const width = 3840;
const height = 2160;
const filename = join(output, `${basename}-4k.mp4`);
const routes = new Map([
  ['/', ['index.html', 'text/html']],
  ['/animation.mjs', ['animation.mjs', 'text/javascript']],
]);
const server = createServer(async (req, res) => {
  const route = routes.get(new URL(req.url, 'http://localhost').pathname);
  if (!route) { res.writeHead(404); res.end('Not found'); return; }
  try {
    const body = await readFile(join(root, route[0]));
    res.writeHead(200, { 'Content-Type': route[1] }); res.end(body);
  } catch (error) {
    console.error(error);
    res.writeHead(500); res.end('Unable to read animation source');
  }
});
let browser;
let encoder;
let encoderDone;
try {
  await mkdir(output, { recursive: true });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const edgePaths = [
    process.env.CALDOVA_VIDEO_BROWSER,
    join(process.env['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
    join(process.env.ProgramFiles ?? 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
  ].filter(Boolean);
  let executablePath;
  for (const candidate of edgePaths) {
    try { await access(candidate); executablePath = candidate; break; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  if (!executablePath) throw new Error('Microsoft Edge not found. Set CALDOVA_VIDEO_BROWSER to a Chromium browser executable.');
  browser = await chromium.launch({ executablePath, headless: true });
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 2 });
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/?render${dark ? '&dark' : ''}`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => typeof window.renderFrame === 'function');
  assert.equal(await page.evaluate(() => document.documentElement.dataset.theme), dark ? 'dark' : 'light');
  const { preparationTiming, retrievalTiming, embeddingFlows, indexPanel, sql } = await page.evaluate(async () => {
    const { preparationTiming, retrievalTiming, flows, indexPanel, nodes } = await import('/animation.mjs');
    return { preparationTiming, retrievalTiming, indexPanel, sql: nodes.sql,
      embeddingFlows: flows.filter((flow) => flow.from === 'embedding' || flow.to === 'embedding')
        .map(({ from, to, start, end }) => ({ from, to, start, end })) };
  });
  for (const phase of [...Object.values(preparationTiming), ...Object.values(retrievalTiming)]) {
    assert.ok(phase.start >= 0 && phase.start < phase.end && phase.end <= duration, 'Valid retrieval phase');
  }
  assert.equal(preparationTiming.loadPassages.start, 0, 'Corpus preparation starts the video');
  assert.ok(preparationTiming.loadPassages.end <= preparationTiming.embeddingRequest.start, 'Load passages before embedding');
  assert.ok(preparationTiming.embeddingRequest.end <= preparationTiming.storeVectors.start, 'Generate passage vectors before storing');
  assert.ok(preparationTiming.storeVectors.end <= preparationTiming.buildIndex.start, 'Store passage vectors before indexing');
  assert.ok(preparationTiming.buildIndex.end <= retrievalTiming.conversation.start, 'Build index before the app question');
  assert.deepEqual(embeddingFlows, [
    { from: 'sql', to: 'embedding', ...preparationTiming.embeddingRequest },
    { from: 'embedding', to: 'sql', ...preparationTiming.storeVectors },
  ], 'Exactly one embedding round trip, during corpus preparation only');
  assert.ok(preparationTiming.buildIndex.end <= retrievalTiming.vectorSearch.start, 'Access index only after creation');
  assert.ok(indexPanel.x > sql.x && indexPanel.y > sql.y &&
    indexPanel.x + indexPanel.w < sql.x + sql.w && indexPanel.y + indexPanel.h < sql.y + sql.h,
  'DiskANN index is fully inside Hyperscale');
  const embeddingStaysIdle = await page.evaluate(async () => {
    const { nodes, renderFrame } = await import('/animation.mjs');
    const { x, y, w, h } = nodes.embedding;
    const context = document.querySelector('canvas').getContext('2d');
    const pixels = () => context.getImageData((x - 3) * 2, (y - 3) * 2, (w + 6) * 2, (h + 6) * 2).data;
    renderFrame(8);
    const reference = pixels();
    return [10, 17.3, 18.6, 20.2, 24, 27, 29.5].every((t) => {
      renderFrame(t);
      return pixels().every((value, i) => value === reference[i]);
    });
  });
  assert.ok(embeddingStaysIdle, 'Embedding model does not animate or regenerate embeddings after preparation');
  const indexScenes = await page.evaluate(async () => {
    const { indexPanel, renderFrame, preparationTiming, retrievalTiming } = await import('/animation.mjs');
    const context = document.querySelector('canvas').getContext('2d');
    return [0, preparationTiming.buildIndex.end, (retrievalTiming.vectorSearch.start + retrievalTiming.vectorSearch.end) / 2].map((t) => {
      renderFrame(t);
      const { x, y, w, h } = indexPanel;
      return Array.from(context.getImageData(x * 2, y * 2, w * 2, h * 2).data);
    });
  });
  assert.notDeepEqual(indexScenes[0], indexScenes[1], 'Index visibly created after embeddings are stored');
  assert.notDeepEqual(indexScenes[1], indexScenes[2], 'Search visibly accesses the existing index');
  const stationaryCards = await page.evaluate(async () => {
    const { nodes, renderFrame } = await import('/animation.mjs');
    const context = document.querySelector('canvas').getContext('2d');
    return [0, 0.5, 1, 4, 10, 22, 29.5].map((t) => {
      renderFrame(t);
      return Object.values(nodes).map(({ x, y, h }) =>
        Array.from(context.getImageData((x + 12) * 2, (y + h - 12) * 2, 1, 1).data));
    });
  });
  for (const sample of stationaryCards) {
    assert.deepEqual(sample, stationaryCards.at(-1), 'All cards fully visible in fixed positions from frame zero');
  }
  async function frame(t) {
    const base64 = await page.evaluate((seconds) => {
      window.renderFrame(seconds);
      return document.querySelector('canvas').toDataURL('image/png').split(',')[1];
    }, t);
    return Buffer.from(base64, 'base64');
  }
  const sampleTimes = [0.7, 2.3, 4, 6.2, 7.7, 9.2, 10.6, 13.2, 14.7, 16, 17.3, 18.6, 20.2, 22.5, 27, 29.5];
  const samples = [];
  for (const t of sampleTimes) {
    const image = await frame(t);
    assert.equal(image.readUInt32BE(16), width, 'PNG width');
    assert.equal(image.readUInt32BE(20), height, 'PNG height');
    samples.push(image);
  }
  assert.equal(new Set(samples.map((image) => image.toString('base64'))).size, samples.length, 'Every scene must be visually distinct');
  assert.deepEqual(pageErrors, [], 'Browser errors');
  await writeFile(join(output, `${basename}-preview.png`), samples.at(-1));
  await writeFile(join(output, `${basename}-opening.png`), await frame(0));

  // A contact sheet exposes every animation beat for visual inspection.
  await page.evaluate(async ({ images }) => {
    const sheet = document.createElement('canvas');
    sheet.width = 1920; sheet.height = 1080;
    const context = sheet.getContext('2d');
    for (let i = 0; i < images.length; i++) {
      const image = new Image();
      image.src = `data:image/png;base64,${images[i]}`;
      await image.decode();
      context.drawImage(image, (i % 4) * 480, Math.floor(i / 4) * 270, 480, 270);
    }
    window.contactSheet = sheet.toDataURL('image/png').split(',')[1];
  }, { images: samples.map((image) => image.toString('base64')) });
  await writeFile(join(output, dark ? 'contact-sheet-dark.png' : 'contact-sheet.png'), Buffer.from(await page.evaluate(() => window.contactSheet), 'base64'));
  console.log(`Scene checks passed (${dark ? 'dark' : 'light'}): ${sampleTimes.length} distinct 4K frames, no browser errors, embedding model used once, index built then accessed inside Hyperscale, stationary cards.`);
  if (!check) {
    encoder = spawn(ffmpeg, [
      '-hide_banner', '-y', '-f', 'image2pipe', '-framerate', String(fps), '-vcodec', 'png', '-i', 'pipe:0',
      '-an', '-c:v', 'libx264', '-preset', 'fast', '-crf', '17', '-pix_fmt', 'yuv420p',
      '-vf', 'scale=iw:ih:out_color_matrix=bt709:out_range=tv',
      '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-color_range', 'tv',
      '-movflags', '+faststart', '-r', String(fps), '-t', String(duration), filename,
    ], { windowsHide: true, stdio: ['pipe', 'ignore', 'pipe'] });
    let diagnostics = '';
    encoder.stderr.on('data', (data) => { diagnostics = (diagnostics + data).slice(-6000); });
    let encoderFailure;
    encoderDone = new Promise((resolve) => {
      encoder.once('error', (error) => { encoderFailure = error; resolve(); });
      encoder.once('close', (code) => {
        if (code !== 0) encoderFailure ??= new Error(`FFmpeg exited ${code}:\n${diagnostics}`);
        resolve();
      });
    });
    encoder.stdin.on('error', (error) => { encoderFailure ??= error; });
    for (let i = 0; i < duration * fps; i++) {
      const image = await frame(i / fps);
      if (encoderFailure) throw encoderFailure;
      if (!encoder.stdin.write(image)) await once(encoder.stdin, 'drain');
      if (i % 90 === 0) console.log(`Rendering ${(i / fps).toFixed(0)} / ${duration} seconds`);
    }
    encoder.stdin.end();
    await encoderDone;
    if (encoderFailure) throw encoderFailure;
    assert.deepEqual(pageErrors, [], 'Browser errors during rendering');

    // Decode the entire result, not just its container header.
    const verify = spawn(ffmpeg, ['-hide_banner', '-i', filename, '-map', '0:v:0', '-f', 'null', '-'],
      { windowsHide: true, stdio: ['ignore', 'ignore', 'pipe'] });
    let report = '';
    verify.stderr.on('data', (data) => { report += data; });
    const [exitCode] = await once(verify, 'close');
    assert.equal(exitCode, 0, report);
    assert.match(report, /3840x2160/, '4K resolution');
    assert.match(report, /30 fps/, '30 fps');
    assert.match(report, /Duration: 00:00:30\.00/, 'Exactly 30 seconds');
    assert.match(report, /frame=\s*900\b/, '900 decoded frames');
    assert.doesNotMatch(report, /Stream #.*Audio:/, 'No audio stream');
    assert.doesNotMatch(report, /Stream #.*Subtitle:/, 'No subtitle stream');
    await writeFile(join(output, dark ? 'verification-dark.txt' : 'verification.txt'), report);
    console.log(`Verified: 3840x2160, 30 fps, 900 frames, 30 seconds, no audio.\n${filename}`);
  }
} finally {
  if (encoder && encoder.exitCode === null) {
    encoder.kill();
    await encoderDone;
  }
  await browser?.close();
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
}
