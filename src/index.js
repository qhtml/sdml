'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseSdml, validateAst } = require('../modules/sdml-parser/src');
const { buildRuntime } = require('../modules/sdml-runtime/src');

function loadSdmlFile(filePath) {
  const absolutePath = path.resolve(process.cwd(), filePath);
  const source = fs.readFileSync(absolutePath, 'utf8');
  return { absolutePath, source };
}

async function runSdmlFile(filePath, options = {}) {
  const { absolutePath, source } = loadSdmlFile(filePath);
  const { ast } = parseSdml(source, absolutePath);
  const validation = validateAst(ast);
  if (!validation.ok) {
    const message = validation.errors.map((x) => `- ${x}`).join('\n');
    throw new Error(`SDML validation failed:\n${message}`);
  }

  const runtime = buildRuntime(ast, options);
  await runtime.start();
  return runtime;
}

module.exports = {
  loadSdmlFile,
  runSdmlFile,
};
