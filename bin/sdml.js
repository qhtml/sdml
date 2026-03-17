#!/usr/bin/env node
'use strict';

const { main } = require('../src/cli');

main().then((code) => {
  if (typeof code === 'number') {
    process.exitCode = code;
  }
});
