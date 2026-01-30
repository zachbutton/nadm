const { readFileSync, writeFileSync } = require('fs');
const { join } = require('path');

const PLACEHOLDER = "'{{CORE_SH}}'";

try {
    const corePath = join(__dirname, '..', 'core.sh');
    const wrapperPath = join(__dirname, '..', 'bin', 'nadm.js');

    const coreSh = readFileSync(corePath, 'utf8');
    let wrapper = readFileSync(wrapperPath, 'utf8');

    // Verify placeholder exists
    if (!wrapper.includes(PLACEHOLDER)) {
        console.error('Error: Placeholder not found in nadm.js. Already built?');
        process.exit(1);
    }

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

    wrapper = wrapper.replace(PLACEHOLDER, safeReplacement);

    writeFileSync(wrapperPath, wrapper);
    console.log('Build complete: core.sh embedded into bin/nadm.js');
} catch (e) {
    console.error('Build failed:', e.message);
    process.exit(1);
}
