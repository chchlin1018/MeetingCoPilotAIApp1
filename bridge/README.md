# NotebookLM Bridge

Local HTTP bridge between MeetingCopilot macOS app and Google NotebookLM.

## Architecture

```
MeetingCopilot App (Swift)
    │
    │  POST http://localhost:3210/query
    │  { notebookId, question, maxResults }
    │
    ▼
Bridge Server (Node.js)
    │
    ├─ Mock Mode ─────→ Simulated responses (dev/testing)
    ├─ Puppeteer Mode ─→ Browser automation vs notebooklm.google.com
    └─ API Mode ───────→ (Future) Google Enterprise API
```

## Quick Start

```bash
cd bridge
npm install

# Development (mock responses)
npm run dev

# Production (browser automation)
npm start
```

## Modes

### Mock Mode (default)

Returns simulated responses based on keyword matching against a built-in UMC Digital Twin knowledge base. Perfect for development and UI testing.

```bash
node bridge-server.js --mock
```

### Puppeteer Mode

Automates a real Chrome browser to query notebooklm.google.com.

**First-time setup** (one-time Google login):
```bash
node bridge-server.js --puppeteer --login
# A browser window opens — complete Google login manually
# Session saved to ./browser-data/
# Ctrl+C when done
```

**Normal operation** (headless):
```bash
node bridge-server.js --puppeteer
```

### API Mode (Future)

When Google releases the NotebookLM Enterprise API, this mode will use direct REST calls instead of browser automation.

## API Endpoints

### `POST /query`

Query a notebook for relevant passages.

```json
// Request
{
  "notebookId": "notebook_abc123",
  "question": "AVEVA 和 IDTF 的差異是什麼？",
  "maxResults": 3
}

// Response
{
  "results": [
    {
      "content": "AVEVA Select operates on a proprietary data model...",
      "source": "AVEVA Competitive Analysis.docx",
      "sourceType": "DOCX",
      "relevance": 0.92,
      "page": "Section 3: Competitive Positioning"
    }
  ],
  "meta": { "latency": 450, "mode": "mock", "notebookId": "notebook_abc123" }
}
```

### `POST /notebooks`

List available notebooks.

### `POST /sources`

List sources in a notebook.

### `GET /health`

Health check.

## Testing

```bash
# Start the bridge first
npm run dev

# In another terminal
npm test
```

## Configuration

Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

| Variable | Default | Description |
|----------|---------|-------------|
| PORT | 3210 | Bridge server port |
| MODE | mock | `mock` or `puppeteer` |
| GOOGLE_EMAIL | | For Puppeteer login |
| DEFAULT_NOTEBOOK_ID | | Default notebook |
| LOG_LEVEL | info | `debug`, `info`, `warn`, `error` |

## Mock Knowledge Base

The mock engine includes 10 realistic document passages covering:

| Topic | Source Document |
|-------|-----------------|
| AVEVA competitive analysis | AVEVA Competitive Analysis.docx |
| UMC OEE data | UMC Q3 Financial Report.pdf |
| Security architecture | ISO 27001 Compliance Checklist.xlsx |
| ROI business case | IDTF Architecture Overview.pptx |
| OpenUSD + Teamcenter | IDTF Architecture Overview.pptx |
| TSMC reference case | TSMC PoC Results Summary.pdf |
| Implementation timeline | IDTF Architecture Overview.pptx |
| Team background | IDTF Architecture Overview.pptx |
| Kevin Liu stakeholder | Kevin Liu LinkedIn Profile Notes.txt |
| Market overview | Semiconductor DT Market Report 2024 |

This matches the demo TalkingPoints and Q&A items in `UsageExample.swift`.
