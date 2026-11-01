# Field zone acceptance — 2026-10-28

Implementation: Claude. Requirements, review and tests: Codex.

## Agreed behaviour

- Z1: Native farming cells connected by shared edge form one zone. Ground gaps and diagonal contact separate zones. Existing robot work radius bounds work.
- Z2: One floating clickable badge per zone, expandable chest-style crop PLAN slots; real resources remain in robot/warehouse. Camera follows, offscreen hides, no permanent fullscreen obstruction.
- Z3: Per-tile hole density; default ratio fills entire zone. Four tiles at eight holes => nominal 32, equal two-crop weights =>16 each. Exact mode sets whole-zone totals. Native spacing limitations remain visible.
- Z4: Stable zone identity, crop assignment and progress through scans, stock changes, harvest/replant and robot replacement. Separate zone edits remain separate. Healthy crops retained.
- Z5: Scoped stage barriers and edit/pause. Other zones keep working. Critical water, P2 supply, real item conservation retained.
- Z6: World persistence; safe defaults/migration. Border growth preserves settings; ambiguous merge/split retains data and asks in-game review rather than silently overwriting.
- Z7: Read polling is bounded and lock-free; per-zone edits have proximity/revision/ownership validation, exclusive lease, disconnect/timeout release. Reject malformed payloads.

## Independent scenarios to execute

1. One tile; two separated; 2x2 contiguous; diagonal; L-shape; reversed scan order.
2. Ratio rounding for odd capacity; zero/empty plan; exact counts under/over capacity; unknown crop; generic seed.
3. Nominal vs safe capacity for connected 16-hole grids; temporary debris does not rewrite capacity/assignments.
4. Per-zone edits and density changes; stable rescans; low seeds then restock; no double stock across zones.
5. Pause/edit one zone with another runnable; concurrent robots; priority-1 water/logistics children.
6. Save/load, primary takeover/replacement; extending a border; same-plan and conflicting merges; split; out-of-range records.
7. RPC malformed/stale/foreign/remote writes; exclusive locks; readonly list; disconnect/expiry; bounded serialization.
8. Native real farmland and warehouse seed consumption across two independent zones and one connected patch.
9. Native client floating badges, correct anchors on camera move, crop slots and ratio/exact/density controls, apply/cancel/reopen, save persistence, no client Lua errors.

## Verification record

- PASS: all16 regression suites;40 Lua5.1 source files compile. New feature suites:29 geometry/reconciliation,10 zone-planner,14 registry/RPC integration,8 widget-draft/request cases.
- PASS: native world identifies one four-tile field and two separated fields, fills32 slots at16+16, honours independent exact2+2 plans, consumes36 real warehouse seeds and saves per-zone settings. See dist/native-zones-final.log.
- REPAIRED BY CLAUDE: paused-zone shared-stock starvation; simultaneous merge/split parent-record deletion; hidden legacy crops/picker pagination; stale dirty-draft revision adoption.
- PASS 2026-10-30: graphical client760944 through normal Steam launch, isolated AgriZoneUI storage, only separate UI-test mod enabled. Three floating badges follow camera;4-tile badge opens32-slot editor; ratio/exact mode, count buttons, crop picker and generic seed selection work; accepted save persists on close/reopen and actual saved-world reload. Zone pause/resume works independently. Real scene planted15 carrots+15 corn+1 generic seed in the configured zone; corrected badge reports31/31. No Lua error/stack traceback in the graphical run.
- REPAIRED BY CLAUDE DURING LIVE UI: plan progress uses complete target totals instead of capacity (including crops beyond6 abbreviated icons), neutral editing label. Two new regressions cover these.
- Startup fixture issue: cloned vanilla clients crashed at native LoadPrefabs. Normal Steam launch of the installed executable with isolated storage succeeded; no game security/authentication settings were changed. This was not claimed as a Mod crash.
- Widget stubs test draft/request logic; real rendering/click/save acceptance is recorded separately above. Full two-client multiplayer sessions and third-party-mod combinations are not certified.
