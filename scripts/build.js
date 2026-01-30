const { readFileSync, writeFileSync } = require('fs');
const { join } = require('path');

const coreSh = readFileSync(join(__dirname, '..', 'core.sh'), 'utf8');
const wrapperPath = join(__dirname, '..', 'bin', 'nadm.js');
let wrapper = readFileSync(wrapperPath, 'utf8');

// Escape for JavaScript template literal:
// - Backslashes must be escaped (\ -> \\)
// - Backticks must be escaped (` -> \`)
// - ${} must be escaped to prevent template interpolation (${ -> \${)
const escaped = coreSh
    .replace(/\\/g, '\\\\')
    .replace(/`/g, '\\`')
    .replace(/\$\{/g, '\\${');

// IMPORTANT: In String.replace(), $' and $` are special replacement patterns.
// We must escape ALL $ as $$ to prevent replacement pattern interpretation.
const safeReplacement = ('`' + escaped + '`').replace(/\$/g, '$$$$');

wrapper = wrapper.replace("'{{CORE_SH}}'", safeReplacement);

writeFileSync(wrapperPath, wrapper);
console.log('Build complete: core.sh embedded into bin/nadm.js');
