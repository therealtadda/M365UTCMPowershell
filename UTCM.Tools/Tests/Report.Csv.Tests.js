'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(process.argv[2], 'utf8').replace(/^\uFEFF/, '');
const cases = JSON.parse(fs.readFileSync(process.argv[3], 'utf8').replace(/^\uFEFF/, ''));
new vm.Script(source);
const start = source.indexOf('  function csvCell(');
const end = source.indexOf('  function safeName(', start);
assert.ok(start >= 0 && end > start, 'CSV helpers must exist in the generated client script');
const context = vm.createContext({});
vm.runInContext(source.slice(start, end), context);
for (const test of cases) {
  const quoted = '"' + test.expected.replace(/"/g, '""') + '"';
  assert.equal(context.csvCell(test.value), quoted, JSON.stringify(test.value));
}
const expectedRows = ['"Value"'].concat(cases.map(test => '"' + test.expected.replace(/"/g, '""') + '"'));
assert.equal(context.toCsv(['Value'], cases.map(test => [test.value])), expectedRows.join('\r\n') + '\r\n');
console.log(`Browser CSV: ${cases.length} parity vectors passed; complete report script syntax is valid.`);
