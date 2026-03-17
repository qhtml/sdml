'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { parseSdml, validateAst } = require('../src');

test('parses README sample and validates', () => {
  const source = `
server {
  listen {
    ip { 127.0.0.1 }
    port { 6221 }
  }
  headers {
    Access-Control-Allow-CORS { https://whatever.com }
  }

  location {
    url { /api/test }
    parameters {
      name
      message
    }
    accept { GET POST }
    headers {
      X-Location-Policy { strict-mode }
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

  const { ast } = parseSdml(source, 'sample.sdml');
  assert.equal(ast.listen.port, 6221);
  assert.equal(ast.locations.length, 1);
  assert.equal(ast.headers['Access-Control-Allow-CORS'], 'https://whatever.com');
  assert.equal(ast.locations[0].headers['X-Location-Policy'], 'strict-mode');
  const returnStmt = ast.locations[0].onRequest.statements[2];
  assert.equal(returnStmt.type, 'ReturnTemplate');
  assert.equal(returnStmt.parts.filter((p) => p.type === 'Expr').length, 2);

  const result = validateAst(ast);
  assert.equal(result.ok, true, result.errors.join('\n'));
});

test('fails validation for undeclared request parameter usage', () => {
  const source = `
server {
  listen { ip { 127.0.0.1 } port { 6221 } }
  location {
    url { /api/test }
    parameters { name }
    accept { GET }
    property name
    onRequest {
      this.name = sanitize(request.unknown)
      return { ok }
    }
  }
}
`;

  const { ast } = parseSdml(source);
  const result = validateAst(ast);
  assert.equal(result.ok, false);
  assert.match(result.errors.join('\n'), /request property 'unknown'/);
});
