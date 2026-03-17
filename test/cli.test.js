'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { parseArgs } = require('../src/cli');

test('parseArgs parses run command', () => {
  const parsed = parseArgs(['run', '--file', 'server.sdml', '--port', '7000', '--threads', '2']);
  assert.equal(parsed.command, 'run');
  assert.equal(parsed.file, 'server.sdml');
  assert.equal(parsed.options.port, 7000);
  assert.equal(parsed.options.workerThreads, 2);
});

test('parseArgs rejects missing --file', () => {
  assert.throws(() => parseArgs(['run']), /missing required --file/);
});
