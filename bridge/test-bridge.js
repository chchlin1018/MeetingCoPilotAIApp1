#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════
// test-bridge.js
// Quick test script for the NotebookLM bridge
// Usage: npm test (while bridge is running)
// ═══════════════════════════════════════════════════════════════════════════

const BASE = process.env.BRIDGE_URL || 'http://localhost:3210';

async function test(name, fn) {
  try {
    const start = Date.now();
    const result = await fn();
    const ms = Date.now() - start;
    console.log(`✅ ${name} (${ms}ms)`);
    return result;
  } catch (err) {
    console.log(`❌ ${name}: ${err.message}`);
    return null;
  }
}

async function post(path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function get(path) {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function main() {
  console.log(`\n🧪 Testing NotebookLM Bridge at ${BASE}\n`);

  // 1. Health check
  const health = await test('Health check', async () => {
    const data = await get('/health');
    if (data.status !== 'ok') throw new Error('Not ok');
    console.log(`   Mode: ${data.mode}, Uptime: ${data.uptime.toFixed(1)}s`);
    return data;
  });

  // 2. Query — AVEVA comparison (should match)
  await test('Query: AVEVA comparison', async () => {
    const data = await post('/query', {
      notebookId: 'nb_test',
      question: 'AVEVA 和 IDTF 的差異是什麼？',
      maxResults: 3
    });
    console.log(`   Results: ${data.results.length}`);
    data.results.forEach((r, i) => {
      console.log(`   [${i + 1}] ${r.source} (${(r.relevance * 100).toFixed(0)}%) — ${r.content.substring(0, 60)}...`);
    });
    if (data.results.length === 0) throw new Error('Expected results');
    return data;
  });

  // 3. Query — Security (should match)
  await test('Query: Security compliance', async () => {
    const data = await post('/query', {
      notebookId: 'nb_test',
      question: 'How does IDTF handle security and ISO compliance?',
      maxResults: 2
    });
    console.log(`   Results: ${data.results.length}`);
    if (data.results.length === 0) throw new Error('Expected results');
    return data;
  });

  // 4. Query — ROI (should match)
  await test('Query: ROI and cost', async () => {
    const data = await post('/query', {
      notebookId: 'nb_test',
      question: 'ROI 和投資成本多少？',
      maxResults: 3
    });
    console.log(`   Results: ${data.results.length}`);
    return data;
  });

  // 5. Query — No match (should return empty or low relevance)
  await test('Query: Unrelated topic', async () => {
    const data = await post('/query', {
      notebookId: 'nb_test',
      question: 'What is the weather in Tokyo today?',
      maxResults: 3
    });
    console.log(`   Results: ${data.results.length} (expected 0 or low)`);
    return data;
  });

  // 6. Query — Kevin Liu stakeholder
  await test('Query: Kevin Liu concerns', async () => {
    const data = await post('/query', {
      notebookId: 'nb_test',
      question: 'Kevin Liu IT VP 的主要關注點是什麼？',
      maxResults: 2
    });
    console.log(`   Results: ${data.results.length}`);
    return data;
  });

  // 7. List notebooks
  await test('List notebooks', async () => {
    const data = await post('/notebooks', {});
    console.log(`   Notebooks: ${data.notebooks.length}`);
    data.notebooks.forEach(nb => console.log(`   - ${nb.name} (${nb.id})`));
    return data;
  });

  // 8. List sources
  await test('List sources', async () => {
    const data = await post('/sources', { notebookId: 'nb_test' });
    console.log(`   Sources: ${data.sources.length}`);
    data.sources.forEach(s => console.log(`   - ${s.title} [${s.type}]`));
    return data;
  });

  // 9. Missing question (should 400)
  await test('Error: Missing question', async () => {
    try {
      await post('/query', { notebookId: 'nb_test' });
      throw new Error('Should have failed');
    } catch (err) {
      if (err.message === 'HTTP 400') return 'Correctly rejected';
      throw err;
    }
  });

  console.log('\n🎉 All tests complete!\n');
}

main().catch(err => {
  console.error('\n💥 Test runner error:', err.message);
  process.exit(1);
});
