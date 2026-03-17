'use strict';

const { parseSdml, validateAst } = require('./sdml-parser');
const { SdmlSyntaxError } = require('./errors');

module.exports = {
  parseSdml,
  validateAst,
  SdmlSyntaxError,
};
