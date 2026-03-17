'use strict';

const { SdmlSyntaxError, lineAndColumn } = require('./errors');

class DslReader {
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

  currentGlobalIndex() {
    return this.baseOffset + this.i;
  }

  fail(msg, localIndex = this.i) {
    const globalIndex = this.baseOffset + localIndex;
    const lc = lineAndColumn(this.rootSource, globalIndex);
    throw new SdmlSyntaxError(msg, this.filePath, lc.line, lc.column);
  }

  skipWs() {
    while (!this.eof()) {
      const ch = this.peek();
      if (ch === ' ' || ch === '\t' || ch === '\r' || ch === '\n' || ch === ';') {
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
      break;
    }
  }

  readIdentifier() {
    const start = this.i;
    if (!/[A-Za-z_]/.test(this.peek() || '')) {
      this.fail('expected identifier');
    }
    this.i += 1;
    while (!this.eof() && /[A-Za-z0-9_]/.test(this.peek())) {
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
          return this.source.slice(start, this.i - 1);
        }
      }
    }
    this.fail(`unterminated '${openChar}${closeChar}' block`, start - 1);
  }

  readStatementChunk() {
    const start = this.i;
    let depth = 0;
    let quote = null;
    let escaped = false;
    while (!this.eof()) {
      const ch = this.peek();
      if (quote) {
        this.i += 1;
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === quote) {
          quote = null;
        }
        continue;
      }
      if (ch === '"' || ch === '\'') {
        quote = ch;
        this.i += 1;
        continue;
      }
      if (ch === '(') {
        depth += 1;
        this.i += 1;
        continue;
      }
      if (ch === ')') {
        depth = Math.max(0, depth - 1);
        this.i += 1;
        continue;
      }
      if (depth === 0 && (ch === '\n' || ch === ';')) {
        break;
      }
      this.i += 1;
    }
    return this.source.slice(start, this.i).trim();
  }
}

class ExprReader {
  constructor(source, context) {
    this.source = source.trim();
    this.context = context;
    this.i = 0;
  }

  eof() {
    return this.i >= this.source.length;
  }

  peek(n = 0) {
    return this.source[this.i + n];
  }

  fail(msg) {
    const idx = this.context.baseOffset + this.context.localIndex + this.i;
    const lc = lineAndColumn(this.context.rootSource, idx);
    throw new SdmlSyntaxError(msg, this.context.filePath, lc.line, lc.column);
  }

  skipWs() {
    while (!this.eof() && /\s/.test(this.peek())) {
      this.i += 1;
    }
  }

  parse() {
    this.skipWs();
    const node = this.parsePrimary();
    this.skipWs();
    if (!this.eof()) {
      this.fail('unexpected trailing expression content');
    }
    return node;
  }

  parsePrimary() {
    this.skipWs();
    const ch = this.peek();
    if (!ch) {
      this.fail('empty expression');
    }
    let node;
    if (ch === '"' || ch === '\'') {
      node = { type: 'Literal', value: this.readString() };
    } else if (/[0-9]/.test(ch)) {
      node = { type: 'Literal', value: this.readNumber() };
    } else if (/[A-Za-z_]/.test(ch)) {
      node = { type: 'Identifier', name: this.readIdentifier() };
    } else if (ch === '(') {
      this.i += 1;
      node = this.parsePrimary();
      this.skipWs();
      if (this.peek() !== ')') {
        this.fail("expected ')' in expression");
      }
      this.i += 1;
    } else {
      this.fail(`unsupported expression token '${ch}'`);
    }

    while (true) {
      this.skipWs();
      if (this.peek() === '.') {
        this.i += 1;
        const prop = this.readIdentifier();
        node = { type: 'Member', object: node, property: prop };
        continue;
      }
      if (this.peek() === '(') {
        this.i += 1;
        const args = [];
        this.skipWs();
        if (this.peek() !== ')') {
          while (true) {
            const arg = this.parsePrimary();
            args.push(arg);
            this.skipWs();
            if (this.peek() === ',') {
              this.i += 1;
              this.skipWs();
              continue;
            }
            break;
          }
        }
        if (this.peek() !== ')') {
          this.fail("expected ')' to close call");
        }
        this.i += 1;
        node = { type: 'Call', callee: node, args };
        continue;
      }
      break;
    }

    return node;
  }

  readIdentifier() {
    const start = this.i;
    if (!/[A-Za-z_]/.test(this.peek() || '')) {
      this.fail('expected identifier');
    }
    this.i += 1;
    while (!this.eof() && /[A-Za-z0-9_]/.test(this.peek())) {
      this.i += 1;
    }
    return this.source.slice(start, this.i);
  }

  readString() {
    const quote = this.peek();
    let escaped = false;
    this.i += 1;
    let out = '';
    while (!this.eof()) {
      const ch = this.peek();
      this.i += 1;
      if (escaped) {
        out += ch;
        escaped = false;
        continue;
      }
      if (ch === '\\') {
        escaped = true;
        continue;
      }
      if (ch === quote) {
        return out;
      }
      out += ch;
    }
    this.fail('unterminated string literal');
  }

  readNumber() {
    const start = this.i;
    while (!this.eof() && /[0-9.]/.test(this.peek())) {
      this.i += 1;
    }
    const text = this.source.slice(start, this.i);
    const value = Number(text);
    if (!Number.isFinite(value)) {
      this.fail('invalid numeric literal');
    }
    return value;
  }
}

function parseExpression(exprText, context) {
  const parser = new ExprReader(exprText, context);
  return parser.parse();
}

function parseTemplateParts(content, context) {
  const parts = [];
  let i = 0;
  let textStart = 0;
  while (i < content.length) {
    if (content[i] === '$' && content[i + 1] === '{') {
      if (textStart < i) {
        parts.push({ type: 'Text', value: content.slice(textStart, i) });
      }
      i += 2;
      const exprStart = i;
      let depth = 1;
      let quote = null;
      let escaped = false;
      while (i < content.length) {
        const ch = content[i];
        i += 1;
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
        if (ch === '{') {
          depth += 1;
          continue;
        }
        if (ch === '}') {
          depth -= 1;
          if (depth === 0) {
            const exprSource = content.slice(exprStart, i - 1).trim();
            if (!exprSource) {
              throw new SdmlSyntaxError('empty template interpolation', context.filePath, context.line, context.column);
            }
            const ast = parseExpression(exprSource, {
              filePath: context.filePath,
              rootSource: context.rootSource,
              baseOffset: context.baseOffset,
              localIndex: context.localIndex + exprStart,
            });
            parts.push({ type: 'Expr', expr: ast });
            textStart = i;
            break;
          }
        }
      }
      if (depth !== 0) {
        throw new SdmlSyntaxError('unterminated template interpolation', context.filePath, context.line, context.column);
      }
      continue;
    }
    i += 1;
  }
  if (textStart < content.length) {
    parts.push({ type: 'Text', value: content.slice(textStart) });
  }
  return parts;
}

function parseDslStatements(source, options = {}) {
  const reader = new DslReader(source, options.filePath, options.rootSource || source, options.baseOffset || 0);
  const statements = [];

  while (true) {
    reader.skipWs();
    if (reader.eof()) {
      break;
    }

    const stmtStart = reader.i;

    if (reader.readKeyword('property')) {
      reader.skipWs();
      const name = reader.readIdentifier();
      statements.push({ type: 'PropertyDecl', name });
      continue;
    }

    if (reader.readKeyword('function')) {
      reader.skipWs();
      const name = reader.readIdentifier();
      reader.skipWs();
      reader.expectChar('(');
      const paramsText = reader.readBalanced('(', ')');
      const params = paramsText
        .split(',')
        .map((x) => x.trim())
        .filter(Boolean);
      for (const param of params) {
        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(param)) {
          reader.fail(`invalid function parameter '${param}'`, stmtStart);
        }
      }
      reader.skipWs();
      const body = reader.readBalanced('{', '}');
      const bodyStmts = parseDslStatements(body, {
        filePath: options.filePath,
        rootSource: options.rootSource || source,
        baseOffset: (options.baseOffset || 0) + stmtStart,
      });
      statements.push({
        type: 'FunctionDecl',
        name,
        params,
        body: bodyStmts,
      });
      continue;
    }

    if (reader.readKeyword('return')) {
      reader.skipWs();
      const template = reader.readBalanced('{', '}');
      const lc = lineAndColumn(options.rootSource || source, (options.baseOffset || 0) + stmtStart);
      const parts = parseTemplateParts(template, {
        filePath: options.filePath,
        rootSource: options.rootSource || source,
        baseOffset: options.baseOffset || 0,
        localIndex: stmtStart,
        line: lc.line,
        column: lc.column,
      });
      statements.push({ type: 'ReturnTemplate', parts });
      continue;
    }

    const target = reader.readStatementChunk();
    if (!target) {
      continue;
    }
    const eq = target.indexOf('=');
    if (eq < 1) {
      reader.fail('expected assignment or supported statement', stmtStart);
    }
    const lhs = target.slice(0, eq).trim();
    const rhs = target.slice(eq + 1).trim();
    if (!lhs || !rhs) {
      reader.fail('invalid assignment statement', stmtStart);
    }
    const exprAst = parseExpression(rhs, {
      filePath: options.filePath,
      rootSource: options.rootSource || source,
      baseOffset: options.baseOffset || 0,
      localIndex: stmtStart + eq + 1,
    });
    statements.push({
      type: 'Assign',
      target: lhs,
      expression: exprAst,
    });
  }

  return statements;
}

module.exports = {
  parseDslStatements,
  parseExpression,
};
