'use strict';

const { runSdmlFile } = require('./index');

function printUsage() {
  process.stdout.write(
    [
      'Usage:',
      '  sdml run --file <path> [--host <ip>] [--port <number>] [--threads <n>] [--script-timeout-ms <n>] [--max-call-depth <n>]',
      '',
      'Example:',
      '  sdml run --file ./server.sdml --port 6221 --threads 2',
      '',
    ].join('\n')
  );
}

function parseArgs(argv) {
  if (argv.length === 0 || argv.includes('--help') || argv.includes('-h')) {
    return { help: true };
  }

  const command = argv[0];
  if (command !== 'run') {
    throw new Error(`unsupported command '${command}'`);
  }

  const options = {};
  let file = null;

  for (let i = 1; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--file') {
      file = argv[++i];
      continue;
    }
    if (arg === '--host') {
      options.host = argv[++i];
      continue;
    }
    if (arg === '--port') {
      options.port = Number(argv[++i]);
      continue;
    }
    if (arg === '--threads') {
      options.workerThreads = Number(argv[++i]);
      continue;
    }
    if (arg === '--script-timeout-ms') {
      options.scriptTimeoutMs = Number(argv[++i]);
      continue;
    }
    if (arg === '--max-call-depth') {
      options.maxCallDepth = Number(argv[++i]);
      continue;
    }
    throw new Error(`unknown argument '${arg}'`);
  }

  if (!file) {
    throw new Error('missing required --file argument');
  }

  if (options.port !== undefined && (!Number.isInteger(options.port) || options.port <= 0 || options.port > 65535)) {
    throw new Error('port must be an integer in range 1..65535');
  }

  if (options.workerThreads !== undefined && (!Number.isInteger(options.workerThreads) || options.workerThreads < 1)) {
    throw new Error('threads must be an integer >= 1');
  }

  return { help: false, command, file, options };
}

async function main(argv = process.argv.slice(2)) {
  try {
    const parsed = parseArgs(argv);
    if (parsed.help) {
      printUsage();
      return 0;
    }

    const runtime = await runSdmlFile(parsed.file, parsed.options);
    process.stdout.write(`SDML runtime started on ${runtime.options.host}:${runtime.options.port}\n`);

    const shutdown = async (signal) => {
      process.stdout.write(`Received ${signal}; shutting down SDML runtime...\n`);
      try {
        await runtime.stop();
        process.exit(0);
      } catch (err) {
        process.stderr.write(`Failed to stop runtime: ${err.message}\n`);
        process.exit(1);
      }
    };

    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));

    return 0;
  } catch (error) {
    process.stderr.write(`${error.message}\n\n`);
    printUsage();
    return 1;
  }
}

module.exports = {
  parseArgs,
  main,
};
