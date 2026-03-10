#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════
// bridge-server.js
// MeetingCopilot v4.3 — NotebookLM Local HTTP Bridge
// v4.3: Added CORS localhost + shared secret auth + log redaction
// ═══════════════════════════════════════════════════════════════════════════

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const app = express();

// Config
const PORT = process.env.PORT || 3210;
const MODE = process.argv.includes('--mock') ? 'mock'
           : process.argv.includes('--puppeteer') ? 'puppeteer'
           : (process.env.MODE || 'mock');
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';

// ★ v4.3 Security: Shared secret for auth
const BRIDGE_SECRET = process.env.BRIDGE_SECRET || crypto.randomBytes(16).toString('hex');

function log(level, ...args) {
  const levels = { debug: 0, info: 1, warn: 2, error: 3 };
  if (levels[level] >= levels[LOG_LEVEL]) {
    const ts = new Date().toISOString().substr(11, 12);
    console.log(`[${ts}] [${level.toUpperCase()}]`, ...args);
  }
}

// ★ v4.3 Security: Redact sensitive content in logs
function redactQuestion(text) {
  if (!text) return '[empty]';
  if (text.length <= 20) return text;
  return text.substring(0, 20) + '...[redacted]';
}

// ═ Middleware ═

// ★ v4.3 Security: CORS restricted to localhost only
app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (curl, Postman, same-machine apps)
    if (!origin) return callback(null, true);
    const allowed = [
      'http://localhost', 'http://127.0.0.1',
      /^http:\/\/localhost:\d+$/, /^http:\/\/127\.0\.0\.1:\d+$/
    ];
    const isAllowed = allowed.some(a => a instanceof RegExp ? a.test(origin) : origin.startsWith(a));
    if (isAllowed) return callback(null, true);
    log('warn', `CORS blocked origin: ${origin}`);
    return callback(new Error('CORS: origin not allowed'));
  },
  methods: ['GET', 'POST'],
  maxAge: 3600
}));

app.use(express.json());

// ★ v4.3 Security: Auth middleware (shared secret)
function authMiddleware(req, res, next) {
  // Health check is public
  if (req.path === '/health') return next();
  const token = req.headers['x-bridge-secret'] || req.headers['authorization']?.replace('Bearer ', '');
  if (!token || token !== BRIDGE_SECRET) {
    log('warn', `Auth rejected: ${req.method} ${req.path} from ${req.ip}`);
    return res.status(401).json({ error: 'Unauthorized: invalid or missing x-bridge-secret header' });
  }
  next();
}
app.use(authMiddleware);

// ★ v4.3 Security: Redacted request logging
app.use((req, res, next) => {
  if (req.method === 'POST') {
    const safe = { ...req.body };
    if (safe.question) safe.question = redactQuestion(safe.question);
    log('info', `${req.method} ${req.path}`, JSON.stringify(safe));
  }
  next();
});

// ═ Routes ═

app.get('/health', (req, res) => {
  res.json({ status: 'ok', mode: MODE, uptime: process.uptime(), timestamp: new Date().toISOString(),
    security: { cors: 'localhost-only', auth: 'shared-secret', logRedaction: true } });
});

app.post('/query', async (req, res) => {
  const startTime = Date.now();
  const { notebookId, question, maxResults = 3 } = req.body;
  if (!question) return res.status(400).json({ error: 'question is required' });
  try {
    let results;
    switch (MODE) {
      case 'mock': results = await mockQuery(notebookId, question, maxResults); break;
      case 'puppeteer': results = await puppeteerQuery(notebookId, question, maxResults); break;
      default: return res.status(500).json({ error: `Unknown mode: ${MODE}` });
    }
    const latency = Date.now() - startTime;
    log('info', `Query OK: ${results.length} results, ${latency}ms, "${redactQuestion(question)}"`);
    res.json({ results, meta: { latency, mode: MODE, notebookId } });
  } catch (err) {
    log('error', `Query FAIL: ${Date.now() - startTime}ms, ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

app.post('/notebooks', async (req, res) => {
  try {
    if (MODE === 'mock') return res.json({ notebooks: [
      { id: 'nb_umc_digital_twin', name: 'UMC Digital Twin Proposal', sourceCount: 8 },
      { id: 'nb_tsmc_reference', name: 'TSMC Reference Case', sourceCount: 5 },
      { id: 'nb_idtf_technical', name: 'IDTF Technical Documentation', sourceCount: 12 }
    ]});
    const notebooks = await puppeteerListNotebooks();
    res.json({ notebooks });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

app.post('/sources', async (req, res) => {
  const { notebookId } = req.body;
  try {
    if (MODE === 'mock') return res.json({ sources: [
      { title: 'UMC Q3 Financial Report.pdf', type: 'PDF', pages: 42 },
      { title: 'IDTF Architecture Overview.pptx', type: 'PPTX', pages: 28 },
      { title: 'AVEVA Competitive Analysis.docx', type: 'DOCX', pages: 15 },
      { title: 'TSMC PoC Results Summary.pdf', type: 'PDF', pages: 8 },
      { title: 'ISO 27001 Compliance Checklist.xlsx', type: 'DOCX', pages: 6 },
      { title: 'Semiconductor DT Market Report 2024', type: 'URL', pages: null },
      { title: 'OpenUSD Specification v24.08', type: 'URL', pages: null },
      { title: 'Kevin Liu LinkedIn Profile Notes.txt', type: 'Text', pages: 1 }
    ]});
    const sources = await puppeteerListSources(notebookId);
    res.json({ sources });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

// ═ Mock Engine ═

const MOCK_KNOWLEDGE_BASE = [
  { keywords: ['aveva', '競品', '差異', '比較', 'competitor', 'difference'],
    content: 'AVEVA Select operates on a proprietary data model tied to Schneider Electric ecosystem. Annual license $2.1M for comparable scope. Lock-in risk: data export requires $180K migration fee.',
    source: 'AVEVA Competitive Analysis.docx', sourceType: 'DOCX', page: 'Section 3' },
  { keywords: ['oee', 'efficiency', '效率', 'downtime', '停機', '良率'],
    content: 'UMC Q3 2024: OEE dropped from 87.2% to 85.1% across 12-inch fabs. Root cause: 43% unplanned equipment downtime. Digital Twin predictive maintenance could address this.',
    source: 'UMC Q3 Financial Report.pdf', sourceType: 'PDF', page: 'Page 17' },
  { keywords: ['security', '資安', 'iso', 'compliance', '合規', 'data residency'],
    content: 'IDTF Security: ISO 27001 in progress (Q2 2025). All data in GCP asia-east1 (Taiwan). VPC isolation + mTLS. Passed TSMC Cybersecurity Assessment Level 2.',
    source: 'ISO 27001 Compliance Checklist.xlsx', sourceType: 'DOCX', page: 'Sheet: Security' },
  { keywords: ['roi', '投資', 'cost', '成本', 'budget', '預算', 'payback'],
    content: 'PoC $120K (8 weeks, 1 line). Annual savings $450K/line. Payback 3.2 months. Full 10-line ROI: 380%.',
    source: 'IDTF Architecture Overview.pptx', sourceType: 'PPTX', page: 'Slide 22' },
  { keywords: ['openusd', 'teamcenter', '標準', 'format', '格式', '整合'],
    content: 'IDTF three-layer: IADL (real-time sensor via OPC-UA), FDL (3D in OpenUSD), NDH (Teamcenter PLM bidirectional sync).',
    source: 'IDTF Architecture Overview.pptx', sourceType: 'PPTX', page: 'Slide 8' },
  { keywords: ['tsmc', '台積', 'reference', '案例', 'cowos', '封裝'],
    content: 'TSMC CoWoS PoC (2024-Q3): OEE +2.1%, unplanned downtime -18%, predictive maintenance accuracy 87% at 4hr horizon.',
    source: 'TSMC PoC Results Summary.pdf', sourceType: 'PDF', page: 'Page 3' },
  { keywords: ['timeline', '時程', 'schedule', '上線', 'implementation', '導入'],
    content: 'Phase 1 PoC 8w, Phase 2 Pilot 12w, Phase 3 Full Rollout 24w. Total: 11 months.',
    source: 'IDTF Architecture Overview.pptx', sourceType: 'PPTX', page: 'Slide 25' },
  { keywords: ['team', '團隚', 'experience', '經驗', 'founder', 'advisor'],
    content: 'CEO Michael Lin: 20yr enterprise+semiconductor (ex-AVEVA Taiwan Head). CTO: 15yr 3D engine. Advisory: ex-TSMC VP. GitHub 2100+ stars.',
    source: 'IDTF Architecture Overview.pptx', sourceType: 'PPTX', page: 'Slide 28' },
  { keywords: ['kevin', 'liu', 'it', 'vp', '資訊', 'stakeholder'],
    content: 'Kevin Liu (UMC IT VP): Key concerns: data residency (Taiwan), SAP/Teamcenter integration, vendor lock-in. Gatekeeper for IT decisions.',
    source: 'Kevin Liu LinkedIn Profile Notes.txt', sourceType: 'Text', page: null },
  { keywords: ['market', '市場', 'semiconductor', 'digital twin', 'industry'],
    content: 'Global semiconductor DT market: $1.2B (2024) -> $4.8B (2028), CAGR 41%. Gap: no open-source semiconductor-specific solution.',
    source: 'Semiconductor DT Market Report 2024', sourceType: 'URL', page: null }
];

async function mockQuery(notebookId, question, maxResults) {
  const delay = 200 + Math.random() * 600;
  await new Promise(r => setTimeout(r, delay));
  const q = question.toLowerCase();
  const scored = MOCK_KNOWLEDGE_BASE.map(item => {
    const hits = new Set(item.keywords.filter(kw => q.includes(kw.toLowerCase())));
    return { ...item, score: hits.size / item.keywords.length, matchedKeywords: [...hits] };
  });
  return scored.filter(i => i.score > 0).sort((a, b) => b.score - a.score).slice(0, maxResults)
    .map(i => ({ content: i.content, source: i.source, sourceType: i.sourceType,
      relevance: Math.min(0.95, i.score + 0.3), page: i.page }));
}

// ═ Puppeteer Engine (unchanged from v4.1) ═
let browser = null; let activePage = null;
async function initPuppeteer() {
  if (browser) return;
  const puppeteer = require('puppeteer');
  const isLogin = process.argv.includes('--login');
  browser = await puppeteer.launch({ headless: isLogin ? false : 'new', userDataDir: './browser-data',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled'],
    defaultViewport: { width: 1280, height: 900 } });
  activePage = await browser.newPage();
  await activePage.evaluateOnNewDocument(() => { Object.defineProperty(navigator, 'webdriver', { get: () => false }); });
  if (isLogin) { await activePage.goto('https://notebooklm.google.com', { waitUntil: 'networkidle2' }); await new Promise(() => {}); }
}
async function puppeteerQuery(notebookId, question, maxResults) {
  await initPuppeteer();
  if (!activePage.url().includes(notebookId)) await activePage.goto(`https://notebooklm.google.com/notebook/${notebookId}`, { waitUntil: 'networkidle2', timeout: 15000 });
  const sel = 'textarea[aria-label], div[contenteditable="true"], input[type="text"]';
  try { await activePage.waitForSelector(sel, { timeout: 5000 }); } catch { throw new Error('NotebookLM chat input not found'); }
  const el = await activePage.$(sel); await el.click({ clickCount: 3 }); await el.type(question, { delay: 30 });
  await activePage.keyboard.press('Enter'); await activePage.waitForTimeout(3000);
  return activePage.evaluate((max) => {
    const els = document.querySelectorAll('[class*="response"], [class*="answer"], [class*="message"][class*="assistant"]');
    if (!els.length) return [];
    const latest = els[els.length - 1]; const text = latest?.innerText || '';
    return [{ content: text.substring(0, 500), source: 'NotebookLM Response', sourceType: 'Text', relevance: 0.80, page: null }];
  }, maxResults);
}
async function puppeteerListNotebooks() { await initPuppeteer(); await activePage.goto('https://notebooklm.google.com', { waitUntil: 'networkidle2' }); return activePage.evaluate(() => Array.from(document.querySelectorAll('[class*="notebook"], [class*="card"]')).map((c, i) => ({ id: c.getAttribute('data-id') || `notebook_${i}`, name: c.innerText?.split('\n')[0] || `Notebook ${i+1}`, sourceCount: null }))); }
async function puppeteerListSources(notebookId) { await initPuppeteer(); await activePage.goto(`https://notebooklm.google.com/notebook/${notebookId}`, { waitUntil: 'networkidle2' }); return activePage.evaluate(() => Array.from(document.querySelectorAll('[class*="source"]')).map(s => ({ title: s.innerText?.split('\n')[0] || 'Unknown', type: 'PDF', pages: null }))); }

// ═ Shutdown ═
async function shutdown() { if (browser) await browser.close(); process.exit(0); }
process.on('SIGINT', shutdown); process.on('SIGTERM', shutdown);

// ═ Start ═
app.listen(PORT, () => {
  console.log('');
  console.log('  ╔══════════════════════════════════════════════════════╗');
  console.log('  ║   MeetingCopilot NotebookLM Bridge v1.1             ║');
  console.log(`  ║   Mode: ${MODE.padEnd(12)}  Port: ${String(PORT).padEnd(16)}  ║`);
  console.log('  ║   🔒 Security: CORS localhost | Auth token | Redact   ║');
  console.log('  ╚══════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`  🔑 Bridge Secret: ${BRIDGE_SECRET}`);
  console.log('  → Set in .env as BRIDGE_SECRET or pass via x-bridge-secret header');
  console.log('  → Configure in MeetingCopilot Keychain settings');
  console.log('');
});
