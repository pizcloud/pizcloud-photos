# Grid Runtime Optimization Playbook

## Table of Contents

1. Baseline-First Loop
2. Scenario Profiles
3. Tuning Order
4. Symptom-to-Action
5. Safe Experiment Patterns
6. Validation Checklist
7. Stop Conditions

## 1. Baseline-First Loop

1. Pick one scenario and one target metric.
2. Record baseline values before edits.
3. Apply one tuning change only.
4. Re-measure with same scenario.
5. Keep or revert based on measurable impact.

## 2. Scenario Profiles

### Profile A: Cold Open and First Scroll

- Target:
- lower first visible-fill delay.
- avoid immediate frame drops.
- Typical levers:
- cache budget.
- prefetch window and concurrency.

### Profile B: Fast Scrollbar Drag

- Target:
- maintain smooth drag path.
- recover quickly with real thumbnails after release.
- Typical levers:
- lightweight mode settings.
- fast-scroll thumb edge.
- throttled prefetch resume timing.

### Profile C: Zoom Transition Scroll

- Target:
- stable FPS while switching column density.
- no repeated clamp/jump loops.
- Typical levers:
- clamp path cost.
- column transition thresholds.

## 3. Tuning Order

1. Enable reuse path and ensure it is stable.
2. Tune memory cache budgets.
3. Tune prefetch window and queue throughput.
4. Tune fast-scroll degradation/recovery.
5. Tune zoom/scroll coupling only if still needed.

## 4. Symptom-to-Action

### Symptom: FPS drops with many tiny jumps

- Check:
- cell rebuild churn (`sameVisual`, notifier updates).
- transform clamp loops in `GridState`.
- Actions:
- reduce unnecessary `CellData` invalidation.
- avoid extra `setState`/notifier updates per tick.

### Symptom: Visible cells stay blank after moving viewport

- Check:
- queue backlog and inflight saturation.
- prefetch rows too wide for current bandwidth.
- Actions:
- reduce prefetch rows.
- tune download concurrency.
- keep nearest-first priority behavior.

### Symptom: Memory spikes and frequent GC/stutter

- Check:
- `LruBytesCache.totalBytes`.
- `size50` bucket pressure versus default bucket.
- Actions:
- reduce overall or size50 budget.
- verify evictions do not thrash visible cells.

### Symptom: Fast drag is smooth but post-drag recovery is slow

- Check:
- whether resume prefetch is delayed too much by throttle.
- whether queue compaction removes useful pending items.
- Actions:
- lower prefetch throttle interval carefully.
- tune compact factor with observed pending growth.

### Symptom: Higher quality too expensive during drag

- Check:
- `_fastScrollThumbEdge` decode impact.
- Actions:
- lower fast-scroll edge.
- preserve normal edge quality once drag ends.

## 5. Safe Experiment Patterns

- Parameter sweep:
- change one numeric constant at a time in small increments.
- Keep an experiment note:
- value changed.
- scenario.
- metric delta.
- Revert-first policy:
- if functional behavior regresses, revert immediately and isolate.

## 6. Validation Checklist

Run:

```bash
flutter analyze lib/grid lib/viewer
flutter test test/grid
```

Manual:

1. Cold open with mixed media and immediate scroll.
2. Fast scrollbar drag from top to deep range and release.
3. Zoom in/out while continuously scrolling.
4. Reopen viewer from current grid position and return.
5. Repeat each scenario twice to detect warm-cache bias.

## 7. Stop Conditions

Stop tuning and hand off when:

- target metric reaches acceptable threshold with no regressions.
- additional changes produce noise-level improvement only.
- changes begin trading correctness for minor performance gains.
