'use strict';

const { parentPort } = require('node:worker_threads');
const { executeLocation } = require('./execution-engine');

parentPort.on('message', (message) => {
  const { id, payload } = message;
  try {
    const location = payload.ast.locations[payload.locationIndex];
    const result = executeLocation(payload.ast, location, payload.requestParams, payload.options || {});
    parentPort.postMessage({ id, ok: true, result });
  } catch (error) {
    parentPort.postMessage({
      id,
      ok: false,
      error: {
        message: error && error.message ? error.message : String(error),
      },
    });
  }
});
