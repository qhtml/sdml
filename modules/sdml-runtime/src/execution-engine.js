'use strict';

const vm = require('node:vm');
const { sanitize } = require('./sanitize');

function deepFreeze(value) {
  if (!value || typeof value !== 'object') {
    return value;
  }
  Object.freeze(value);
  for (const key of Object.keys(value)) {
    deepFreeze(value[key]);
  }
  return value;
}

function astToExpression(expr) {
  if (!expr || !expr.type) {
    throw new Error('invalid expression AST node');
  }
  if (expr.type === 'Literal') {
    return JSON.stringify(expr.value);
  }
  if (expr.type === 'Identifier') {
    return `__resolveIdentifier(${JSON.stringify(expr.name)})`;
  }
  if (expr.type === 'Member') {
    if (!expr.object || expr.object.type !== 'Identifier') {
      throw new Error('only direct member access is supported');
    }
    return `__getMember(${JSON.stringify(expr.object.name)}, ${JSON.stringify(expr.property)})`;
  }
  if (expr.type === 'Call') {
    if (!expr.callee || expr.callee.type !== 'Identifier') {
      throw new Error('only direct function calls are supported');
    }
    const args = expr.args.map((arg) => astToExpression(arg)).join(', ');
    return `__invoke(${JSON.stringify(expr.callee.name)}, [${args}])`;
  }
  throw new Error(`unsupported expression AST type '${expr.type}'`);
}

function evaluateExpression(exprAst, runtime, localScope) {
  const scriptSource = `(${astToExpression(exprAst)})`;
  const script = new vm.Script(scriptSource, { filename: 'sdml-ast-expression.vm' });

  const sandbox = {
    __resolveIdentifier(name) {
      if (name === 'request') {
        return runtime.request;
      }
      if (name === 'this') {
        return runtime.state;
      }
      if (Object.prototype.hasOwnProperty.call(localScope, name)) {
        return localScope[name];
      }
      if (runtime.functions.has(name)) {
        return runtime.functions.get(name);
      }
      throw new Error(`identifier '${name}' is not resolvable`);
    },
    __getMember(baseName, prop) {
      if (baseName === 'request') {
        if (!runtime.requestParams.has(prop)) {
          throw new Error(`request.${prop} is not declared`);
        }
        return runtime.request[prop];
      }
      if (baseName === 'this') {
        if (!runtime.properties.has(prop)) {
          throw new Error(`this.${prop} is not declared`);
        }
        return runtime.state[prop];
      }
      throw new Error(`member access on '${baseName}' is not allowed`);
    },
    __invoke(name, args) {
      if (name === 'sanitize') {
        return sanitize(args[0]);
      }
      return executeFunctionByName(name, args, runtime, localScope.__depth || 0);
    },
  };

  return script.runInNewContext(sandbox, {
    timeout: runtime.scriptTimeoutMs,
    microtaskMode: 'afterEvaluate',
  });
}

function renderTemplate(parts, runtime, localScope) {
  let out = '';
  for (const part of parts) {
    if (part.type === 'Text') {
      out += part.value;
      continue;
    }
    if (part.type === 'Expr') {
      const value = evaluateExpression(part.expr, runtime, localScope);
      out += value === undefined || value === null ? '' : String(value);
    }
  }
  return out.trim();
}

function executeStatements(statements, runtime, localScope) {
  for (const stmt of statements) {
    if (stmt.type === 'PropertyDecl') {
      runtime.properties.add(stmt.name);
      if (!Object.prototype.hasOwnProperty.call(runtime.state, stmt.name)) {
        runtime.state[stmt.name] = undefined;
      }
      continue;
    }

    if (stmt.type === 'FunctionDecl') {
      runtime.functions.set(stmt.name, stmt);
      continue;
    }

    if (stmt.type === 'Assign') {
      const match = /^this\.([A-Za-z_][A-Za-z0-9_]*)$/.exec(stmt.target);
      if (!match) {
        throw new Error(`invalid assignment target '${stmt.target}'`);
      }
      const propName = match[1];
      if (!runtime.properties.has(propName)) {
        throw new Error(`assignment to undeclared property 'this.${propName}'`);
      }
      runtime.state[propName] = evaluateExpression(stmt.expression, runtime, localScope);
      continue;
    }

    if (stmt.type === 'ReturnTemplate') {
      return {
        returned: true,
        value: renderTemplate(stmt.parts, runtime, localScope),
      };
    }

    throw new Error(`unsupported statement type '${stmt.type}'`);
  }

  return {
    returned: false,
    value: undefined,
  };
}

function executeFunctionByName(name, args, runtime, depth) {
  if (!runtime.functions.has(name)) {
    throw new Error(`function '${name}' is not declared`);
  }
  if (depth >= runtime.maxCallDepth) {
    throw new Error('function call depth limit reached');
  }

  const fn = runtime.functions.get(name);
  const localScope = { __depth: depth + 1 };
  for (let i = 0; i < fn.params.length; i += 1) {
    localScope[fn.params[i]] = i < args.length ? args[i] : undefined;
  }

  const result = executeStatements(fn.body, runtime, localScope);
  return result.value;
}

function buildExecutionRuntime(ast, location, requestParams, options = {}) {
  const onRequestStmts = location.onRequest ? location.onRequest.statements : [];
  const onRequestProps = onRequestStmts.filter((x) => x.type === 'PropertyDecl').map((x) => x.name);

  const properties = new Set([
    ...(ast.properties || []),
    ...(location.properties || []),
    ...onRequestProps,
  ]);

  const functions = new Map();
  for (const fn of ast.functions || []) {
    functions.set(fn.name, fn);
  }
  for (const fn of location.functions || []) {
    functions.set(fn.name, fn);
  }
  for (const fn of onRequestStmts.filter((x) => x.type === 'FunctionDecl')) {
    functions.set(fn.name, fn);
  }

  const state = {};
  for (const prop of properties) {
    state[prop] = undefined;
  }

  return {
    state,
    properties,
    functions,
    request: deepFreeze({ ...requestParams }),
    requestParams: new Set(location.parameters || []),
    scriptTimeoutMs: Number.isInteger(options.scriptTimeoutMs) ? options.scriptTimeoutMs : 40,
    maxCallDepth: Number.isInteger(options.maxCallDepth) ? options.maxCallDepth : 20,
  };
}

function executeLocation(ast, location, requestParams, options = {}) {
  const runtime = buildExecutionRuntime(ast, location, requestParams, options);
  const result = executeStatements((location.onRequest && location.onRequest.statements) || [], runtime, { __depth: 0 });

  if (!result.returned) {
    throw new Error(`location '${location.url}' did not return a response`);
  }

  return {
    result: result.value,
    properties: runtime.state,
  };
}

module.exports = {
  executeLocation,
};
