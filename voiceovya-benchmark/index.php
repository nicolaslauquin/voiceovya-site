<?php
// Public benchmark page: "with my Mac, which model should I use, and how many seconds does it
// cost?". Rendered on read from the archived reports — no build step, no database.

require __DIR__ . '/lib.php';

$reports = load_reports();
$quality = quality_rows($reports);
$speed = speed_sections($reports);
$transcription = transcription_rows($reports);
$latest = latest_measured_at($reports);

/** Escapes every value that reaches the page: report content is user-submitted by construction. */
function e(?string $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function seconds(float $value): string
{
    return $value < 10 ? number_format($value, 1, ',', ' ') . ' s'
        : number_format($value, 0, ',', ' ') . ' s';
}

function percent(?float $ratio): string
{
    return $ratio === null ? '—' : number_format($ratio * 100, 0, ',', ' ') . ' %';
}

/** Sample count, flagged when a median rests on too few runs to mean anything. */
function samples(int $count): string
{
    $label = $count . ' rapport' . ($count > 1 ? 's' : '');
    return $count < MIN_SAMPLES_FOR_SOLID
        ? '<span class="n weak" title="Trop peu de mesures pour une médiane fiable">' . $label . '</span>'
        : '<span class="n">' . $label . '</span>';
}
?>
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Benchmark des modèles — VoiceOvya</title>
<meta name="description" content="Combien de secondes coûte l'analyse d'une note vocale, par Mac et par modèle d'IA. Mesures réelles partagées par les utilisateurs de VoiceOvya.">
<style>
:root{
  --font:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;
  --mono:ui-monospace,"SF Mono",Menlo,monospace;
  --accent:#1f9e63;--accent-deep:#157a4b;--accent-soft:#e7f4ec;
  --bg-clear:#f4f8f6;--bg-white:#fafcfb;--bg-dark:#1d2522;
  --text-dark:#1d2522;--text-medium:#6b756f;--text-light:#b3bbb5;
  --shadow-card:0 1px 3px rgba(0,0,0,.05);
}
*{box-sizing:border-box}
body{margin:0;font-family:var(--font);color:var(--text-dark);background:var(--bg-clear);
  line-height:1.55;-webkit-font-smoothing:antialiased}
.wrap{max-width:920px;margin:0 auto;padding:56px 24px 88px}
h1{font-size:2rem;line-height:1.2;margin:0 0 12px}
h2{font-size:1.25rem;margin:48px 0 6px}
p.lead{font-size:1.05rem;color:var(--text-medium);margin:0 0 8px}
p.note{color:var(--text-medium);font-size:.9rem;margin:0 0 18px}
.card{background:var(--bg-white);border:1px solid #e4ebe7;border-radius:14px;
  box-shadow:var(--shadow-card);padding:18px 20px}
.verdicts{display:grid;gap:14px;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));margin-top:18px}
.verdict .config{font-size:.8rem;text-transform:uppercase;letter-spacing:.04em;color:var(--text-medium)}
.verdict .pick{font-family:var(--mono);font-size:1rem;color:var(--accent-deep);margin:6px 0 2px;
  word-break:break-word}
.verdict .time{color:var(--text-medium);font-size:.9rem}
table{width:100%;border-collapse:collapse;font-size:.94rem}
th,td{text-align:left;padding:9px 10px;border-bottom:1px solid #eef3f0}
th{font-size:.78rem;text-transform:uppercase;letter-spacing:.04em;color:var(--text-medium);font-weight:600}
tr:last-child td{border-bottom:none}
td.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
td.model{font-family:var(--mono);font-size:.88rem}
.scroll{overflow-x:auto}
.tag{display:inline-block;font-size:.72rem;padding:1px 7px;border-radius:99px;
  background:var(--accent-soft);color:var(--accent-deep);vertical-align:1px}
.n{color:var(--text-light);font-size:.8rem}
.n.weak{color:#c8952b;border-bottom:1px dotted currentColor;cursor:help}
.bar{height:6px;border-radius:3px;background:var(--accent);display:block;min-width:2px}
.bar.other{background:rgba(31,158,99,.45)}
footer{margin-top:56px;padding-top:20px;border-top:1px solid #e4ebe7;
  color:var(--text-medium);font-size:.86rem}
footer a{color:var(--accent-deep)}
.empty{text-align:center;color:var(--text-medium);padding:36px 20px}
</style>
</head>
<body>
<div class="wrap">

<h1>Quel modèle d'IA sur quel Mac&nbsp;?</h1>
<p class="lead">
  Toutes les mesures viennent de la même note vocale de 3&nbsp;min&nbsp;40, analysée avec le même
  prompt, sur les Mac des utilisateurs de VoiceOvya. Vous pouvez donc les comparer entre elles.
</p>

<?php if ($reports === []) : ?>
  <div class="card empty">Aucun rapport agrégé pour le moment.</div>
<?php else : ?>

  <h2>Le modèle à choisir, selon votre Mac</h2>
  <p class="note">
    Le meilleur compromis entre la justesse de l'analyse et le temps d'attente&nbsp;:
    70&nbsp;% qualité, 30&nbsp;% vitesse, la vitesse étant comparée au modèle le plus rapide
    mesuré sur ce même Mac.
  </p>
  <div class="verdicts">
    <?php foreach ($speed as $section) :
        $pick = recommended_model($section, $quality);
        if ($pick === null) {
            continue;
        }
        $row = current(array_filter($section['rows'], fn($r) => $r['label'] === $pick));
        ?>
      <div class="card verdict">
        <div class="config"><?= e($section['config']) ?></div>
        <div class="pick"><?= e($pick) ?></div>
        <div class="time"><?= seconds($row['seconds']) ?> par note · <?= samples($row['n']) ?></div>
      </div>
    <?php endforeach; ?>
  </div>

  <h2>Temps d'analyse d'une note, par Mac</h2>
  <p class="note">
    Médiane du temps d'analyse d'une note <strong>inédite</strong>, celle qu'un usage réel produit
    à chaque fois. Les mesures prises en économie d'énergie ou sur une machine en surchauffe sont
    écartées.
  </p>
  <?php foreach ($speed as $section) :
      $fastest = $section['rows'][0]['seconds']; ?>
    <div class="card" style="margin-bottom:14px">
      <h3 style="margin:0 0 8px;font-size:1rem"><?= e($section['config']) ?></h3>
      <div class="scroll"><table>
        <tr><th>Modèle</th><th style="width:34%">Temps</th><th class="num">Mesures</th></tr>
        <?php foreach ($section['rows'] as $index => $row) : ?>
          <tr>
            <td class="model"><?= e($row['label']) ?></td>
            <td class="num" style="text-align:left">
              <?= seconds($row['seconds']) ?>
              <span class="bar<?= $index === 0 ? '' : ' other' ?>"
                style="width:<?= (int) round(100 * min(1, $fastest / max($row['seconds'], 0.001))) ?>%"></span>
            </td>
            <td class="num"><?= samples($row['n']) ?></td>
          </tr>
        <?php endforeach; ?>
      </table></div>
    </div>
  <?php endforeach; ?>

  <h2>Qualité de l'analyse, par modèle</h2>
  <p class="note">
    La qualité ne dépend pas du Mac&nbsp;: même note, même prompt, notation automatique. Un seul
    classement suffit donc, tous Mac confondus. La couverture dit combien des faits attendus le
    modèle a retrouvés dans la note.
  </p>
  <div class="card scroll"><table>
    <tr><th>Modèle</th><th class="num">Score /100</th><th class="num">Couverture</th><th class="num">Mesures</th></tr>
    <?php foreach ($quality as $row) : ?>
      <tr>
        <td class="model"><?= e($row['label']) ?>
          <?php if ($row['isLocal']) : ?><span class="tag">sur votre Mac</span><?php endif; ?>
        </td>
        <td class="num"><?= number_format($row['score'], 1, ',', ' ') ?></td>
        <td class="num"><?= percent($row['coverage']) ?></td>
        <td class="num"><?= samples($row['n']) ?></td>
      </tr>
    <?php endforeach; ?>
  </table></div>

  <?php if ($transcription !== []) : ?>
    <h2>Transcription, par puce</h2>
    <p class="note">
      La transcription est faite par macOS, sur votre Mac, quel que soit le modèle d'IA choisi
      ensuite. «&nbsp;120× temps réel&nbsp;» veut dire qu'une heure d'audio est transcrite en
      trente secondes.
    </p>
    <div class="card scroll"><table>
      <tr><th>Puce</th><th class="num">Vitesse</th><th class="num">Mesures</th></tr>
      <?php foreach ($transcription as $row) : ?>
        <tr>
          <td><?= e($row['chip']) ?></td>
          <td class="num"><?= number_format($row['factor'], 0, ',', ' ') ?>× temps réel</td>
          <td class="num"><?= samples($row['n']) ?></td>
        </tr>
      <?php endforeach; ?>
    </table></div>
  <?php endif; ?>

<?php endif; ?>

<footer>
  <?= count($reports) ?> rapport<?= count($reports) > 1 ? 's' : '' ?> agrégé<?= count($reports) > 1 ? 's' : '' ?>,
  protocole v<?= MIN_PROTOCOL_VERSION ?> et plus.
  <?php if ($latest !== null) : ?>
    Dernière mesure&nbsp;: <?= e(substr($latest, 0, 10)) ?>.
  <?php endif; ?>
  <br>
  Les rapports ne contiennent aucun contenu de note&nbsp;: uniquement des durées, des compteurs et
  des identifiants techniques de matériel et de modèle.
  <a href="/">Retour à VoiceOvya</a>
</footer>

</div>
</body>
</html>
