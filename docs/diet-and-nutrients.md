# Diet tracking and nutrients

Receipts are photographed, turned into food names, stored per day under the
user, enriched with vitamins and minerals from USDA FoodData Central, and kept
for a sliding two-week window. The window, together with foods logged through
the assistant, feeds the nutrient tracker, the home-screen gaps card, and the
scan recommender. A separate nutrient garden on the home page shows three Rive
trees.

| File | Role |
| --- | --- |
| `lib/diet/receipt_scan_page.dart` | `ReceiptScanPage`: camera, Veryfi with ML Kit fallback, review, save |
| `lib/diet/veryfi_service.dart` | `VeryfiService.processReceipt()`: Veryfi v8 API call and line-item mapping |
| `lib/diet/receipt_parser.dart` | `ReceiptItem` and `parseReceiptItems()` (on-device OCR text parser) |
| `lib/diet/receipt_review_sheet.dart` | `showReceiptReview()` / `ReceiptReviewSheet`: remove items, pick purchase date |
| `lib/diet/receipt_store.dart` | `ReceiptStore`: Firestore reads/writes for `users/{uid}/diet` and `foodEntries` |
| `lib/diet/nutrition_service.dart` | `NutritionService`: USDA lookup, `nutritionCache`, unit normalisation |
| `lib/diet/diet_window_service.dart` | `DietDay`, `DietStorage`, `FirestoreDietStorage`, `DietWindowService` (14-day window + pruning) |
| `lib/diet/nutrient_insights.dart` | `nutrientTargets`, `NutrientStatus`, `NutrientCoverage`, `NutrientInsights` |
| `lib/diet/nutrient_tracker_page.dart` | `NutrientTrackerPage` and the home-screen `NutrientGapsCard` |
| `lib/diet/diet_history_page.dart` | `DietHistoryPage`: receipt days and manual food logs |
| `lib/food/nutrient.dart` | `Nutrient` enum: shorthand ids, units, reference amounts |
| `lib/garden/nutrient_garden.dart` | `NutrientGarden`: three Rive trees |
| `lib/garden/nutrient_score_service.dart` | `NutrientScoreService`: 0..1 score (currently not wired in) |

## Data flow

```mermaid
flowchart TD
    Photo[Receipt photo<br/>ReceiptScanPage, ResolutionPreset.veryHigh] --> Veryfi[VeryfiService.processReceipt<br/>POST api.veryfi.com/api/v8/partner/documents/]
    Veryfi -- items --> Review
    Veryfi -- "exception or no items" --> MLKit[ML Kit TextRecognizer latin<br/>+ parseReceiptItems]
    MLKit --> Review[ReceiptReviewSheet<br/>remove items, pick day]
    Review -- ReviewedReceipt --> Save[DietWindowService.save]
    Save --> Store[ReceiptStore.save]
    Store --> Nutr[NutritionService.totalsFor]
    Nutr --> Cache[(nutritionCache/{name})]
    Nutr -- cache miss --> USDA[USDA FDC /fdc/v1/foods/search]
    Store --> Diet[(users/{uid}/diet/{yyyy-MM-dd}<br/>date, foods, nutrition, updatedAt)]
    Save --> Prune[DietWindowService.recentDays<br/>delete days before cutoff]
    Prune --> Diet

    Assistant[Assistant propose_food_log] --> Entries[(users/{uid}/foodEntries/{entryId})]
    Entries --> Logged[ReceiptStore.loggedIntakeSince<br/>NutritionService.nutrientsFor per entry]

    Diet --> Window[DietWindowService.recentDays]
    Window --> Insights[NutrientInsights.load]
    Logged --> Insights
    Insights --> Tracker[NutrientTrackerPage]
    Insights --> GapsCard[NutrientGapsCard on home]
    Insights --> Recs[FoodRecommendationService<br/>low/high nutrients]
    Window --> History[DietHistoryPage]
    Entries --> History
    Garden[NutrientGarden progress: 0.62 hard-coded] -.not wired.- Score[NutrientScoreService]
```

## Firestore paths

| Path | Written by | Read by | Fields |
| --- | --- | --- | --- |
| `users/{uid}/diet/{yyyy-MM-dd}` | `ReceiptStore.save` (via `DietWindowService.save`); deleted by `ReceiptStore.delete` / `deleteOlderThan` | `ReceiptStore.history()` → `DietWindowService` | `date` (Timestamp, local midnight), `foods` (string array, `arrayUnion`), `nutrition` (map shorthand → double, 2 dp), `updatedAt` (server timestamp) |
| `users/{uid}/foodEntries/{entryId}` | `AssistantRepository` (`propose_food_log`), see `docs/assistant.md` | `ReceiptStore.loggedIntakeSince`, `DietHistoryPage` "Manual food logs" | `name`, `localDate` (Timestamp), `localDay` (string), `kind` (`eaten`/`purchased`), `source` (`assistant`), `createdAt`, optional `amount` |
| `nutritionCache/{lower-cased food name}` | `NutritionService.nutrientsFor` (top-level, shared by all users) | `NutritionService.nutrientsFor` | `nutrition` (map), `updatedAt` |
| `users/{uid}` | `NutrientScoreService.save` (merge) | `NutrientScoreService.load` | `nutrientScore`, `nutrientTotals`, `nutrientUpdatedAt` |

`firestore.rules` has matching rules for `users/{uid}/diet/{dayId}` (keys
limited to `date`, `foods`, `updatedAt`, `nutrition`; `foods` ≤ 500 entries),
`users/{uid}/foodEntries/{entryId}` (create only, no update), and
`nutritionCache/{foodName}` (any signed-in user may read/create/update). The
`users/{uid}` update rule only allows `religion`, `dietary`,
`health_conditions` and `updatedAt`, so the `nutrientScore*` fields would be
rejected (see Issues).

## Receipt scanning

`ReceiptScanPage(userId:)` is opened from `DietHistoryPage` ("Scan receipt"),
only on Android/iOS (`ReceiptScanPage.isSupported`). It uses the back camera
at `ResolutionPreset.veryHigh` and releases the camera on
`AppLifecycleState.inactive`, as the product scanner does.

On capture (`_capture`):

1. `takePicture()`, then `_recognise(photo)`:
   - `VeryfiService().processReceipt(bytes, 'receipt-<epoch ms>.jpg')`.
   - If Veryfi throws an `Exception` **or** returns no items, fall back to
     `_recogniseLocally`: ML Kit `TextRecognizer(script: TextRecognitionScript.latin)`
     then `parseReceiptItems(result.text)`.
2. No items → snackbar "No items found. Make sure the whole receipt fills the frame…".
3. `showReceiptReview(context, items)`; null or empty → stop.
4. `DietWindowService(widget.userId).save(reviewed.items, reviewed.day)`.
5. Pop with the number of items saved; `DietHistoryPage` shows
   "Saved N foods to your diet."

### Veryfi

`VeryfiService` posts JSON `{file_data: <base64>, file_name}` to
`https://api.veryfi.com/api/v8/partner/documents/` (overridable `apiUrl`) with
headers:

| Header | Value |
| --- | --- |
| `Client-Id` | `veryfiClientId` |
| `Authorization` | `apikey <veryfiUsername>:<veryfiApiKey>` |
| `X-Veryfi-Date` | UTC timestamp, seconds precision, `Z` suffix |
| `X-Veryfi-Signature` | hex HMAC-SHA256 of `"<timestamp>:<filename>"` keyed with `veryfiApiKey` |

Status 200 or 201 is success; anything else throws `VeryfiException` with
Veryfi's `message`/`error`. Each `line_items[]` entry becomes a `ReceiptItem`
with `name` = `description` (whitespace collapsed; empty skipped). If `price`
> 0 it is used with `qty` (rounded, default 1); otherwise if `total` > 0 it is
used as a single-quantity price; otherwise the line is dropped.

Credentials (`veryfiClientId`, `veryfiUsername`, `veryfiApiKey`) live in the
git-ignored `lib/secrets.dart`; see `lib/secrets.example.dart`.

### On-device parser (`parseReceiptItems`)

Used only for the ML Kit fallback. Line by line:

- Lines matching `_skipLine` (subtotal, total, tax, VAT, payment methods,
  discounts, loyalty, dates, URLs, "thank you", …) or only digits reset any
  pending name.
- A leading quantity (`2 X MILK`, `3 @ 1.20`, quantity 1–99) is stripped.
- A bare price line (`2.49`, `£2,49`, optional trailing tax-flag letter)
  completes the pending name from the previous line(s).
- `NAME 2 @ 1.50 [3.00]` gives unit price and quantity.
- `NAME 2.49` (also `MILK2.49`, optional trailing `2 X` quantity) gives a
  name and price on one line.
- Otherwise the line is held as a pending name (joined with the previous
  pending name up to 80 characters).
- Names are trimmed of punctuation noise; names shorter than 2 characters or
  made only of digits are discarded. Unpaired trailing names are dropped.

`ReceiptItem` has `name`, `price` (unit price), `quantity`, `lineTotal`, and
`toMap`/`fromMap`.

### Review sheet

`ReceiptReviewSheet` lists item names with a delete button each, and a date
tile "When did you get this?" (default today; `showDatePicker` from 365 days
ago to today). "Save N items" returns `ReviewedReceipt(items, day)`; "Retake
photo" returns null. Prices and quantities are shown nowhere and are not
stored.

## Storage (`ReceiptStore`)

`ReceiptStore(userId, {nutrition})` works on `users/{uid}/diet`.

- `save(items, day)`:
  1. `names = items.map((i) => i.name)`; `totals = await nutrition.totalsFor(names)`.
  2. `set` on `diet/{yyyy-MM-dd}` with merge: `date` (local midnight),
     `foods: arrayUnion(names)`, `nutrition: {}`, `updatedAt: serverTimestamp()`.
  3. If `totals` is non-empty, re-read the doc, add `totals` to its existing
     `nutrition`, round to 2 dp, and `update` `nutrition`.
- `history()`: snapshots ordered by `date` descending, `limit(90)`.
- `deleteOlderThan(cutoff)`: batch-deletes days with `date < cutoff` (not
  called by any code; the window service prunes via `delete` instead).
- `delete(dayId)`: deletes one day.
- `loggedIntakeSince(start)`: queries `users/{uid}/foodEntries` where
  `localDate >= start`, looks up each entry's `name` with
  `nutrition.nutrientsFor(name)` (one 100 g USDA serving per entry, regardless
  of `amount` or `kind`), and sums per local day. Failed lookups are skipped.

## Nutrient lookup (`NutritionService`)

- `nutrientsFor(food)`: key = `food.trim().toLowerCase()`. Reads
  `nutritionCache/{key}`; if it exists, returns its `nutrition` (filtered to
  known shorthands). Otherwise calls USDA and writes the result (even an empty
  map) to the cache. Cache read/write errors are ignored.
- USDA request: `GET https://api.nal.usda.gov/fdc/v1/foods/search` with
  `api_key=<usdaApiKey>`, `query=<food>`, `dataType=Foundation,SR Legacy`,
  `pageSize=1`; 15 s timeout. The first hit's `foodNutrients` are used, so
  values are per 100 g of that USDA food.
- `totalsFor(foods)`: sums `nutrientsFor` over the list, skipping foods whose
  lookup throws an `Exception`.
- `nutrientsFromUsda(entries)` maps USDA names to shorthands (entries with
  value ≤ 0 or names containing `added` are ignored):

| USDA nutrient name prefix | Shorthand | Stored unit |
| --- | --- | --- |
| `Calcium` | `CA` | MG |
| `Sodium` | `NA` | MG |
| `Iron` | `FE` | MG |
| `Potassium` | `K` | MG |
| `Magnesium` | `MG` | MG |
| `Zinc` | `ZN` | MG |
| `Vitamin A, RAE` (other Vitamin A ignored) | `VITA` | UG |
| `Vitamin B-6` | `VITB6` | MG |
| `Vitamin B-12` | `VITB12` | UG |
| `Vitamin C` | `VITC` | MG |
| `Vitamin D (D2 + D3)` in UG only | `VITD` | UG |
| `Vitamin E (alpha-tocopherol)` | `VITE` | MG |
| `Vitamin K (phylloquinone)` | `VITK` | UG |
| `Folate, DFE`, else `Folate, food` | `FOL` | UG |

Units come from `nutrientUnits`, built from `Nutrient.values`
(`lib/food/nutrient.dart`). Conversions: MG↔UG by 1000; IU → UG × 0.3
(retinol), IU → MG × 0.67 (alpha-tocopherol).

## The 14-day window (`DietWindowService`)

`DietWindowService(userId, {storage, now})` is the single read path for recent
receipt days. `storage` defaults to `FirestoreDietStorage(userId)`, which
wraps `ReceiptStore` (`loadAll` = first snapshot of `history()`,
`deleteDays` = `delete` per id).

- `window = Duration(days: 14)`.
- `cutoff()` = local midnight 14 calendar days before today
  (`DateTime(n.year, n.month, n.day - 14)`), computed by calendar days to
  avoid DST drift. Days with `date` on or after the cutoff are kept, so the
  window holds today plus the 14 previous days (15 calendar dates). Example
  from the test: now = 2026-11-07 15:30 → cutoff 2026-10-24.
- `recentDays()`: loads all days, deletes those before the cutoff from
  storage, refreshes the in-memory mirror `_local`, and returns the kept
  days newest first. **Retention is enforced here**: any read or save
  deletes expired days.
- `recentDaysStream()`: yields `recentDays()` immediately, then again when
  `_version` changes (`save`/`deleteDay` on the same instance) or after an
  hour, polling every 5 s.
- `recentFoods()`: all food names in the mirror, newest day first,
  duplicates kept.
- `recentNutritionTotals()`: nutrient totals summed across the mirror.
- `save(items, day)`: `storage.save`, bump `_version`, then `recentDays()`
  (prunes).
- `deleteDay(dayId)`: delete from storage and mirror, bump `_version`.

Callers: `ReceiptScanPage` (save), `DietHistoryPage` (stream, delete),
`NutrientInsights.load`, and `AssistantRepository` (`lib/assistant/assistant_repository.dart`, reads `recentDays()`).

## Nutrient insights

### Targets (`nutrientTargets`)

Adult daily reference intakes (UK/EU NRVs, NHS sodium limit). These match
`Nutrient.dailyValue` / `dailyLimit` in `lib/food/nutrient.dart`.

| Key | Label | Daily target | Unit | Limit? | Suggested sources |
| --- | --- | --- | --- | --- | --- |
| `CA` | Calcium | 800 | mg | | Milk, Yoghurt, Cheese, Tofu |
| `NA` | Sodium | 2400 | mg | yes (`isLimit`) | none |
| `FE` | Iron | 14 | mg | | Spinach, Lentils, Red meat, Fortified cereal |
| `K` | Potassium | 2000 | mg | | Bananas, Potatoes, Beans, Avocado |
| `MG` | Magnesium | 375 | mg | | Almonds, Spinach, Oats, Brown rice |
| `ZN` | Zinc | 10 | mg | | Beef, Chickpeas, Pumpkin seeds, Cashews |
| `VITA` | Vitamin A | 800 | µg | | Carrots, Sweet potato, Spinach, Eggs |
| `VITB6` | Vitamin B6 | 1.4 | mg | | Chicken, Salmon, Bananas, Chickpeas |
| `VITB12` | Vitamin B12 | 2.5 | µg | | Eggs, Milk, Salmon, Fortified cereal |
| `VITC` | Vitamin C | 80 | mg | | Oranges, Peppers, Strawberries, Broccoli |
| `VITD` | Vitamin D | 10 | µg | | Oily fish, Eggs, Fortified milk, Mushrooms |
| `VITE` | Vitamin E | 12 | mg | | Sunflower seeds, Almonds, Avocado, Olive oil |
| `VITK` | Vitamin K | 75 | µg | | Kale, Spinach, Broccoli, Cabbage |
| `FOL` | Folate | 200 | µg | | Lentils, Asparagus, Spinach, Chickpeas |

### Status (`NutrientCoverage.status`)

`ratio = average / target.daily`, where `average` is the mean daily intake.

| `NutrientStatus` | Normal nutrient | Limit nutrient (sodium) | Tracker label |
| --- | --- | --- | --- |
| `lacking` | ratio < 0.35 | never | "Lacking" (bad colour) |
| `low` | 0.35 ≤ ratio < 0.7 | never | "Low" (warn colour) |
| `good` | ratio ≥ 0.7 | ratio ≤ 1 | "Good" (good colour) |
| `high` | never | ratio > 1 | "Too high" (bad colour) |

`NutrientInsights.gaps` = coverage with status `lacking` or `low`.

### Loading and averaging

`NutrientInsights.load(userId, {days})` (default
`DietWindowService.window.inDays` = 14):

1. `start` = today − (days − 1), local midnight.
2. In parallel: `DietWindowService(userId).recentDays()` and
   `ReceiptStore(userId).loggedIntakeSince(start)`.
3. Adds each receipt day's `nutrition` on or after `start` into the logged
   intake map.
4. `NutrientInsights.fromDaily(intake, today: now, days: days)`.

`fromDaily` builds the list of `days` dates ending today, sums intake per
date, and divides each nutrient's total by the number of days **since the
first tracked day** in the window (inclusive), not by `days`, so new users are
not penalised for days before they started. `trackedDays` counts dates with
any data; `isEmpty` is `trackedDays == 0`. Coverage is sorted ascending by
`ratio`, and sodium by `1 − clamp(ratio − 1, 0, 10)`, so sodium only moves up
the list when it is over the limit. `fromDaily`'s own default is `days = 30`,
but every caller passes a value ≤ 14.

Every food counts as one USDA 100 g serving; the tracker states this in its
footnote.

### Consumers

- `NutrientTrackerPage`: range selector 3 / 7 / 14 days, a gaps summary (top
  4 gaps with "Try: <sources>", plus a sodium warning when `high`), and a
  row per nutrient with average, percentage of target, status label, daily
  bars, and good sources. Pull-to-refresh reloads.
- `NutrientGapsCard` (home page): 14-day insights, up to 5 gap chips
  "<label> <pct>%"; reloads after returning from the tracker.
- `FoodRecommendationService.parseProfile` maps `lacking`/`low` to
  `lowNutrients` and `high` to `highNutrients` (see `docs/recommendations.md`).

## Diet history page

`DietHistoryPage(userId:)`:

- "Scan receipt" opens `ReceiptScanPage`; "Nutrient tracker" opens the tracker.
- A `StreamBuilder` over `DietWindowService(userId).recentDaysStream()` shows
  one `_DayCard` per day: food chips and a `_NutrientBox` per stored
  nutrient, and "Delete day" (with confirmation) → `deleteDay`.
- "Manual food logs": a live query on `users/{uid}/foodEntries` ordered by
  `localDate` descending, `limit(100)`, showing name, Eaten/Purchased, and
  amount, with per-entry delete. The page text says these "stay separate from
  receipt totals"; they are not shown in the day cards, but they are combined
  with receipt days in `NutrientInsights`.

## Nutrient garden

### `NutrientGarden`

`NutrientGarden(progress:)` loads `assets/rive/tree_demo.riv` (declared in
`pubspec.yaml`, package `rive: ^0.14.11`) and draws three trees in a 180 px
row with scales 0.55 (left), 1.0 (centre), 0.75 (right). Each tree builds a
`RiveWidgetController` with `StateMachineNamed('State Machine 1')` and sets
the state machine's first `NumberInput` to
`progress.clamp(0, 1) * 80 * scale`, so a perfect score reaches 80 % of the
input's 0–100 range on the centre tree.

The home page currently passes a constant:

```dart
// TODO: feed from NutrientScoreService once diet history is wired;
// 0.62 stands in for a decent-but-not-perfect diet.
const NutrientGarden(progress: 0.62),
```

### `NutrientScoreService`

Not called from anywhere in `lib/`.

- `scoreFromTotals(totals)`: 0 for empty totals; otherwise the mean over all
  14 keys in its private `_dailyTargets` of `clamp(value / target, 0, 1)`
  (missing or non-positive nutrients count as 0), clamped to 0..1.
- `refreshFromFoods(userId, foods)`: `NutritionService.totalsFor(foods)` →
  score → `save`.
- `save` merges `nutrientScore`, `nutrientTotals`, `nutrientUpdatedAt` into
  `users/{uid}`; `load` reads `nutrientScore`.

Its `_dailyTargets` differ from `nutrientTargets`:

| Key | Garden target | Insights target |
| --- | --- | --- |
| CA | 700 | 800 |
| NA | 1600 (scored as a goal) | 2400 (limit) |
| FE | 8.7 | 14 |
| K | 3500 | 2000 |
| MG | 300 | 375 |
| ZN | 9.5 | 10 |
| VITA | 700 | 800 |
| VITB6 | 1.4 | 1.4 |
| VITB12 | 1.5 | 2.5 |
| VITC | 40 | 80 |
| VITD | 10 | 10 |
| VITE | 4 | 12 |
| VITK | 1 | 75 |
| FOL | 200 | 200 |

The score is also computed on raw totals, not on per-day averages.

## Testing

| Test | Covers |
| --- | --- |
| `test/diet/diet_window_service_test.dart` | cutoff exactly two weeks back at midnight; in-window days newest first; stale days deleted and excluded; `recentFoods` keeps duplicates; `recentNutritionTotals` sums only in-window days; `save` writes through and prunes; `deleteDay` removes from storage and mirror (fake `DietStorage`, injected `now`) |
| `test/diet/nutrient_insights_test.dart` | averaging over days since tracking began and gap ranking; records outside the window ignored |
| `test/diet/nutrition_service_test.dart` | USDA name → shorthand and units; folate DFE preference and fallback; MG → UG; IU vitamin D entries |
| `test/diet/receipt_parser_test.dart` | price-only lines, single-line name+price, skip lines, skip keywords mid-name, quantity prefix, comma decimals/currency, unpaired names, `toMap`/`fromMap`, tax flag, glued price, qty-at-unit-price |
| `test/diet/veryfi_service_test.dart` | line-item mapping, total-only items, signed headers and base64 body, `VeryfiException` on non-200 (uses `MockClient`) |

Not covered: `ReceiptStore` (Firestore), `NutritionService.nutrientsFor`
caching / USDA HTTP, `NutrientInsights.load`, the UI pages, and
`NutrientScoreService`.

```sh
flutter test test/diet
```

## Known issues

1. **Same-day receipts likely lose earlier nutrition.** `ReceiptStore.save`
   writes `'nutrition': <String, double>{}` with `SetOptions(merge: true)`.
   Firestore treats an empty map in a merge as a field to set, which replaces
   the existing `nutrition` map; the following read-modify-write then only
   has the new receipt's totals. The day's nutrition would reflect only the
   last receipt saved.
2. **Back-dated receipts older than the window are deleted immediately.**
   The review sheet allows dates up to 365 days ago, but
   `DietWindowService.save` prunes right after saving, so a day before the
   cutoff is written and then deleted while the user is told "Saved N foods".
3. **History page may not refresh after a scan.** `ReceiptScanPage` saves
   through its own `DietWindowService` instance, so the history page's
   stream (a different instance) only sees the new day when it is rebuilt or
   after its hourly refresh. `DietHistoryPage` is a `StatelessWidget` that
   creates a new `DietWindowService` and stream in every `build`.
4. **`nutrientScore` writes are blocked by the rules.** The `users/{uid}`
   update rule in `firestore.rules` only allows `religion`, `dietary`,
   `health_conditions`, `updatedAt`. `NutrientScoreService.save` is unused
   today, but would fail once wired. The same rule also blocks the scan
   sheet's `ignored_swap_items` write (see `docs/scanning.md`).
5. **Garden is not wired and uses different targets** (see table above); the
   progress is hard-coded to 0.62.
6. **`_Tree.build` creates a new `RiveWidgetController` on every build and
   never disposes it.**
7. **Quantities are ignored for nutrition.** Each receipt line and each
   logged food counts as one 100 g serving. `foods` uses `arrayUnion`, so a
   food bought twice on the same day is listed once.
8. **Cache key is the raw lower-cased name.** `nutritionCache/{name}` is used
   as a document id; names containing `/` (for example "1/2 gal milk") are
   not valid document ids and may make the lookup throw.
9. `ReceiptStore.deleteOlderThan` is unused; `test/diet/veryfi_service_test.dart`
   has two tests with the same name ("keeps items where Veryfi only filled
   the line total").
