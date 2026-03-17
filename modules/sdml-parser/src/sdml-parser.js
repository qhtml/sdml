'use strict';

const { SdmlSyntaxError, lineAndColumn } = require('./errors');
const { parseDslStatements } = require('./dsl-parser');

class BlockParser {
  constructor(source, filePath, rootSource, baseOffset) {
    this.source = source || '';
    this.filePath = filePath || '<inline>';
    this.rootSource = rootSource || this.source;
    this.baseOffset = baseOffset || 0;
    this.i = 0;
  }

  eof() {
    return this.i >= this.source.length;
  }

  peek(n = 0) {
    return this.source[this.i + n];
  }

  fail(msg, localIndex = this.i) {
    const globalIndex = this.baseOffset + localIndex;
    const lc = lineAndColumn(this.rootSource, globalIndex);
    throw new SdmlSyntaxError(msg, this.filePath, lc.line, lc.column);
  }

  skipWs() {
    while (!this.eof()) {
      const ch = this.peek();
      if (ch === ' ' || ch === '\t' || ch === '\r' || ch === '\n') {
        this.i += 1;
        continue;
      }
      if (ch === '/' && this.peek(1) === '/') {
        this.i += 2;
        while (!this.eof() && this.peek() !== '\n') {
          this.i += 1;
        }
        continue;
      }
      if (ch === '#') {
        this.i += 1;
        while (!this.eof() && this.peek() !== '\n') {
          this.i += 1;
        }
        continue;
      }
      break;
    }
  }

  readIdentifier() {
    if (!/[A-Za-z_]/.test(this.peek() || '')) {
      this.fail('expected identifier');
    }
    const start = this.i;
    this.i += 1;
    while (!this.eof() && /[A-Za-z0-9_]/.test(this.peek())) {
      this.i += 1;
    }
    return this.source.slice(start, this.i);
  }

  readHeaderName() {
    if (!/[A-Za-z0-9]/.test(this.peek() || '')) {
      this.fail('expected header name');
    }
    const start = this.i;
    this.i += 1;
    while (!this.eof() && /[A-Za-z0-9-]/.test(this.peek())) {
      this.i += 1;
    }
    return this.source.slice(start, this.i);
  }

  readKeyword(keyword) {
    const start = this.i;
    if (this.source.slice(start, start + keyword.length) !== keyword) {
      return false;
    }
    const end = start + keyword.length;
    if (/[A-Za-z0-9_]/.test(this.source[end] || '')) {
      return false;
    }
    this.i = end;
    return true;
  }

  expectChar(ch) {
    if (this.peek() !== ch) {
      this.fail(`expected '${ch}'`);
    }
    this.i += 1;
  }

  readBalanced(openChar, closeChar) {
    if (this.peek() !== openChar) {
      this.fail(`expected '${openChar}'`);
    }
    this.i += 1;
    const start = this.i;
    let depth = 1;
    let quote = null;
    let escaped = false;
    while (!this.eof()) {
      const ch = this.peek();
      this.i += 1;
      if (quote) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (ch === '\\') {
          escaped = true;
          continue;
        }
        if (ch === quote) {
          quote = null;
        }
        continue;
      }
      if (ch === '"' || ch === '\'') {
        quote = ch;
        continue;
      }
      if (ch === openChar) {
        depth += 1;
      } else if (ch === closeChar) {
        depth -= 1;
        if (depth === 0) {
          return {
            content: this.source.slice(start, this.i - 1),
            startGlobal: this.baseOffset + start,
          };
        }
      }
    }
    this.fail(`unterminated '${openChar}${closeChar}' block`, start - 1);
  }

  parseFunctionDecl() {
    this.skipWs();
    const name = this.readIdentifier();
    this.skipWs();
    this.expectChar('(');
    const paramsRaw = this.readBalanced('(', ')').content;
    const params = paramsRaw
      .split(',')
      .map((x) => x.trim())
      .filter(Boolean);
    for (const param of params) {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(param)) {
        this.fail(`invalid parameter name '${param}'`);
      }
    }
    this.skipWs();
    const body = this.readBalanced('{', '}');
    return {
      type: 'FunctionDecl',
      name,
      params,
      body: parseDslStatements(body.content, {
        filePath: this.filePath,
        rootSource: this.rootSource,
        baseOffset: body.startGlobal,
      }),
    };
  }
}

function parseListItems(content) {
  return content
    .split(/\s+/)
    .map((x) => x.trim())
    .filter(Boolean);
}

function parseListenBlock(block, filePath, rootSource) {
  const p = new BlockParser(block.content, filePath, rootSource, block.startGlobal);
  const listen = { ip: null, port: null };
  while (true) {
    p.skipWs();
    if (p.eof()) {
      break;
    }
    const keyword = p.readIdentifier();
    p.skipWs();
    const body = p.readBalanced('{', '}');
    if (keyword === 'ip') {
      listen.ip = body.content.trim();
    } else if (keyword === 'port') {
      const portText = body.content.trim();
      const port = Number(portText);
      if (!Number.isInteger(port) || port <= 0 || port > 65535) {
        p.fail(`invalid port '${portText}'`, p.i);
      }
      listen.port = port;
    } else {
      p.fail(`unsupported listen field '${keyword}'`, p.i);
    }
  }
  return listen;
}

function parseHeadersBlock(block, filePath, rootSource) {
  const p = new BlockParser(block.content, filePath, rootSource, block.startGlobal);
  const headers = {};
  while (true) {
    p.skipWs();
    if (p.eof()) {
      break;
    }
    const headerName = p.readHeaderName();
    p.skipWs();
    const valueBlock = p.readBalanced('{', '}');
    const value = valueBlock.content.trim();
    if (!value) {
      p.fail(`header '${headerName}' must have a non-empty value`);
    }
    headers[headerName] = value;
  }
  return headers;
}

function parseLocationBlock(block, filePath, rootSource) {
  const p = new BlockParser(block.content, filePath, rootSource, block.startGlobal);
  const location = {
    type: 'Location',
    url: null,
    parameters: [],
    accept: [],
    headers: {},
    properties: [],
    functions: [],
    onRequest: null,
  };

  while (true) {
    p.skipWs();
    if (p.eof()) {
      break;
    }
    const keyword = p.readIdentifier();

    if (keyword === 'property') {
      p.skipWs();
      location.properties.push(p.readIdentifier());
      continue;
    }

    if (keyword === 'function') {
      location.functions.push(p.parseFunctionDecl());
      continue;
    }

    p.skipWs();
    const body = p.readBalanced('{', '}');

    if (keyword === 'url') {
      location.url = body.content.trim();
    } else if (keyword === 'parameters') {
      location.parameters = parseListItems(body.content);
    } else if (keyword === 'accept') {
      location.accept = parseListItems(body.content).map((x) => x.toUpperCase());
    } else if (keyword === 'headers') {
      location.headers = parseHeadersBlock(body, filePath, rootSource);
    } else if (keyword === 'onRequest') {
      location.onRequest = {
        type: 'OnRequest',
        statements: parseDslStatements(body.content, {
          filePath,
          rootSource,
          baseOffset: body.startGlobal,
        }),
      };
    } else {
      p.fail(`unsupported location field '${keyword}'`);
    }
  }

  return location;
}

function parseServerBlock(block, filePath, rootSource) {
  const p = new BlockParser(block.content, filePath, rootSource, block.startGlobal);
  const server = {
    type: 'Server',
    listen: null,
    locations: [],
    headers: {},
    properties: [],
    functions: [],
  };

  while (true) {
    p.skipWs();
    if (p.eof()) {
      break;
    }
    const keyword = p.readIdentifier();

    if (keyword === 'property') {
      p.skipWs();
      server.properties.push(p.readIdentifier());
      continue;
    }

    if (keyword === 'function') {
      server.functions.push(p.parseFunctionDecl());
      continue;
    }

    p.skipWs();
    const body = p.readBalanced('{', '}');

    if (keyword === 'listen') {
      server.listen = parseListenBlock(body, filePath, rootSource);
    } else if (keyword === 'location') {
      server.locations.push(parseLocationBlock(body, filePath, rootSource));
    } else if (keyword === 'headers') {
      server.headers = parseHeadersBlock(body, filePath, rootSource);
    } else {
      p.fail(`unsupported server field '${keyword}'`);
    }
  }

  return server;
}

function validateExpression(expr, ctx, errors) {
  if (!expr || !expr.type) {
    errors.push('expression node is missing type');
    return;
  }

  if (expr.type === 'Literal') {
    return;
  }

  if (expr.type === 'Identifier') {
    const allowed = ctx.params.has(expr.name) || ctx.functions.has(expr.name) || expr.name === 'request' || expr.name === 'this';
    if (!allowed) {
      errors.push(`identifier '${expr.name}' is not allowed in scope`);
    }
    return;
  }

  if (expr.type === 'Member') {
    if (expr.object.type !== 'Identifier') {
      errors.push('only direct member access is allowed');
      return;
    }
    if (expr.object.name === 'request') {
      if (!ctx.parameters.has(expr.property)) {
        errors.push(`request property '${expr.property}' is not declared in parameters`);
      }
      return;
    }
    if (expr.object.name === 'this') {
      if (!ctx.properties.has(expr.property)) {
        errors.push(`this property '${expr.property}' is not declared`);
      }
      return;
    }
    errors.push(`unsupported member base '${expr.object.name}'`);
    return;
  }

  if (expr.type === 'Call') {
    if (expr.callee.type !== 'Identifier') {
      errors.push('only direct function calls are allowed');
      return;
    }
    const callee = expr.callee.name;
    if (!ctx.functions.has(callee) && callee !== 'sanitize') {
      errors.push(`function '${callee}' is not declared in scope`);
    }
    for (const arg of expr.args) {
      validateExpression(arg, ctx, errors);
    }
    return;
  }

  errors.push(`unsupported expression type '${expr.type}'`);
}

function validateStatements(statements, baseContext, errors) {
  const localProps = new Set(baseContext.properties);
  const localFns = new Set(baseContext.functions);

  for (const stmt of statements) {
    if (stmt.type === 'PropertyDecl') {
      localProps.add(stmt.name);
      continue;
    }

    if (stmt.type === 'FunctionDecl') {
      localFns.add(stmt.name);
      continue;
    }

    const ctx = {
      properties: localProps,
      functions: localFns,
      parameters: baseContext.parameters,
      params: baseContext.params,
    };

    if (stmt.type === 'Assign') {
      const match = /^this\.([A-Za-z_][A-Za-z0-9_]*)$/.exec(stmt.target);
      if (!match) {
        errors.push(`assignment target '${stmt.target}' must be this.<property>`);
      } else if (!localProps.has(match[1])) {
        errors.push(`assignment target this.${match[1]} references undeclared property`);
      }
      validateExpression(stmt.expression, ctx, errors);
      continue;
    }

    if (stmt.type === 'ReturnTemplate') {
      for (const part of stmt.parts) {
        if (part.type === 'Expr') {
          validateExpression(part.expr, ctx, errors);
        }
      }
      continue;
    }

    errors.push(`unsupported statement type '${stmt.type}'`);
  }

  for (const stmt of statements) {
    if (stmt.type === 'FunctionDecl') {
      const fnCtx = {
        properties: localProps,
        functions: localFns,
        parameters: baseContext.parameters,
        params: new Set(stmt.params),
      };
      validateStatements(stmt.body, fnCtx, errors);
    }
  }
}

function validateAst(ast) {
  const errors = [];
  if (!ast || ast.type !== 'Server') {
    return {
      ok: false,
      errors: ['root node must be Server'],
    };
  }

  if (!ast.listen) {
    errors.push('listen block is required');
  } else {
    if (!ast.listen.ip) {
      errors.push('listen.ip is required');
    }
    if (!ast.listen.port) {
      errors.push('listen.port is required');
    }
  }

  if (!Array.isArray(ast.locations) || ast.locations.length === 0) {
    errors.push('at least one location block is required');
  }

  for (const [name, value] of Object.entries(ast.headers || {})) {
    if (!/^[A-Za-z0-9-]+$/.test(name)) {
      errors.push(`server header '${name}' has invalid name format`);
    }
    if (!String(value || '').trim()) {
      errors.push(`server header '${name}' has empty value`);
    }
  }

  const serverProps = new Set(ast.properties || []);
  const serverFns = new Set((ast.functions || []).map((f) => f.name));

  for (const fn of ast.functions || []) {
    validateStatements(fn.body || [], {
      properties: serverProps,
      functions: serverFns,
      parameters: new Set(),
      params: new Set(fn.params || []),
    }, errors);
  }

  const routeKeys = new Set();

  for (const loc of ast.locations || []) {
    if (!loc.url) {
      errors.push('location.url is required');
      continue;
    }
    if (!Array.isArray(loc.accept) || loc.accept.length === 0) {
      errors.push(`location ${loc.url} must declare accept methods`);
      continue;
    }

    const key = `${loc.url}|${loc.accept.sort().join(',')}`;
    if (routeKeys.has(key)) {
      errors.push(`duplicate location route detected for ${loc.url}`);
    }
    routeKeys.add(key);

    const locProps = new Set([...serverProps, ...(loc.properties || [])]);
    const locFns = new Set([...serverFns, ...((loc.functions || []).map((f) => f.name))]);
    const params = new Set(loc.parameters || []);

    for (const fn of loc.functions || []) {
      validateStatements(fn.body || [], {
        properties: locProps,
        functions: locFns,
        parameters: params,
        params: new Set(fn.params || []),
      }, errors);
    }

    if (!loc.onRequest || !Array.isArray(loc.onRequest.statements) || loc.onRequest.statements.length === 0) {
      errors.push(`location ${loc.url} requires non-empty onRequest block`);
      continue;
    }

    for (const [name, value] of Object.entries(loc.headers || {})) {
      if (!/^[A-Za-z0-9-]+$/.test(name)) {
        errors.push(`location ${loc.url} header '${name}' has invalid name format`);
      }
      if (!String(value || '').trim()) {
        errors.push(`location ${loc.url} header '${name}' has empty value`);
      }
    }

    validateStatements(loc.onRequest.statements, {
      properties: locProps,
      functions: locFns,
      parameters: params,
      params: new Set(),
    }, errors);
  }

  return {
    ok: errors.length === 0,
    errors,
  };
}

function parseSdml(source, filePath = '<inline>') {
  const parser = new BlockParser(source, filePath, source, 0);
  parser.skipWs();
  if (!parser.readKeyword('server')) {
    parser.fail("file must start with 'server'");
  }
  parser.skipWs();
  const block = parser.readBalanced('{', '}');
  parser.skipWs();
  if (!parser.eof()) {
    parser.fail('unexpected content after server block');
  }
  const ast = parseServerBlock(block, filePath, source);
  return {
    ast,
  };
}

module.exports = {
  parseSdml,
  validateAst,
};
