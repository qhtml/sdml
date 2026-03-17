'use strict';

const http = require('node:http');
const os = require('node:os');
const { executeLocation } = require('./execution-engine');
const { WorkerPool } = require('./worker-pool');

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (chunk) => {
      raw += chunk;
      if (raw.length > 1_000_000) {
        reject(new Error('request body too large'));
      }
    });
    req.on('end', () => {
      if (!raw.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(new Error('invalid JSON request body'));
      }
    });
    req.on('error', reject);
  });
}

function jsonReply(res, statusCode, payload, extraHeaders = {}) {
  const body = JSON.stringify(payload);
  res.statusCode = statusCode;
  for (const [name, value] of Object.entries(extraHeaders)) {
    res.setHeader(name, String(value));
  }
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('content-length', Buffer.byteLength(body));
  res.end(body);
}

class SdmlRuntime {
  constructor(ast, options = {}) {
    this.ast = ast;
    this.options = {
      host: options.host !== undefined ? options.host : ((ast.listen && ast.listen.ip) || '127.0.0.1'),
      port: options.port !== undefined ? options.port : ((ast.listen && ast.listen.port) || 6221),
      workerThreads: Number.isInteger(options.workerThreads)
        ? options.workerThreads
        : Math.max(1, Math.min(4, os.cpus().length - 1)),
      scriptTimeoutMs: Number.isInteger(options.scriptTimeoutMs) ? options.scriptTimeoutMs : 40,
      maxCallDepth: Number.isInteger(options.maxCallDepth) ? options.maxCallDepth : 20,
    };
    this.server = null;
    this.workerPool = null;
    this.serverHeaders = { ...(ast.headers || {}) };

    this.routeByPath = new Map();
    for (let i = 0; i < (ast.locations || []).length; i += 1) {
      const location = ast.locations[i];
      this.routeByPath.set(location.url, {
        location,
        index: i,
        headers: {
          ...this.serverHeaders,
          ...(location.headers || {}),
        },
      });
    }
  }

  async start() {
    if (this.server) {
      return;
    }

    if (this.options.workerThreads > 1) {
      this.workerPool = new WorkerPool(this.options.workerThreads);
    }

    this.server = http.createServer(async (req, res) => {
      try {
        const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
        const route = this.routeByPath.get(url.pathname);
        if (!route) {
          jsonReply(res, 404, { error: 'route not found' }, this.serverHeaders);
          return;
        }

        const method = (req.method || 'GET').toUpperCase();
        if (!route.location.accept.includes(method)) {
          jsonReply(res, 405, { error: 'method not allowed', allow: route.location.accept }, route.headers);
          return;
        }

        const body = (method === 'POST' || method === 'PUT' || method === 'PATCH')
          ? await readJsonBody(req)
          : {};

        const params = {};
        for (const name of route.location.parameters || []) {
          if (url.searchParams.has(name)) {
            params[name] = url.searchParams.get(name);
          } else if (body && Object.prototype.hasOwnProperty.call(body, name)) {
            params[name] = body[name];
          } else {
            params[name] = undefined;
          }
        }

        let execResult;
        const execOptions = {
          scriptTimeoutMs: this.options.scriptTimeoutMs,
          maxCallDepth: this.options.maxCallDepth,
        };
        if (this.workerPool) {
          execResult = await this.workerPool.execute({
            ast: this.ast,
            locationIndex: route.index,
            requestParams: params,
            options: execOptions,
          });
        } else {
          execResult = executeLocation(this.ast, route.location, params, execOptions);
        }

        jsonReply(res, 200, execResult, route.headers);
      } catch (error) {
        jsonReply(res, 500, {
          error: 'runtime execution failed',
          detail: error && error.message ? error.message : String(error),
        }, this.serverHeaders);
      }
    });

    await new Promise((resolve, reject) => {
      this.server.once('error', reject);
      this.server.listen(this.options.port, this.options.host, resolve);
    });

    const address = this.server.address();
    if (address && typeof address === 'object' && Number.isInteger(address.port)) {
      this.options.port = address.port;
    }
  }

  async stop() {
    if (!this.server) {
      return;
    }

    const server = this.server;
    this.server = null;

    await new Promise((resolve, reject) => {
      server.close((err) => {
        if (err) {
          reject(err);
        } else {
          resolve();
        }
      });
    });

    if (this.workerPool) {
      await this.workerPool.close();
      this.workerPool = null;
    }
  }
}

function buildRuntime(ast, options = {}) {
  return new SdmlRuntime(ast, options);
}

module.exports = {
  SdmlRuntime,
  buildRuntime,
};
