'use strict';

function sanitize(input) {
  if (input === null || input === undefined) {
    return '';
  }
  const text = String(input);
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/\u0000/g, '');
}

module.exports = {
  sanitize,
};
