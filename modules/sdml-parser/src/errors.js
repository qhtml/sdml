'use strict';

class SdmlSyntaxError extends Error {
  constructor(message, filePath, line, column) {
    super(`${filePath || '<inline>'}:${line}:${column} ${message}`);
    this.name = 'SdmlSyntaxError';
    this.filePath = filePath || '<inline>';
    this.line = line;
    this.column = column;
  }
}

function lineAndColumn(source, index) {
  const safeIndex = Math.max(0, Math.min(index, source.length));
  let line = 1;
  let col = 1;
  for (let i = 0; i < safeIndex; i += 1) {
    if (source[i] === '\n') {
      line += 1;
      col = 1;
    } else {
      col += 1;
    }
  }
  return { line, column: col };
}

module.exports = {
  SdmlSyntaxError,
  lineAndColumn,
};
