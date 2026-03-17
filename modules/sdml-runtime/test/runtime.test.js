'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { parseSdml, validateAst } = require('../../sdml-parser/src');
const { buildRuntime } = require('../src');

function httpJson(url, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = http.request(url, {
      method,
      headers: data ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(data) } : {},
    }, (res) => {
      let raw = '';
      res.on('data', (chunk) => {
        raw += chunk;
      });
      res.on('end', () => {
        resolve({ status: res.statusCode, json: JSON.parse(raw), headers: res.headers });
      });
    });
    req.on('error', reject);
    if (data) {
      req.write(data);
    }
    req.end();
  });
}

test('runtime serves declared route and sanitizes request parameters', async () => {
  const source = `
server {
  listen { ip { 127.0.0.1 } port { 6221 } }
  headers {
    Access-Control-Allow-CORS { https://whatever.com }
    X-Server-Policy { strict }
  }
  location {
    url { /api/test }
    parameters { name message }
    accept { GET POST }
    headers {
      X-Location-Policy { local-only }
    }
    property name
    property message
    onRequest {
      this.name = sanitize(request.name)
      this.message = sanitize(request.message)
      return { hello \${this.name} we received your message: \${this.message}. }
    }
  }
}
`;

  const { ast } = parseSdml(source, 'runtime.sdml');
  const validation = validateAst(ast);
  assert.equal(validation.ok, true, validation.errors.join('\n'));

  const runtime = buildRuntime(ast, { port: 0, workerThreads: 1 });
  await runtime.start();

  try {
    const response = await httpJson(`http://127.0.0.1:${runtime.options.port}/api/test?name=<Mike>&message=yo`);
    assert.equal(response.status, 200);
    assert.match(response.json.result, /&lt;Mike&gt;/);
    assert.match(response.json.result, /yo/);
    assert.equal(typeof response.json.properties, 'object');
    assert.equal(response.headers['x-server-policy'], 'strict');
    assert.equal(response.headers['x-location-policy'], 'local-only');
    assert.equal(response.headers['access-control-allow-cors'], 'https://whatever.com');
  } finally {
    await runtime.stop();
  }
});
