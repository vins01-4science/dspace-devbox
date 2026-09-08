#!/usr/bin/env node
// Filters a Maven dependency classpath file (':' separated) down to entries
// that actually exist as files on disk. Reactor module paths (target/classes
// dirs or unbuilt jars) are dropped — only real jars from ~/.m2 remain.
// Output: the surviving paths joined by ':' on stdout.
'use strict';

const fs = require('fs');

const input = process.argv[2];
if (!input) {
    console.error('usage: filter-cp.js <cp.txt>');
    process.exit(1);
}

const raw = fs.readFileSync(input, 'utf8').trim();
if (!raw) {
    console.error('empty classpath file: ' + input);
    process.exit(1);
}

const kept = raw
    .split(':')
    .filter((entry) => {
        if (!entry) return false;
        try {
            return fs.statSync(entry).isFile();
        } catch (err) {
            return false;
        }
    });

console.log(kept.join(':'));