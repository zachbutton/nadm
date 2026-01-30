#!/usr/bin/env node
const { spawnSync } = require('child_process');
const { readFileSync } = require('fs');
const { join } = require('path');

// In dev: read from file. In production: this gets replaced with embedded script.
let script;
try {
    // Try embedded script marker first (replaced during build)
    script = '{{CORE_SH}}';
    if (script === '{{' + 'CORE_SH}}') {
        // Not replaced - dev mode, read from file
        script = readFileSync(join(__dirname, '..', 'core.sh'), 'utf8');
    }
} catch (e) {
    console.error('Error: Could not load core.sh');
    process.exit(1);
}

const result = spawnSync('bash', ['-c', script + '\nmain'], {
    stdio: 'inherit',
    env: {
        ...process.env,
        NADM_ARGS: process.argv.slice(2).join(' ')
    }
});

process.exit(result.status || 0);
