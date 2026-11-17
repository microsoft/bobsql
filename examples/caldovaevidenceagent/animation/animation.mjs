const canvas = document.querySelector('#film');
const ctx = canvas.getContext('2d');
const W = 1920;
const H = 1080;
const dark = new URLSearchParams(location.search).has('dark');
document.documentElement.dataset.theme = dark ? 'dark' : 'light';
const colors = {
  ink: '#142b48', muted: '#64748b', blue: '#0078d4',
  teal: '#008b96', purple: '#7651c9', green: '#17835b',
  background: '#f7f9fc', washStart: '#edf4fd', washEnd: '#f9fafc',
  grid: '#c6d4e4', card: '#ffffff', border: '#bfcede',
  connection: '#d6e0ea', arrow: '#b6c6d6',
  foundry: '#f0edf955', foundryBorder: '#ddd7ef',
  vectorLine: '#b7decf', vectorDot: '#a6c8b9',
  ...(dark ? {
    ink: '#edf4ff', muted: '#a6b8d0', blue: '#61b5ff',
    teal: '#4bd8cf', purple: '#b59aff', green: '#5fe0ac',
    background: '#080f1e', washStart: '#152b48', washEnd: '#090f1d',
    grid: '#355073', card: '#121f33', border: '#526b8b',
    connection: '#506c8e', arrow: '#7592b4',
    foundry: '#8a6fdc0c', foundryBorder: '#473b69',
    vectorLine: '#2d725c', vectorDot: '#73ad97',
  } : {}),
};
export const preparationTiming = {
  loadPassages: { start: 0, end: 1.6 },
  embeddingRequest: { start: 1.6, end: 3.1 },
  storeVectors: { start: 3.1, end: 4.8 },
  buildIndex: { start: 4.8, end: 7 },
};
export const retrievalTiming = {
  conversation: { start: 8.5, end: 10 },
  vectorSearch: { start: 16.7, end: 21 },
};
export const nodes = {
  corpus: { x: 1405, y: 175, w: 430, h: 172, color: colors.teal, icon: 'skill',
    title: ['Article passages'], body: ['30 PubMed Central articles', '2,834 passages'] },
  app: { x: 85, y: 435, w: 300, h: 176, color: colors.teal, icon: 'app',
    title: ['Caldova Evidence App'], body: ['Evidence investigation'] },
  agent: { x: 515, y: 435, w: 340, h: 176, color: colors.purple, icon: 'agent',
    title: ['Hosted Foundry Agent'], body: ['Responses + Activity', 'Plans, investigates, synthesizes'] },
  skill: { x: 515, y: 175, w: 340, h: 172, color: colors.purple, icon: 'skill',
    title: ['Foundry Skills API'], body: ['biomedical-evidence-review', 'Versioned SKILL.md'] },
  model: { x: 515, y: 785, w: 340, h: 162, color: colors.purple, icon: 'model',
    title: ['GPT-5'], body: ['Reasoning model', 'Microsoft Foundry'] },
  mcp: { x: 985, y: 435, w: 290, h: 176, color: colors.blue, icon: 'shield',
    title: ['DAB 2.0', 'SQL MCP Server'], body: ['Governed read-only tools'] },
  procedures: { x: 1405, y: 400, w: 430, h: 246, color: colors.green, icon: 'code',
    title: ['Approved SQL procedures'], body: ['search_evidence', 'get_article_context', 'get_corpus_status'], mono: true },
  embedding: { x: 985, y: 785, w: 290, h: 162, color: colors.blue, icon: 'vector',
    title: ['text-embedding-3-small'], body: ['Azure OpenAI', '512 dimensions'] },
  sql: { x: 1405, y: 715, w: 430, h: 260, color: colors.green, icon: 'database',
    title: ['Azure SQL Hyperscale'], body: ['research | 2,834 stored passage vectors'] },
};
export const indexPanel = { x: 1427, y: 852, w: 386, h: 103 };
const corpusPath = [[1835, 261], [1870, 261], [1870, 866], [1835, 866]];

// Each flow follows an actual boundary; evidence returns through the same governed path.
export const flows = [
  { points: corpusPath, color: colors.teal, ...preparationTiming.loadPassages, from: 'corpus', to: 'sql' },
  { points: [[1405, 866], [1275, 866]], color: colors.blue, ...preparationTiming.embeddingRequest, from: 'sql', to: 'embedding' },
  { points: [[1275, 866], [1405, 866]], color: colors.green, ...preparationTiming.storeVectors, from: 'embedding', to: 'sql' },
  { points: [[685, 347], [685, 435]], color: colors.purple, start: 7, end: 8.5, from: 'skill', to: 'agent' },
  { points: [[385, 523], [515, 523]], color: colors.teal, ...retrievalTiming.conversation, from: 'app', to: 'agent' },
  { points: [[685, 611], [685, 785]], color: colors.purple, start: 10, end: 11.2, from: 'agent', to: 'model' },
  { points: [[685, 785], [685, 611]], color: colors.purple, start: 11.2, end: 12.4, from: 'model', to: 'agent' },
  { points: [[855, 523], [985, 523]], color: colors.blue, start: 12.4, end: 14, from: 'agent', to: 'mcp' },
  { points: [[1275, 523], [1405, 523]], color: colors.blue, start: 14, end: 15.5, from: 'mcp', to: 'procedures' },
  { points: [[1620, 646], [1620, 715]], color: colors.green, start: 15.5, end: retrievalTiming.vectorSearch.start, from: 'procedures', to: 'sql' },
  { points: [[1620, 715], [1620, 646]], color: colors.green, start: retrievalTiming.vectorSearch.end, end: 22, from: 'sql', to: 'procedures' },
  { points: [[1405, 523], [1275, 523]], color: colors.green, start: 22, end: 23, from: 'procedures', to: 'mcp' },
  { points: [[985, 523], [855, 523]], color: colors.green, start: 23, end: 24, from: 'mcp', to: 'agent' },
  { points: [[685, 611], [685, 785]], color: colors.purple, start: 24, end: 25, from: 'agent', to: 'model' },
  { points: [[685, 785], [685, 611]], color: colors.purple, start: 25, end: 26, from: 'model', to: 'agent' },
  { points: [[515, 523], [385, 523]], color: colors.green, start: 26, end: 28, from: 'agent', to: 'app' },
];
const clamp = (x) => Math.max(0, Math.min(1, x));
const ease = (x) => { x = clamp(x); return x * x * (3 - 2 * x); };
const windowAt = (t, start, end, fade = 0.3) => ease((t - start) / fade) * ease((end - t) / fade);
function roundRect(x, y, w, h, r = 6) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}
function text(value, x, y, size = 18, color = colors.ink, weight = 400, align = 'left', mono = false) {
  ctx.font = `${weight} ${size}px ${mono ? 'Consolas' : '"Segoe UI"'}, sans-serif`;
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.fillText(value, x, y);
}
function line(points, stroke, width = 2) {
  ctx.beginPath();
  points.forEach(([x, y], i) => i ? ctx.lineTo(x, y) : ctx.moveTo(x, y));
  ctx.strokeStyle = stroke;
  ctx.lineWidth = width;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.stroke();
}
function dot(x, y, r, color) {
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fillStyle = color;
  ctx.fill();
}
function icon(type, x, y, color) {
  ctx.save();
  ctx.translate(x, y);
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = 2;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  if (type === 'app') {
    roundRect(-13, -11, 26, 22, 4); ctx.stroke();
    line([[-13, -4], [13, -4]], color);
    dot(-8, -8, 1, color); dot(-4, -8, 1, color);
    line([[-5, 1], [-8, 4], [-5, 7]], color);
    line([[5, 1], [8, 4], [5, 7]], color);
  } else if (type === 'agent' || type === 'model') {
    const points = [[0, -13], [12, -5], [8, 10], [-8, 10], [-12, -5]];
    points.forEach((p, i) => { line([p, points[(i + 1) % 5]], color, 1.5); line([p, [0, 0]], color, 1.5); dot(...p, 2.5, color); });
    dot(0, 0, 3.5, color);
  } else if (type === 'skill') {
    roundRect(-10, -13, 20, 26, 3); ctx.stroke();
    line([[-5, -5], [5, -5]], color);
    line([[-5, 1], [5, 1]], color);
    line([[-5, 7], [1, 7]], color);
  } else if (type === 'shield') {
    ctx.beginPath(); ctx.moveTo(0, -14); ctx.lineTo(12, -9); ctx.lineTo(10, 4);
    ctx.quadraticCurveTo(8, 10, 0, 14); ctx.quadraticCurveTo(-8, 10, -10, 4);
    ctx.lineTo(-12, -9); ctx.closePath(); ctx.stroke();
    line([[-5, 0], [-1, 4], [6, -4]], color, 2.5);
  } else if (type === 'code') {
    line([[-6, -8], [-14, 0], [-6, 8]], color);
    line([[6, -8], [14, 0], [6, 8]], color);
    line([[3, -11], [-3, 11]], color);
  } else if (type === 'vector') {
    for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) dot(-9 + i * 9, -9 + j * 9, i === j ? 3 : 2, color);
  } else if (type === 'database') {
    ctx.beginPath(); ctx.ellipse(0, -9, 13, 5, 0, 0, Math.PI * 2); ctx.stroke();
    line([[-13, -9], [-13, 9]], color); line([[13, -9], [13, 9]], color);
    for (const yy of [0, 9]) { ctx.beginPath(); ctx.ellipse(0, yy, 13, 5, 0, 0, Math.PI); ctx.stroke(); }
  }
  ctx.restore();
}
function card(node, activity, t) {
  const { x, y, w, h, color } = node;
  ctx.save();
  roundRect(x, y, w, h);
  ctx.fillStyle = colors.card; ctx.fill();
  ctx.strokeStyle = activity > 0 ? color : colors.border;
  ctx.lineWidth = 2 + activity * 0.5; ctx.stroke();
  ctx.globalAlpha = (dark ? 0.12 : 0.07) + activity * 0.05;
  roundRect(x + 18, y + 18, 46, 46, 4); ctx.fillStyle = color; ctx.fill();
  ctx.globalAlpha = 1;
  icon(node.icon, x + 41, y + 41, color);
  dot(x + w - 24, y + 27, 3.5, color);
  if (activity > 0.01) {
    ctx.globalAlpha = activity * 0.2 * (0.65 + 0.35 * Math.sin(t * 4));
    ctx.beginPath(); ctx.arc(x + w - 24, y + 27, 9, 0, Math.PI * 2);
    ctx.fillStyle = color; ctx.fill(); ctx.globalAlpha = 1;
  }
  const titleSize = node === nodes.embedding ? 20 : node === nodes.sql ? 23 : 24;
  const titleY = y + 91;
  node.title.forEach((value, i) => text(value, x + 22, titleY + i * 27, titleSize, colors.ink, 600));
  const bodyY = titleY + (node.title.length - 1) * 27 + 28;
  node.body.forEach((value, i) => text(value, x + 22, bodyY + i * (node.mono ? 30 : 23),
    node.mono ? 20 : node === nodes.agent ? 17 : 18, node.mono ? color : colors.muted, 400, 'left', node.mono));
  ctx.restore();
}
function connection(points, color, label, lx, ly) {
  line(points, colors.connection, 2);
  const [a, b] = [points.at(-2), points.at(-1)];
  const angle = Math.atan2(b[1] - a[1], b[0] - a[0]);
  ctx.save(); ctx.translate(...b); ctx.rotate(angle);
  line([[-8, -4], [0, 0], [-8, 4]], colors.arrow, 2); ctx.restore();
  if (label) text(label, lx, ly, 16, color, 500, 'center');
}
function pointOnPath(points, progress) {
  const lengths = points.slice(1).map((q, i) => Math.hypot(q[0] - points[i][0], q[1] - points[i][1]));
  let distance = clamp(progress) * lengths.reduce((sum, length) => sum + length, 0);
  for (let i = 0; i < lengths.length; i++) {
    if (distance <= lengths[i]) {
      const u = lengths[i] === 0 ? 0 : distance / lengths[i];
      return [points[i][0] + (points[i + 1][0] - points[i][0]) * u,
        points[i][1] + (points[i + 1][1] - points[i][1]) * u];
    }
    distance -= lengths[i];
  }
  return points.at(-1);
}
function flow(f, t) {
  const a = windowAt(t, f.start, f.end, Math.min(0.25, (f.end - f.start) / 4));
  if (a <= 0) return;
  ctx.save();
  ctx.globalAlpha = a * 0.22; line(f.points, f.color, 7);
  ctx.globalAlpha = a;
  const duration = f.end - f.start;
  // Staggered packets travel in one direction, with short luminous trails.
  for (let i = 0; i < 3; i++) {
    const u = (t - f.start) / duration * 1.55 - i * 0.24;
    if (u < 0 || u > 1) continue;
    for (let j = 8; j >= 0; j--) {
      const v = Math.max(0, u - j * 0.018);
      ctx.globalAlpha = a * (1 - j / 9) * (j ? 0.48 : 1);
      dot(...pointOnPath(f.points, v), j ? 3 : 5, f.color);
    }
    ctx.globalAlpha = a;
    dot(...pointOnPath(f.points, u), 2, '#fff');
  }
  ctx.restore();
}
function vectorIndex(t) {
  const { start, end } = retrievalTiming.vectorSearch;
  const searching = windowAt(t, start, end, 0.2);
  const build = preparationTiming.buildIndex;
  const progress = clamp((t - build.start) / (build.end - build.start));
  const building = windowAt(t, build.start, build.end, 0.2);
  const { x, y, w, h } = indexPanel;
  const points = [[196, 48], [220, 22], [230, 70], [252, 44], [271, 19],
    [285, 75], [305, 43], [328, 18], [346, 65]].map(([px, py]) => [x + px, y + py]);
  const edges = [[0, 1], [0, 2], [0, 3], [1, 3], [1, 4], [2, 3], [2, 5],
    [3, 4], [3, 5], [3, 6], [4, 6], [4, 7], [5, 6], [5, 8], [6, 7], [6, 8], [7, 8]];
  const searchPath = [0, 3, 6, 8];
  const traversal = clamp((t - start) / (end - start)) * (searchPath.length - 1);
  const visited = searchPath.slice(0, Math.floor(traversal) + 1);
  ctx.save();
  roundRect(x, y, w, h, 4);
  ctx.fillStyle = colors.background; ctx.fill();
  ctx.strokeStyle = searching ? colors.blue : building ? colors.green : colors.border;
  ctx.lineWidth = searching || building ? 2 : 1.5; ctx.stroke();
  text('DiskANN index', x + 14, y + 28, 19, colors.ink, 600);
  text('VECTOR_SEARCH', x + 14, y + 53, 14, colors.green, 500, 'left', true);
  for (const [a, b] of edges) {
    const indexed = progress >= (Math.max(a, b) + 1) / points.length;
    ctx.globalAlpha = indexed ? 0.8 : 0.12;
    line([points[a], points[b]], indexed ? colors.green : colors.vectorLine, 1.5);
  }
  points.forEach(([px, py], i) => {
    const indexed = progress >= (i + 1) / points.length;
    ctx.globalAlpha = indexed ? 1 : 0.2;
    dot(px, py, indexed ? 4 : 3, indexed ? colors.green : colors.vectorDot);
  });
  ctx.globalAlpha = 1;
  line([[x + 14, y + h - 9], [x + w - 14, y + h - 9]], colors.connection, 2);
  if (progress > 0) line([[x + 14, y + h - 9], [x + 14 + (w - 28) * progress, y + h - 9]], colors.green, 3);
  if (searching > 0) {
    ctx.globalAlpha = searching;
    line(searchPath.map((i) => points[i]), colors.blue, 3);
    visited.forEach((i) => {
      ctx.beginPath(); ctx.arc(...points[i], 8, 0, Math.PI * 2);
      ctx.strokeStyle = colors.blue; ctx.lineWidth = 2; ctx.stroke();
    });
    const segment = Math.min(searchPath.length - 2, Math.floor(traversal));
    const position = pointOnPath([points[searchPath[segment]], points[searchPath[segment + 1]]], traversal - segment);
    dot(...position, 6, colors.blue);
    dot(...position, 2.5, '#ffffff');
  }
  ctx.restore();
}

export function renderFrame(seconds) {
  const t = Math.max(0, Math.min(30, seconds));
  ctx.setTransform(canvas.width / W, 0, 0, canvas.height / H, 0, 0);
  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = colors.background; ctx.fillRect(0, 0, W, H);
  const wash = ctx.createRadialGradient(1500, 200, 30, 1300, 300, 1500);
  wash.addColorStop(0, colors.washStart); wash.addColorStop(1, colors.washEnd);
  ctx.fillStyle = wash; ctx.fillRect(0, 0, W, H);
  ctx.save();
  ctx.globalAlpha = 0.35;
  for (let x = 40; x < W; x += 32) for (let y = 150; y < H - 40; y += 32) dot(x, y, 0.7, colors.grid);
  ctx.restore();

  roundRect(85, 65, 5, 60, 2); ctx.fillStyle = colors.blue; ctx.fill();
  text('Caldova Evidence Agent', 110, 108, 42, colors.ink, 600);

  roundRect(480, 150, 410, 827, 8);
  ctx.fillStyle = colors.foundry; ctx.fill(); ctx.strokeStyle = colors.foundryBorder; ctx.lineWidth = 1; ctx.stroke();
  // Architecture boundaries and service labels, not narrative captions.
  text('MICROSOFT FOUNDRY', 685, 1008, 14, colors.purple, 600, 'center');
  text('GOVERNED DATA ACCESS', 1410, 1008, 14, colors.green, 600, 'center');

  connection([[385, 523], [515, 523]], colors.teal, 'conversation', 450, 499);
  connection([[855, 523], [985, 523]], colors.blue, 'tool call', 920, 499);
  connection([[1275, 523], [1405, 523]], colors.blue, 'execute', 1340, 499);
  connection([[685, 347], [685, 435]], colors.purple, '', 0, 0);
  text('download at startup', 785, 382, 14, colors.purple, 400, 'center');
  text('load on demand', 785, 403, 14, colors.purple, 400, 'center');
  connection([[685, 611], [685, 785]], colors.purple, 'reasoning', 747, 702);
  connection([[1620, 646], [1620, 715]], colors.green, '', 0, 0);
  connection([[1405, 866], [1275, 866]], colors.blue, '', 0, 0);
  connection(corpusPath, colors.teal, '', 0, 0);

  const activity = Object.fromEntries(Object.keys(nodes).map((key) => [key, 0]));
  for (const f of flows) {
    const a = windowAt(t, f.start, f.end, 0.3);
    activity[f.from] = Math.max(activity[f.from], a * 0.65);
    activity[f.to] = Math.max(activity[f.to], a);
  }
  activity.sql = Math.max(activity.sql, windowAt(t, preparationTiming.buildIndex.start, preparationTiming.buildIndex.end, 0.2));
  activity.sql = Math.max(activity.sql, windowAt(t, retrievalTiming.vectorSearch.start, retrievalTiming.vectorSearch.end, 0.2));
  activity.app = Math.max(activity.app, windowAt(t, 28.2, 30.5, 0.4));
  for (const [key, node] of Object.entries(nodes)) card(node, activity[key], t);
  flows.forEach((f) => flow(f, t));
  vectorIndex(t);
}

window.renderFrame = renderFrame;
window.animationDuration = 30;
const seek = document.querySelector('#seek');
const play = document.querySelector('#play');
let playing = !new URLSearchParams(location.search).has('render');
let position = 0;
let last = performance.now();
function tick(now) {
  if (playing) {
    position = (position + (now - last) / 1000) % 30;
    renderFrame(position);
    seek.value = position;
    document.querySelector('#time').value = `${position.toFixed(1)} / 30 s`;
  }
  last = now;
  requestAnimationFrame(tick);
}
play.addEventListener('click', () => {
  playing = !playing;
  play.textContent = playing ? 'Pause' : 'Play';
});
seek.addEventListener('input', () => {
  position = Number(seek.value);
  renderFrame(position);
  document.querySelector('#time').value = `${position.toFixed(1)} / 30 s`;
});
play.textContent = playing ? 'Pause' : 'Play';
renderFrame(0);
requestAnimationFrame(tick);
