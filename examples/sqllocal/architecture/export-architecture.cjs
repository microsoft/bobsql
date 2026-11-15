const assert = require("node:assert/strict");
const { spawn, execFile } = require("node:child_process");
const { randomUUID } = require("node:crypto");
const { constants } = require("node:fs");
const fs = require("node:fs/promises");
const path = require("node:path");
const { Readable } = require("node:stream");
const { pipeline } = require("node:stream/promises");
const { pathToFileURL } = require("node:url");
const { promisify, parseArgs } = require("node:util");
const { chromium } = require("playwright");
const ffmpeg = require("@ffmpeg-installer/ffmpeg").path;

const execute = promisify(execFile);
const width = 1920, height = 1080, fps = 30, seconds = 18;
const frameCount = fps * seconds;

async function runFfmpeg(args) {
  return execute(ffmpeg, args, { windowsHide: true, encoding: "buffer", maxBuffer: 32 * 1024 * 1024 });
}

async function requireNewFile(file) {
  try {
    await fs.access(file);
  } catch (error) {
    if (error.code === "ENOENT") return;
    throw error;
  }
  throw new Error(`Refusing to overwrite ${file}. Choose a new output directory.`);
}

async function verifyVideo(file, buttons) {
  const { stdout, stderr } = await runFfmpeg([
    "-hide_banner", "-xerror", "-threads", "2", "-i", file,
    "-map", "0:v:0", "-an", "-f", "framemd5", "pipe:1",
  ]);
  const metadata = stderr.toString();
  assert.match(metadata, /Video: h264/);
  assert.match(metadata, /yuv420p/);
  assert.match(metadata, /1920x1080/);
  assert.match(metadata, /30 fps/);
  assert.match(metadata, /Duration: 00:00:18\.00/);
  assert.doesNotMatch(metadata, /Audio:/);
  const frames = stdout.toString().split(/\r?\n/).filter(line => line && !line.startsWith("#"));
  assert.equal(frames.length, frameCount, "Decode the entire expected video");
  assert.ok(new Set(frames.map(line => line.split(",").at(-1).trim())).size > 1,
    "The exported phase must animate, not hold a single still image");

  const bytes = await fs.readFile(file);
  let moov = -1, mdat = -1;
  for (let offset = 0; offset + 8 <= bytes.length;) {
    let size = bytes.readUInt32BE(offset);
    const type = bytes.toString("ascii", offset + 4, offset + 8);
    if (size === 1) size = Number(bytes.readBigUInt64BE(offset + 8));
    if (size === 0) size = bytes.length - offset;
    assert.ok(size >= 8 && offset + size <= bytes.length, "Valid MP4 atom size");
    if (type === "moov") moov = offset;
    if (type === "mdat") mdat = offset;
    offset += size;
  }
  assert.ok(moov >= 0 && mdat > moov, "Use fast-start MP4 layout for slide playback");

  const samples = [0, Math.floor(frameCount / 2), frameCount - 1];
  const { stdout: pixels } = await runFfmpeg([
    "-hide_banner", "-loglevel", "error", "-xerror", "-threads", "2", "-i", file,
    "-vf", `select='${samples.map(frame => `eq(n,${frame})`).join("+")}'`,
    "-vsync", "0", "-an", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1",
  ]);
  const frameBytes = width * height * 3;
  assert.equal(pixels.length, samples.length * frameBytes);
  for (let sample = 0; sample < samples.length; sample++) {
    for (const button of buttons) {
      const offset = sample * frameBytes + (button.y * width + button.x) * 3;
      button.color.forEach((value, channel) => {
        assert.ok(Math.abs(pixels[offset + channel] - value) <= 10,
          `Button color changed or disappeared in encoded frame ${samples[sample]}`);
      });
    }
  }
}

async function encode(page, chapter, file) {
  const encoder = spawn(ffmpeg, [
    "-hide_banner", "-loglevel", "error", "-n",
    "-f", "image2pipe", "-framerate", String(fps), "-vcodec", "png", "-i", "pipe:0",
    "-an", "-c:v", "libx264", "-preset", "medium", "-crf", "18",
    "-pix_fmt", "yuv420p", "-r", String(fps), "-threads", "2", "-movflags", "+faststart",
    "-metadata", `title=Caldova Regional Care - ${chapter.title}`,
    "-metadata", "comment=Conceptual architecture animation, not live traffic. Silent; no narration.",
    file,
  ], { windowsHide: true, stdio: ["pipe", "ignore", "pipe"] });
  let diagnostics = "";
  encoder.stderr.on("data", chunk => { diagnostics += chunk; });
  const completed = new Promise((resolve, reject) => {
    encoder.once("error", reject);
    encoder.once("close", code => {
      if (code === 0) resolve();
      else reject(new Error(`FFmpeg exited ${code}: ${diagnostics}`));
    });
  });
  async function* frames() {
    for (let frame = 0; frame < frameCount; frame++) {
      await page.evaluate(({ id, time }) => window.caldova.render(id, undefined, time),
        { id: chapter.id, time: frame * 1000 / fps });
      yield await page.screenshot({ type: "png", animations: "disabled" });
      if ((frame + 1) % (fps * 6) === 0) {
        console.log(`${chapter.label}: ${frame + 1}/${frameCount} frames`);
      }
    }
  }
  try {
    await Promise.all([completed, pipeline(Readable.from(frames()), encoder.stdin)]);
  } catch (error) {
    if (encoder.exitCode === null) encoder.kill();
    throw new Error(`Could not export ${chapter.label}: ${diagnostics}`, { cause: error });
  }
}

async function main() {
  const { values, positionals } = parseArgs({
    options: { chapter: { type: "string" } },
    allowPositionals: true,
  });
  if (positionals.length > 1) throw new Error("Usage: npm run export -- [output-directory] [--chapter audit]");
  const output = path.resolve(positionals[0] || path.join(__dirname, "exports"));
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ channel: "msedge", headless: true });
  try {
    const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    const url = pathToFileURL(path.join(__dirname, "architecture-player.html"));
    await page.goto(`${url.href}?export=1&buttons=1`);
    const available = await page.evaluate(() => window.caldova.chapters.map(({ id, title, label, file }) =>
      ({ id, title, label, file })));
    assert.equal(available.length, 5);
    const chapters = values.chapter ? available.filter(chapter => chapter.id === values.chapter) : available;
    if (!chapters.length) throw new Error(`Unknown chapter: ${values.chapter}`);
    for (const chapter of chapters) await requireNewFile(path.join(output, `${chapter.file}.mp4`));

    for (const chapter of chapters) {
      const target = path.join(output, `${chapter.file}.mp4`);
      const temporary = path.join(output, `.render-${randomUUID()}.mp4`);
      try {
        await page.goto(`${url.href}?export=1&buttons=1&chapter=${chapter.id}`);
        await page.evaluate(() => document.fonts.ready);
        assert.ok(await page.locator(".navigation").isVisible());
        assert.equal(await page.locator(".chapter-nav button[aria-current]").textContent(), chapter.label);
        const buttons = await page.locator(".chapter-nav button").evaluateAll(elements => elements.map(button => {
          const box = button.getBoundingClientRect();
          const style = getComputedStyle(button);
          const background = style.backgroundColor === "rgba(0, 0, 0, 0)"
            ? getComputedStyle(document.body).backgroundColor : style.backgroundColor;
          if (button.hasAttribute("aria-current") && style.backgroundColor !== style.borderTopColor) {
            throw new Error("The selected phase button is not filled solid");
          }
          return {
            x: Math.round(box.right - 20),
            y: Math.round(box.top + box.height / 2),
            color: background.match(/\d+/g).slice(0, 3).map(Number),
          };
        }));
        await encode(page, chapter, temporary);
        assert.deepEqual(errors, [], "No browser rendering errors");
        await verifyVideo(temporary, buttons);
        await fs.copyFile(temporary, target, constants.COPYFILE_EXCL);
        console.log(`Verified ${target} | ${seconds}s | ${width}x${height} | ${fps} fps | H.264`);
      } finally {
        await fs.rm(temporary, { force: true });
      }
    }
  } finally {
    await browser.close();
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
