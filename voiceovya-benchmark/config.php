<?php
// Shared constants of the benchmark endpoint and page. One source of truth: api.php validates
// with them, index.php filters with them.

const DATA_DIR = __DIR__ . '/data';
// Reports below this protocol version measured differently (warmup shared a prompt-cache prefix
// with the measured context) and cannot be aggregated with current ones.
const MIN_PROTOCOL_VERSION = 4;
// 300 KB. A real report is a few KB (~6 KB for four models), so this leaves room for a very large
// sweep while staying far from anything that could fill the hosting quota.
const MAX_BODY_BYTES = 307200;
// Storage backstop on a shared host: beyond this the endpoint refuses instead of filling the quota.
const MAX_STORED_REPORTS = 5000;
// Under this many samples a median is an anecdote; the page shows the value but flags it.
const MIN_SAMPLES_FOR_SOLID = 3;
