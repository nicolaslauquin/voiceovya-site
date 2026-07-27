<?php
// Aggregation over the stored reports. Pure functions: index.php calls them and renders.
//
// Two axes on purpose, because the data behaves differently on each:
// - quality does not depend on the machine (same corpus, same prompt, deterministic scoring),
//   so it aggregates per model across every report;
// - speed depends on the chip and the RAM, so it aggregates per machine configuration.

require_once __DIR__ . '/config.php';

/** Decoded valid reports, oldest first. Skips files that stopped being readable JSON. */
function load_reports(): array
{
    $files = glob(DATA_DIR . '/*.json');
    if ($files === false) {
        return [];
    }
    sort($files);
    $reports = [];
    foreach ($files as $file) {
        $decoded = json_decode((string) file_get_contents($file), true);
        if (!is_array($decoded)) {
            continue;
        }
        if (($decoded['benchmarkVersion'] ?? 0) < MIN_PROTOCOL_VERSION) {
            continue;
        }
        // One platform per page for now; reports that predate the field are Mac by construction.
        if (($decoded['machine']['platform'] ?? 'mac') !== 'mac') {
            continue;
        }
        $reports[] = $decoded;
    }
    return $reports;
}

/** Median rather than mean everywhere: one throttled Mac or misconfigured runtime ruins a mean. */
function median(array $values): ?float
{
    if ($values === []) {
        return null;
    }
    sort($values);
    $count = count($values);
    $middle = intdiv($count, 2);
    return $count % 2 === 1 ? $values[$middle] : ($values[$middle - 1] + $values[$middle]) / 2;
}

/** "Apple M5 Pro · 64 Go": the chip and the RAM, the two numbers that predict local-model speed. */
function machine_config(array $report): string
{
    $machine = $report['machine'];
    return $machine['gpuName'] . ' · ' . $machine['memoryGigabytes'] . ' Go';
}

/**
 * Human names for the technical identifiers a report carries. The app deliberately ships
 * identifiers (`lmstudio`, `appleIntelligence`) so two reports stay comparable verbatim; a public
 * page has the opposite job, so the mapping lives here — on the reading side.
 *
 * Mirrors LLMProvider.displayName and DevRuntimeKind.displayName. An unknown key falls back to
 * itself: a provider added in the app must show up on the page before this file is updated,
 * ugly rather than absent.
 */
const HOST_NAMES = [
    'appleIntelligence' => 'Apple Intelligence',
    'applePrivateCloud' => 'Apple Private Cloud',
    'chatgpt' => 'ChatGPT',
    'claude' => 'Claude',
    'developerRuntime' => 'Serveur local',
    'ollama' => 'Ollama',
    'llamacpp' => 'llama.cpp',
    'lmstudio' => 'LM Studio',
];

/** Same rule as the app (BenchmarkTarget.label): the runtime is the host when there is one. */
function model_label(array $target): string
{
    $host = $target['runtime'] ?? $target['provider'];
    $host = HOST_NAMES[$host] ?? $host;
    $model = $target['model'] ?? '';
    return $model === '' ? $host : $host . ' · ' . $model;
}

/** Mirrors LLMProvider.isLocal: Private Cloud Compute is keyless but still off the machine. */
function is_local_provider(array $target): bool
{
    return in_array($target['provider'], ['appleIntelligence', 'developerRuntime'], true);
}

/**
 * A speed sample only counts when the machine was in a fair state: a sweep on battery saver or
 * under thermal throttling measures the power manager, not the model.
 */
function is_fair_speed_sample(array $report): bool
{
    $machine = $report['machine'];
    return !in_array($machine['thermalState'] ?? 'nominal', ['serious', 'critical'], true)
        && !($machine['isLowPowerModeEnabled'] ?? false);
}

/** First run of a measure: the new-note figure, the only one the prompt cache cannot flatter. */
function fresh_run(array $measure): ?array
{
    return $measure['runs'][0] ?? null;
}

/** Fact coverage of a scored run, 0..1: covered facts over expected facts, all sections together. */
function overall_coverage(array $quality): ?float
{
    $expected = 0;
    $covered = 0;
    foreach (['keyPoints', 'decisions', 'actions'] as $section) {
        if (!isset($quality[$section])) {
            continue;
        }
        $expected += $quality[$section]['expectedCount'] ?? 0;
        $covered += $quality[$section]['coveredCount'] ?? 0;
    }
    return $expected > 0 ? $covered / $expected : null;
}

/**
 * Per-model quality across every report: median score /100, median coverage, sample count,
 * locality. Sorted by score, best first.
 */
function quality_rows(array $reports): array
{
    $byModel = [];
    foreach ($reports as $report) {
        foreach ($report['models'] as $measure) {
            $run = fresh_run($measure);
            if ($run === null || !isset($run['quality']['score'])) {
                continue;
            }
            $label = model_label($measure['target']);
            $byModel[$label]['scores'][] = (float) $run['quality']['score'];
            $byModel[$label]['isLocal'] = is_local_provider($measure['target']);
            $coverage = overall_coverage($run['quality']);
            if ($coverage !== null) {
                $byModel[$label]['coverages'][] = $coverage;
            }
        }
    }
    $rows = [];
    foreach ($byModel as $label => $samples) {
        $rows[] = [
            'label' => $label,
            'score' => median($samples['scores']),
            'coverage' => median($samples['coverages'] ?? []),
            'isLocal' => $samples['isLocal'],
            'n' => count($samples['scores']),
        ];
    }
    usort($rows, fn($a, $b) => $b['score'] <=> $a['score']);
    return $rows;
}

/**
 * Per-configuration speed: for each chip·RAM, each model's median new-note seconds and sample
 * count, fastest first. Configurations sorted by their fastest model.
 */
function speed_sections(array $reports): array
{
    $byConfig = [];
    foreach ($reports as $report) {
        if (!is_fair_speed_sample($report)) {
            continue;
        }
        $config = machine_config($report);
        foreach ($report['models'] as $measure) {
            $run = fresh_run($measure);
            if ($run === null || !isset($run['seconds'])) {
                continue;
            }
            $byConfig[$config][model_label($measure['target'])][] = (float) $run['seconds'];
        }
    }
    $sections = [];
    foreach ($byConfig as $config => $byModel) {
        $rows = [];
        foreach ($byModel as $label => $seconds) {
            $rows[] = ['label' => $label, 'seconds' => median($seconds), 'n' => count($seconds)];
        }
        usort($rows, fn($a, $b) => $a['seconds'] <=> $b['seconds']);
        $sections[] = ['config' => $config, 'rows' => $rows];
    }
    usort($sections, fn($a, $b) => $a['rows'][0]['seconds'] <=> $b['rows'][0]['seconds']);
    return $sections;
}

/**
 * The model to pick on a configuration, quality first: same weights as in the app (70 % quality,
 * 30 % speed), speed scored against the fastest model of the same configuration so two machines
 * never share a baseline they did not run.
 */
function recommended_model(array $section, array $qualityRows): ?string
{
    $qualityByLabel = array_column($qualityRows, 'score', 'label');
    $fastest = $section['rows'][0]['seconds'] ?? null;
    if ($fastest === null || $fastest <= 0) {
        return null;
    }
    $best = null;
    $bestScore = -1.0;
    foreach ($section['rows'] as $row) {
        $quality = $qualityByLabel[$row['label']] ?? null;
        if ($quality === null || $row['seconds'] <= 0) {
            continue;
        }
        $score = 0.7 * $quality + 0.3 * 100 * min(1, $fastest / $row['seconds']);
        if ($score > $bestScore) {
            $bestScore = $score;
            $best = $row['label'];
        }
    }
    return $best;
}

/** Per-chip transcription capability: median realtime factor of the best run. */
function transcription_rows(array $reports): array
{
    $byChip = [];
    foreach ($reports as $report) {
        // Same fairness bar as the model speeds: a throttled machine transcribes slower too.
        if (!is_fair_speed_sample($report)) {
            continue;
        }
        $runs = $report['transcription']['runSeconds'] ?? [];
        $audio = $report['corpus']['audioSeconds'] ?? 0;
        if ($runs === [] || $audio <= 0) {
            continue;
        }
        $best = min($runs);
        if ($best > 0) {
            $byChip[$report['machine']['gpuName']][] = $audio / $best;
        }
    }
    $rows = [];
    foreach ($byChip as $chip => $factors) {
        $rows[] = ['chip' => $chip, 'factor' => median($factors), 'n' => count($factors)];
    }
    usort($rows, fn($a, $b) => $b['factor'] <=> $a['factor']);
    return $rows;
}

/** ISO timestamp of the most recent report, for the trust footer. */
function latest_measured_at(array $reports): ?string
{
    $dates = array_column($reports, 'measuredAt');
    return $dates === [] ? null : max($dates);
}
