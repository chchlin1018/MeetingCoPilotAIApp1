#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════
// bridge-server.js
// MeetingCopilot v4.1 — NotebookLM Local HTTP Bridge
// ═══════════════════════════════════════════════════════════════════════════
//
// Swift App (NotebookLMService.swift)
//     │
//     │  POST http://localhost:3210/query
//     │  { notebookId, question, maxResults }
//     │
//     ▼
// This Bridge Server
//     │
//     ├─ Mock Mode ─────→ Simulated responses (dev/testing)
//     ├─ Puppeteer Mode ─→ Browser automation against notebooklm.google.com
//     └─ API Mode ───────→ (Future) Google Enterprise API when GA
//
// Usage:
//   npm start          # Production (reads .env for MODE)
//   npm run dev         # Mock mode for development
//   node bridge-server.js --mock
//   node bridge-server.js --puppeteer
//
// ═══════════════════════════════════════════════════════════════════════════

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const app = express();

// ─────────────────────────────────────────────────────────────────────────
// Config
// ─────────────────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3210;
const MODE = process.argv.includes('--mock') ? 'mock'
           : process.argv.includes('--puppeteer') ? 'puppeteer'
           : (process.env.MODE || 'mock');

const LOG_LEVEL = process.env.LOG_LEVEL || 'info';

function log(level, ...args) {
  const levels = { debug: 0, info: 1, warn: 2, error: 3 };
  if (levels[level] >= levels[LOG_LEVEL]) {
    const ts = new Date().toISOString().substr(11, 12);
    console.log(`[${ts}] [${level.toUpperCase()}]`, ...args);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Middleware
// ─────────────────────────────────────────────────────────────────────────

app.use(cors());
app.use(express.json());

// Request logging
app.use((req, res, next) => {
  if (req.method === 'POST') {
    log('info', `${req.method} ${req.path}`, JSON.stringify(req.body).substring(0, 120));
  }
  next();
});

// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Routes
// ═══════════════════════════════════════════════════════════════════════════

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    mode: MODE,
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// ─────────────────────────────────────────────────────────────────────────
// POST /query — Core query endpoint
// Called by NotebookLMService.swift
// ─────────────────────────────────────────────────────────────────────────

app.post('/query', async (req, res) => {
  const startTime = Date.now();
  const { notebookId, question, maxResults = 3 } = req.body;

  if (!question) {
    return res.status(400).json({ error: 'question is required' });
  }

  try {
    let results;

    switch (MODE) {
      case 'mock':
        results = await mockQuery(notebookId, question, maxResults);
        break;
      case 'puppeteer':
        results = await puppeteerQuery(notebookId, question, maxResults);
        break;
      default:
        return res.status(500).json({ error: `Unknown mode: ${MODE}` });
    }

    const latency = Date.now() - startTime;
    log('info', `Query OK: ${results.length} results, ${latency}ms, "${question.substring(0, 40)}"`);

    res.json({ results, meta: { latency, mode: MODE, notebookId } });
  } catch (err) {
    const latency = Date.now() - startTime;
    log('error', `Query FAIL: ${latency}ms, ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────
// POST /notebooks — List available notebooks
// ─────────────────────────────────────────────────────────────────────────

app.post('/notebooks', async (req, res) => {
  try {
    if (MODE === 'mock') {
      return res.json({
        notebooks: [
          { id: 'nb_umc_digital_twin', name: 'UMC Digital Twin Proposal', sourceCount: 8 },
          { id: 'nb_tsmc_reference', name: 'TSMC Reference Case', sourceCount: 5 },
          { id: 'nb_idtf_technical', name: 'IDTF Technical Documentation', sourceCount: 12 }
        ]
      });
    }
    // Puppeteer mode: scrape notebook list
    const notebooks = await puppeteerListNotebooks();
    res.json({ notebooks });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────
// POST /sources — List sources in a notebook
// ─────────────────────────────────────────────────────────────────────────

app.post('/sources', async (req, res) => {
  const { notebookId } = req.body;
  try {
    if (MODE === 'mock') {
      return res.json({
        sources: [
          { title: 'UMC Q3 Financial Report.pdf', type: 'PDF', pages: 42 },
          { title: 'IDTF Architecture Overview.pptx', type: 'PPTX', pages: 28 },
          { title: 'AVEVA Competitive Analysis.docx', type: 'DOCX', pages: 15 },
          { title: 'TSMC PoC Results Summary.pdf', type: 'PDF', pages: 8 },
          { title: 'ISO 27001 Compliance Checklist.xlsx', type: 'DOCX', pages: 6 },
          { title: 'Semiconductor DT Market Report 2024', type: 'URL', pages: null },
          { title: 'OpenUSD Specification v24.08', type: 'URL', pages: null },
          { title: 'Kevin Liu LinkedIn Profile Notes.txt', type: 'Text', pages: 1 }
        ]
      });
    }
    const sources = await puppeteerListSources(notebookId);
    res.json({ sources });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Mock Engine (Development / Testing)
// ═══════════════════════════════════════════════════════════════════════════
//
// Simulates NotebookLM query responses based on keyword matching.
// Returns realistic passages that look like they came from uploaded documents.
// Includes artificial latency (200-800ms) to simulate real query times.
//
// ═══════════════════════════════════════════════════════════════════════════

const MOCK_KNOWLEDGE_BASE = [
  {
    keywords: ['aveva', '競品', '差異', '比較', 'competitor', 'difference'],
    content: 'AVEVA Select operates on a proprietary data model tied to Schneider Electric ecosystem. Annual license $2.1M for comparable scope. Lock-in risk: data export requires $180K migration fee. Their 2024 roadmap shows no OpenUSD support. Key weakness: no native semiconductor equipment-level digital twin — their Asset Performance module targets process industry (oil & gas, chemicals) not discrete manufacturing.',
    source: 'AVEVA Competitive Analysis.docx',
    sourceType: 'DOCX',
    page: 'Section 3: Competitive Positioning'
  },
  {
    keywords: ['oee', 'efficiency', '效率', 'downtime', '停機', '良率', 'yield'],
    content: 'UMC Q3 2024: OEE dropped from 87.2% to 85.1% across 12-inch fabs. Root cause analysis indicates 43% due to unplanned equipment downtime (avg 2.3 hrs/incident), 31% from recipe changeover delays, 26% from quality excursions. Digital Twin predictive maintenance could address the 43% equipment downtime component. Estimated OEE improvement: +1.8-2.4% with real-time anomaly detection.',
    source: 'UMC Q3 Financial Report.pdf',
    sourceType: 'PDF',
    page: 'Page 17: Manufacturing KPIs'
  },
  {
    keywords: ['security', '資安', 'iso', 'compliance', '合規', 'data residency', '隱私'],
    content: 'IDTF Security Architecture: (1) ISO 27001 certification in progress, target Q2 2025. (2) All data stored in GCP asia-east1 (Changhua, Taiwan) — zero cross-border data transfer. (3) VPC Service Controls isolate each tenant. (4) All API communication via mutual TLS (mTLS). (5) Passed TSMC Cybersecurity Assessment (Level 2) in 2024-09. (6) SEMI E187 Equipment Information Security compliance checklist: 94% complete.',
    source: 'ISO 27001 Compliance Checklist.xlsx',
    sourceType: 'DOCX',
    page: 'Sheet: Security Architecture'
  },
  {
    keywords: ['roi', '投資', 'cost', '成本', 'budget', '預算', 'payback', '回收'],
    content: 'PoC Investment: $120K (8 weeks, 1 production line). Expected single-line annual savings: $450K/yr breakdown — reduced unplanned downtime ($280K), energy optimization ($95K), yield improvement ($75K). Payback period: 3.2 months. Full 10-line rollout: $840K/yr total cost, $3.2M total benefit. Three-year NPV at 10% discount: $5.8M. ROI: 380%.',
    source: 'IDTF Architecture Overview.pptx',
    sourceType: 'PPTX',
    page: 'Slide 22: Business Case'
  },
  {
    keywords: ['openusd', 'teamcenter', '標準', 'format', '格式', '整合', 'integration'],
    content: 'IDTF three-layer architecture: IADL (Industrial Automation Data Layer) handles real-time sensor data at 100ms intervals via OPC-UA. FDL (Factory Digital Layer) manages 3D geometry in OpenUSD format — validated with Pixar reference implementation. NDH (Notebook Data Hub) provides Teamcenter PLM bidirectional sync via REST API for BOM, recipe, and maintenance records. Validated at TSMC advanced packaging CoWoS line.',
    source: 'IDTF Architecture Overview.pptx',
    sourceType: 'PPTX',
    page: 'Slide 8: Technical Architecture'
  },
  {
    keywords: ['tsmc', '台積', 'reference', '案例', 'cowos', '封裝', 'packaging'],
    content: 'TSMC Advanced Packaging PoC Results (2024-Q3): CoWoS production line, 8-week engagement. Results: OEE +2.1% (from 91.3% to 93.4%), unplanned downtime -18% (avg incident duration 2.3hrs → 1.9hrs), predictive maintenance accuracy 87% at 4-hour horizon. Key success factor: OpenUSD-based 3D equipment model enabled visual anomaly detection that operators could understand without ML expertise.',
    source: 'TSMC PoC Results Summary.pdf',
    sourceType: 'PDF',
    page: 'Page 3: Executive Summary'
  },
  {
    keywords: ['timeline', '時程', 'schedule', '上線', 'implementation', '導入', 'phase'],
    content: 'Proposed implementation roadmap: Phase 1 PoC (8 weeks) — single production line, 3 equipment types, real-time dashboard + anomaly detection. Phase 2 Pilot (12 weeks) — expand to 3 lines, add predictive maintenance + energy optimization. Phase 3 Full Rollout (24 weeks) — all 12-inch fab lines, Teamcenter integration, operator training. Total timeline: 11 months from contract to full deployment.',
    source: 'IDTF Architecture Overview.pptx',
    sourceType: 'PPTX',
    page: 'Slide 25: Implementation Roadmap'
  },
  {
    keywords: ['team', '團隊', 'experience', '經驗', '背景', 'founder', 'advisor'],
    content: 'MacroVision Systems core team: CEO Michael Lin — 20yr enterprise software + semiconductor (ex-AVEVA Taiwan Head, managed $35M annual revenue). CTO — 15yr 3D graphics engine development (ex-Autodesk). Head of AI — PhD NTU, 8yr ML in manufacturing. Advisory board: ex-TSMC VP of Smart Manufacturing, HTFA Digital Twin Committee member. GitHub: IDTF framework 2,100+ stars, 340+ forks.',
    source: 'IDTF Architecture Overview.pptx',
    sourceType: 'PPTX',
    page: 'Slide 28: Team'
  },
  {
    keywords: ['kevin', 'liu', 'it', 'vp', '資訊', 'stakeholder'],
    content: 'Kevin Liu (UMC IT VP) profile notes: Joined UMC 2019 from Foxconn. Key concerns from past 2 meetings: (1) data residency — must stay in Taiwan, (2) integration with existing SAP ECC and Teamcenter PLM, (3) vendor lock-in risk — wants open standards. Communication style: detail-oriented, asks follow-up questions, respects technical depth. Influence: gatekeeper for all IT infrastructure decisions, reports directly to COO.',
    source: 'Kevin Liu LinkedIn Profile Notes.txt',
    sourceType: 'Text',
    page: null
  },
  {
    keywords: ['market', '市場', 'semiconductor', 'digital twin', 'industry', '產業'],
    content: 'Global semiconductor digital twin market size: $1.2B (2024), projected $4.8B by 2028 (CAGR 41%). Key drivers: AI/ML integration, equipment complexity (EUV lithography), supply chain resilience post-COVID. Top players: Siemens (Teamcenter), AVEVA (Schneider), PTC (ThingWorx). Gap: no open-source, semiconductor-specific solution — IDTF addresses this whitespace. Taiwan semiconductor output: $130B (2024), 65% global foundry share.',
    source: 'Semiconductor DT Market Report 2024',
    sourceType: 'URL',
    page: null
  }
];

async function mockQuery(notebookId, question, maxResults) {
  // Simulate network latency (200-800ms)
  const delay = 200 + Math.random() * 600;
  await new Promise(r => setTimeout(r, delay));

  const q = question.toLowerCase();

  // Score each knowledge item
  const scored = MOCK_KNOWLEDGE_BASE.map(item => {
    const keywordHits = item.keywords.filter(kw => q.includes(kw.toLowerCase()));
    // Also check Chinese characters individually
    const chineseHits = item.keywords.filter(kw => {
      if (kw.length <= 2) return q.includes(kw);
      return false;
    });
    const uniqueHits = new Set([...keywordHits, ...chineseHits]);
    const score = uniqueHits.size / item.keywords.length;
    return { ...item, score, matchedKeywords: [...uniqueHits] };
  });

  // Filter and sort
  return scored
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, maxResults)
    .map(item => ({
      content: item.content,
      source: item.source,
      sourceType: item.sourceType,
      relevance: Math.min(0.95, item.score + 0.3),  // Boost to realistic range
      page: item.page
    }));
}


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Puppeteer Engine (Browser Automation)
// ═══════════════════════════════════════════════════════════════════════════
//
// Automates notebooklm.google.com via headless Chrome.
// Requires one-time manual Google login to establish session cookies.
//
// How it works:
// 1. Launch Chromium with persistent user data dir (keeps Google session)
// 2. Navigate to NotebookLM notebook page
// 3. Type question into the chat/query input
// 4. Wait for and parse the response + source citations
// 5. Return structured results
//
// First-time setup:
//   node bridge-server.js --puppeteer --login
//   → Opens visible browser for manual Google login
//   → Saves session to ./browser-data/
//   → Subsequent launches reuse session (headless)
//
// ═══════════════════════════════════════════════════════════════════════════

let browser = null;
let activePage = null;

async function initPuppeteer() {
  if (browser) return;

  const puppeteer = require('puppeteer');
  const isLogin = process.argv.includes('--login');

  log('info', `Launching Puppeteer (${isLogin ? 'LOGIN mode — visible browser' : 'headless'})...`);

  browser = await puppeteer.launch({
    headless: isLogin ? false : 'new',
    userDataDir: './browser-data',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-blink-features=AutomationControlled'
    ],
    defaultViewport: { width: 1280, height: 900 }
  });

  activePage = await browser.newPage();

  // Stealth: override navigator.webdriver
  await activePage.evaluateOnNewDocument(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => false });
  });

  if (isLogin) {
    log('info', 'Opening NotebookLM for manual login...');
    await activePage.goto('https://notebooklm.google.com', { waitUntil: 'networkidle2' });
    log('info', '>>> Please complete Google login in the browser window <<<');
    log('info', '>>> Then press Ctrl+C to restart in headless mode <<<');
    // Keep alive for manual login
    await new Promise(() => {});
  }

  log('info', 'Puppeteer ready (using saved session)');
}

async function puppeteerQuery(notebookId, question, maxResults) {
  await initPuppeteer();

  const notebookUrl = `https://notebooklm.google.com/notebook/${notebookId}`;

  // Navigate to notebook if not already there
  const currentUrl = activePage.url();
  if (!currentUrl.includes(notebookId)) {
    log('debug', `Navigating to notebook: ${notebookId}`);
    await activePage.goto(notebookUrl, { waitUntil: 'networkidle2', timeout: 15000 });
    await activePage.waitForTimeout(2000);
  }

  // Find and type in the query input
  // NotebookLM's chat input selector (may change — update as needed)
  const inputSelector = 'textarea[aria-label], div[contenteditable="true"], input[type="text"]';

  try {
    await activePage.waitForSelector(inputSelector, { timeout: 5000 });
  } catch {
    log('warn', 'Could not find chat input — NotebookLM UI may have changed');
    throw new Error('NotebookLM chat input not found. UI may have changed.');
  }

  // Clear and type question
  const inputEl = await activePage.$(inputSelector);
  await inputEl.click({ clickCount: 3 }); // Select all
  await inputEl.type(question, { delay: 30 });

  // Submit (Enter key)
  await activePage.keyboard.press('Enter');

  // Wait for response (look for new response elements)
  log('debug', 'Waiting for NotebookLM response...');
  await activePage.waitForTimeout(3000);

  // Parse response — extract text and source citations
  const results = await activePage.evaluate((max) => {
    const responseElements = document.querySelectorAll(
      // Common patterns for NotebookLM response blocks
      '[class*="response"], [class*="answer"], [class*="message"][class*="assistant"]'
    );

    if (responseElements.length === 0) return [];

    // Get the latest response
    const latest = responseElements[responseElements.length - 1];
    const responseText = latest?.innerText || '';

    // Try to find source citations within the response
    const citations = latest?.querySelectorAll('[class*="citation"], [class*="source"]') || [];

    const parsed = [];
    if (citations.length > 0) {
      citations.forEach((cite, i) => {
        if (i >= max) return;
        parsed.push({
          content: cite.innerText || responseText.substring(0, 300),
          source: cite.getAttribute('title') || cite.getAttribute('data-source') || `Source ${i + 1}`,
          sourceType: 'PDF',
          relevance: 0.85 - (i * 0.05),
          page: null
        });
      });
    } else {
      // No structured citations — return full response as single result
      parsed.push({
        content: responseText.substring(0, 500),
        source: 'NotebookLM Response',
        sourceType: 'Text',
        relevance: 0.80,
        page: null
      });
    }

    return parsed;
  }, maxResults);

  return results;
}

async function puppeteerListNotebooks() {
  await initPuppeteer();
  await activePage.goto('https://notebooklm.google.com', { waitUntil: 'networkidle2' });
  await activePage.waitForTimeout(2000);

  return activePage.evaluate(() => {
    const cards = document.querySelectorAll('[class*="notebook"], [class*="card"]');
    return Array.from(cards).map((card, i) => ({
      id: card.getAttribute('data-id') || `notebook_${i}`,
      name: card.innerText?.split('\n')[0] || `Notebook ${i + 1}`,
      sourceCount: null
    }));
  });
}

async function puppeteerListSources(notebookId) {
  await initPuppeteer();
  await activePage.goto(
    `https://notebooklm.google.com/notebook/${notebookId}`,
    { waitUntil: 'networkidle2' }
  );
  await activePage.waitForTimeout(2000);

  return activePage.evaluate(() => {
    const sources = document.querySelectorAll('[class*="source"]');
    return Array.from(sources).map(s => ({
      title: s.innerText?.split('\n')[0] || 'Unknown',
      type: 'PDF',
      pages: null
    }));
  });
}


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Graceful Shutdown
// ═══════════════════════════════════════════════════════════════════════════

async function shutdown() {
  log('info', 'Shutting down...');
  if (browser) {
    await browser.close();
    browser = null;
  }
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);


// ═══════════════════════════════════════════════════════════════════════════
// MARK: - Start Server
// ═══════════════════════════════════════════════════════════════════════════

app.listen(PORT, () => {
  console.log('');
  console.log('  ╔══════════════════════════════════════════════════════╗');
  console.log('  ║   MeetingCopilot NotebookLM Bridge v1.0             ║');
  console.log(`  ║   Mode: ${MODE.padEnd(12)}  Port: ${String(PORT).padEnd(16)}  ║`);
  console.log('  ║                                                      ║');
  console.log('  ║   POST /query      — Query NotebookLM               ║');
  console.log('  ║   POST /notebooks  — List notebooks                  ║');
  console.log('  ║   POST /sources    — List sources in notebook        ║');
  console.log('  ║   GET  /health     — Health check                    ║');
  console.log('  ╚══════════════════════════════════════════════════════╝');
  console.log('');
  if (MODE === 'mock') {
    console.log('  ⚠  Running in MOCK mode — responses are simulated');
    console.log('  💡 For real NotebookLM: node bridge-server.js --puppeteer');
    console.log('');
  }
});
