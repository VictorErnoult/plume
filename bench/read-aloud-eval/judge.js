// bench/read-aloud-eval/judge.js
// Verdict math for the blind judge page. Plain functions, tested from Swift with JavaScriptCore.
(function (root) {
  const CRITERIA = ["mainPoint", "nothingInvented", "rightLanguage", "rightLength"];

  function lengthClass(words) {
    return words < 300 ? "short" : words <= 1500 ? "medium" : "long";
  }

  function median(values) {
    if (values.length === 0) return null;
    const sorted = [...values].sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  // results: results.json; verdicts: { [file]: { order: [idA, idB], A: {criteria}, B: {criteria}, preference: "A"|"B"|"equal", note } }
  function summarize(results, verdicts) {
    const engines = {};
    for (const engine of results.engines) {
      engines[engine.id] = { counts: {}, preferred: 0, totals: [], firsts: [] };
    }
    let ties = 0;
    for (const item of results.items) {
      const verdict = verdicts[item.file];
      if (!verdict) continue;
      const lengthKey = lengthClass(item.words);
      verdict.order.forEach((id, index) => {
        const label = index === 0 ? "A" : "B";
        const engine = engines[id];
        if (!engine) return;
        for (const key of ["all", lengthKey]) {
          engine.counts[key] = engine.counts[key] || { n: 0 };
          engine.counts[key].n += 1;
          for (const criterion of CRITERIA) {
            engine.counts[key][criterion] = (engine.counts[key][criterion] || 0) + (verdict[label][criterion] ? 1 : 0);
          }
        }
        if (verdict.preference === label) engine.preferred += 1;
        const outcome = item.results[id] || {};
        if (typeof outcome.totalSeconds === "number") engine.totals.push(outcome.totalSeconds);
        if (typeof outcome.firstSentenceSeconds === "number") engine.firstSentences = (engine.firstSentences || []).concat(outcome.firstSentenceSeconds);
      });
      if (verdict.preference === "equal") ties += 1;
    }
    const out = { engines: {}, ties };
    for (const [id, engine] of Object.entries(engines)) {
      const shares = {};
      for (const [key, count] of Object.entries(engine.counts)) {
        shares[key] = {};
        for (const criterion of CRITERIA) shares[key][criterion] = count.n ? count[criterion] / count.n : 0;
      }
      out.engines[id] = Object.assign(shares, {
        preferred: engine.preferred,
        medianTotalSeconds: median(engine.totals),
        medianFirstSentenceSeconds: median(engine.firstSentences || []),
      });
      if (!out.engines[id].all) out.engines[id].all = Object.fromEntries(CRITERIA.map((c) => [c, 0]));
    }
    return out;
  }

  // A random A/B order per file, drawn once and kept with the progress, so a reload never
  // swaps the labels of a judged selection.
  function orderFor(file, engineIds, saved) {
    if (saved[file] && saved[file].order) return saved[file].order;
    const order = Math.random() < 0.5 ? [engineIds[0], engineIds[1]] : [engineIds[1], engineIds[0]];
    return order;
  }

  root.PlumeJudge = { summarize, orderFor, lengthClass, CRITERIA };
})(globalThis);
