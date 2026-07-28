<?php
// Collection endpoint: receives the JSON report the app produces (BenchmarkReportJSON), validates
// its shape, and archives one file per report. No database: files are the storage, index.php
// aggregates them on read.

require __DIR__ . '/config.php';

header('Content-Type: application/json; charset=utf-8');

// No `never` return type: it needs PHP 8.1, and the endpoint should survive a cluster that
// serves an older engine than `.ovhconfig` asks for.
function fail(int $status, string $reason)
{
    http_response_code($status);
    echo json_encode(['status' => 'error', 'reason' => $reason]);
    exit;
}

/**
 * One counter file per address and per hour, holding one byte per POST that reached this check.
 *
 * Counts attempts rather than accepted reports: a client looping on a payload the endpoint refuses
 * is exactly what this is for.
 *
 * The address is salted-hashed and never stored in clear, and a counter is deleted as soon as its
 * hour has passed: this is a throttle, not a log of who measured what. `FILE_APPEND` is atomic
 * enough for a counter, which avoids holding a lock on a request path.
 *
 * Fails **open** on a storage problem: losing a legitimate report is worse than letting one
 * through uncounted.
 */
function within_rate_limit(): bool
{
    $address = $_SERVER['REMOTE_ADDR'] ?? '';
    if ($address === '') {
        return true;
    }
    if (!is_dir(RATE_DIR) && !mkdir(RATE_DIR, 0755, true)) {
        return true;
    }
    $hour = gmdate('YmdH');
    // Salted with the day so a counter cannot be correlated across days even if the files leaked.
    $key = substr(hash('sha256', $address . '|' . gmdate('Ymd')), 0, 32);
    $path = RATE_DIR . '/' . $hour . '-' . $key;
    $count = is_file($path) ? (int) filesize($path) : 0;
    if ($count >= MAX_REPORTS_PER_HOUR) {
        return false;
    }
    file_put_contents($path, '.', FILE_APPEND);

    // Prune the previous hours, so the directory never grows without bound.
    foreach (glob(RATE_DIR . '/*') ?: [] as $file) {
        if (strncmp(basename($file), $hour, strlen($hour)) !== 0) {
            unlink($file);
        }
    }
    return true;
}

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    fail(405, 'POST only');
}
$contentType = $_SERVER['CONTENT_TYPE'] ?? '';
if (stripos($contentType, 'application/json') === false) {
    fail(415, 'expected application/json');
}
if (!within_rate_limit()) {
    fail(429, 'too many reports from this address, try again later');
}
$body = file_get_contents('php://input', false, null, 0, MAX_BODY_BYTES + 1);
if ($body === false || $body === '') {
    fail(400, 'empty body');
}
if (strlen($body) > MAX_BODY_BYTES) {
    fail(413, 'report too large');
}

$report = json_decode($body, true);
if (!is_array($report)) {
    fail(400, 'invalid JSON');
}

// Shape checks: enough to reject noise, not a full schema. Everything the page renders is
// escaped on output, so unexpected string content is a display concern, never an injection one.
$version = $report['benchmarkVersion'] ?? null;
if (!is_int($version) || $version < 1) {
    fail(422, 'missing benchmarkVersion');
}
if ($version < MIN_PROTOCOL_VERSION) {
    fail(422, 'protocol version too old to aggregate');
}
$machine = $report['machine'] ?? null;
if (!is_array($machine) || !is_string($machine['gpuName'] ?? null)
    || !is_int($machine['memoryGigabytes'] ?? null)) {
    fail(422, 'missing machine block');
}
$models = $report['models'] ?? null;
if (!is_array($models) || $models === [] || count($models) > 50) {
    fail(422, 'missing or oversized models block');
}
if (!is_string($report['measuredAt'] ?? null)) {
    fail(422, 'missing measuredAt');
}

// Durations are checked here and not only rendered defensively: `(float) "abc"` is 0.0, so a
// single report with a non-numeric duration would silently halve a published median instead of
// looking wrong. A model that failed carries no run at all, which stays valid.
foreach ($models as $measure) {
    $runs = $measure['runs'] ?? [];
    if (!is_array($runs)) {
        fail(422, 'runs must be a list');
    }
    foreach ($runs as $run) {
        if (!is_array($run) || !isset($run['seconds'])) {
            fail(422, 'a run has no duration');
        }
        if (!is_numeric($run['seconds']) || (float) $run['seconds'] <= 0) {
            fail(422, 'a run duration is not a positive number');
        }
    }
}

if (!is_dir(DATA_DIR) && !mkdir(DATA_DIR, 0755, true)) {
    fail(500, 'storage unavailable');
}
$stored = glob(DATA_DIR . '/*.json');
if ($stored !== false && count($stored) >= MAX_STORED_REPORTS) {
    fail(503, 'storage full');
}

// Re-encoded rather than the raw body, so storage only ever contains what json_decode accepted.
// The content hash makes the endpoint idempotent: the same report sent twice lands on one file.
$canonical = json_encode($report, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
$id = substr(sha1($canonical), 0, 16);
$path = DATA_DIR . '/' . gmdate('Ymd') . '-' . $id . '.json';

$temp = tempnam(DATA_DIR, 'upload-');
if ($temp === false || file_put_contents($temp, $canonical) === false || !rename($temp, $path)) {
    if (is_string($temp) && is_file($temp)) {
        unlink($temp);
    }
    fail(500, 'write failed');
}

echo json_encode(['status' => 'ok', 'id' => $id]);
