# Diet tracking and nutrients

Receipts are photographed, turned into food names, stored per day under the
user, enriched with vitamins and minerals from USDA FoodData Central, and kept
for a sliding two-week window. The window, together with foods logged through
the assistant, feeds the nutrient tracker, the home-screen garden, and the
scan recommender. A separate nutrient garden fills the home page with a painted
sunrise valley.

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
| `lib/diet/nutrient_tracker_page.dart` | `NutrientTrackerPage` (opened from the History tab) |
| `lib/diet/diet_history_page.dart` | `DietHistoryPage`: receipt days and manual food logs |
| `lib/food/nutrient.dart` | `Nutrient` enum: shorthand ids, units, reference amounts |
| `lib/garden/nutrient_garden.dart` | `NutrientGarden`: loads the score, shows the valley |
| `lib/garden/sunrise_valley.dart` | `SunriseValley`: the `CustomPainter` scene |
| `lib/garden/nutrient_score_service.dart` | `NutrientScoreService`: 0..1 score from `NutrientInsights` |

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
    Insights --> Recs[FoodRecommendationService<br/>low/high nutrients]
    Window --> History[DietHistoryPage]
    Entries --> History
    Insights --> Score[NutrientScoreService.scoreFromInsights] --> Garden[NutrientGarden on home]
```

## Firestore paths

| Path | Written by | Read by | Fields |
| --- | --- | --- | --- |
| `users/{uid}/diet/{yyyy-MM-dd}` | `ReceiptStore.save` (via `DietWindowService.save`); deleted by `ReceiptStore.delete` / `deleteOlderThan` | `ReceiptStore.history()` → `DietWindowService` | `date` (Timestamp, local midnight), `foods` (string array, `arrayUnion`), `nutrition` (map shorthand → double, `FieldValue.increment` per receipt, each increment rounded to 2 dp), `updatedAt` (server timestamp) |
| `users/{uid}/foodEntries/{entryId}` | `AssistantRepository` (`propose_food_log`), see `docs/assistant.md` | `ReceiptStore.loggedIntakeSince`, `DietHistoryPage` "Manual food logs" | `name`, `localDate` (Timestamp), `localDay` (string), `kind` (`eaten`/`purchased`), `source` (`assistant`), `createdAt`, optional `amount` |
| `nutritionCache/{lower-cased food name}` | `NutritionService.nutrientsFor` (top-level, shared by all users) | `NutritionService.nutrientsFor` | `nutrition` (map), `updatedAt` |

`firestore.rules` has matching rules for `users/{uid}/diet/{dayId}` (keys
limited to `date`, `foods`, `updatedAt`, `nutrition`; `foods` ≤ 500 entries),
`users/{uid}/foodEntries/{entryId}` (create only, no update), and
`nutritionCache/{foodName}` (any signed-in user may read/create/update). The
garden score is computed on demand and never stored.

## Receipt scanning

`ReceiptScanPage(userId:, diet:)` is opened from `DietHistoryPage` ("Scan receipt"),
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
4. `save(reviewed.items, reviewed.day)` on the `diet` passed in by
   `DietHistoryPage` (or a new `DietWindowService(widget.userId)` if none).
   A `DietDayOutOfWindowException` is shown as a snackbar and the page stays
   open; other errors are shown inline.
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
tile "When did you get this?" (default today; `showDatePicker` from
`DietWindowService.cutoffFor(now)`, the window start, to today). "Save N items" returns `ReviewedReceipt(items, day)`; "Retake
photo" returns null. Prices and quantities are shown nowhere and are not
stored.

## Storage (`ReceiptStore`)

`ReceiptStore(userId, {nutrition})` works on `users/{uid}/diet`.

- `save(items, day)`:
  1. `names = items.map((i) => i.name)`; `totals = await nutrition.totalsFor(names)`.
  2. One `set` on `diet/{yyyy-MM-dd}` with merge, built by `dayWrite`:
     `date` (local midnight), `foods: arrayUnion(names)`,
     `nutrition: {key: FieldValue.increment(total rounded to 2 dp)}`, and
     `updatedAt: serverTimestamp()`. Same-day receipts add up server-side.
     `nutrition` is left out when `totals` is empty, so an existing map is
     not replaced by `{}`.
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
- `cutoffFor(now)` (static): the same cutoff for a given time; the review
  sheet uses it as the date picker's `firstDate`.
- `save(items, day)`: throws `DietDayOutOfWindowException` (with a
  user-facing `message`) without writing if `day` is before the cutoff;
  otherwise `storage.save`, bump `_version`, then `recentDays()` (prunes).
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
- `FoodRecommendationService.parseProfile` maps `lacking`/`low` to
  `lowNutrients` and `high` to `highNutrients` (see `docs/recommendations.md`).

## Diet history page

`DietHistoryPage(userId:)`:

- "Scan receipt" opens `ReceiptScanPage`; "Nutrient tracker" opens the tracker.
- It is a `StatefulWidget` that creates one `DietWindowService` and its
  `recentDaysStream()` in its state, and passes that service to
  `ReceiptScanPage`, so a saved receipt refreshes the list straight away.
- A `StreamBuilder` over that stream shows
  one `_DayCard` per day: food chips and a `_NutrientBox` per stored
  nutrient, and "Delete day" (with confirmation) → `deleteDay`.
- "Manual food logs": a live query on `users/{uid}/foodEntries` ordered by
  `localDate` descending, `limit(100)`, showing name, Eaten/Purchased, and
  amount, with per-entry delete. The page text says these "stay separate from
  receipt totals"; they are not shown in the day cards, but they are combined
  with receipt days in `NutrientInsights`.

## Nutrient garden

### `NutrientGarden`

`NutrientGarden(userId:)` sits on the home tab (keyed by the user and by a
scan counter in `_HomePageState`, so it reloads after the scan page closes).
It loads `NutrientInsights.load(userId)` (injectable `loader`), scores it with
`NutrientScoreService.scoreFromInsights`, and animates the trees to the new
score over 800 ms with a `TweenAnimationBuilder`. It expands to fill its
parent; the home tab stacks it under the greeting and the `Scaffold`
extends the body behind the status bar and bottom bar.

| State | Shown |
| --- | --- |
| Loading | Valley at 0 |
| Error | Logged with `debugPrint`; valley stays at 0 |
| `insights.isEmpty` | Valley at 0 plus "Scan a receipt to grow your garden" above the bottom bar |
| Otherwise | Valley at the score |

`SunriseValley(progress:)` is a single `CustomPainter`: sky, sun and moon,
stars, clouds and birds, layered ridges with mist bands, a meadow, and an
S-curve river that widens toward the viewer. `progress` drives how many trees
and tufts appear, how big they grow and how saturated the greens are, from
sparse saplings at 0 to a full valley at 1. Layout positions are seeded, so
the scene is the same on every build. Tests replace it through
`treesBuilder`.

It animates from a `Ticker` that feeds a `ValueNotifier<double>` of scene
seconds straight to the painter (`CustomPainter(repaint:)`), so frames
repaint without rebuilding widgets. `ValleyClock` turns those seconds into:

| Cycle | Length | What changes |
| --- | --- | --- |
| Day/night | `dayLength` 48 s, 65 % daylight | Sun arcs left to right; sky keyed by sun height (night, twilight, golden, morning, noon); moon and twinkling stars at night; land lit through one `ColorFilter` (`BlendMode.modulate`) tint |
| Seasons | `daysPerSeason` 1 day/night cycle each | Spring blossom and petals, summer greens, autumn amber and falling leaves, winter snow, frosted trees and snowfall; each blends into the next overnight, so every sunrise opens on the next season |
| Ambient | continuous | Clouds drift and wrap; birds fly by day; trees, crest conifers and grass sway in gusting wind; light streaks flow down the river under the reflected sun or moon |

The scene opens just after sunrise in today's season (`ValleySeason.of`,
northern hemisphere), or `startSeason`. `animate: false`, or the platform's
reduced-motion setting (`MediaQuery.disableAnimationsOf`), freezes it.

### `NutrientScoreService`

Scores come from the same `nutrientTargets` as the tracker, so the garden and
the tracker never disagree.

- `scoreFromInsights(insights)`: 0 when `insights.isEmpty`; otherwise the mean
  over every nutrient in `insights.coverage`, clamped to 0..1.
  - Goal nutrients score `ratio.clamp(0, 1)`, so a megadose of one nutrient
    can't hide gaps elsewhere.
  - Limit nutrients (`target.isLimit`, sodium) score `(2 - ratio).clamp(0, 1)`:
    1 at or under the limit, falling linearly to 0 at twice the limit.
- `scoreFor(userId)`: loads insights (injectable `loader`, default
  `NutrientInsights.load`) and scores them.

## Testing

| Test | Covers |
| --- | --- |
| `test/diet/diet_window_service_test.dart` | cutoff exactly two weeks back at midnight; in-window days newest first; stale days deleted and excluded; `recentFoods` keeps duplicates; `recentNutritionTotals` sums only in-window days; `save` writes through and prunes; a second same-day save keeps the earlier nutrition; `save` rejects days before the window and accepts the oldest in-window day; `cutoffFor`; `deleteDay` removes from storage and mirror (fake `DietStorage`, injected `now`) |
| `test/diet/nutrient_insights_test.dart` | averaging over days since tracking began and gap ranking; records outside the window ignored |
| `test/diet/nutrition_service_test.dart` | USDA name → shorthand and units; folate DFE preference and fallback; MG → UG; IU vitamin D entries |
| `test/diet/receipt_store_test.dart` | `ReceiptStore.dayWrite` increments each nutrient so same-day receipts add up; leaves `nutrition` out when there is nothing to add |
| `test/diet/receipt_parser_test.dart` | price-only lines, single-line name+price, skip lines, skip keywords mid-name, quantity prefix, comma decimals/currency, unpaired names, `toMap`/`fromMap`, tax flag, glued price, qty-at-unit-price |
| `test/garden/nutrient_score_service_test.dart` | empty insights score 0; all targets met score 1; half goals; sodium at, over and far over the limit; megadose clamping; `scoreFor` uses the injected loader |
| `test/garden/sunrise_valley_test.dart` | month to season; each season opens just after sunrise; noon/midnight sun height; a season holds through the day then turns overnight; winter wraps to spring; a full year of frames paints without errors; reduced motion stops the ticker |
| `test/garden/nutrient_garden_test.dart` | trees at 0 while loading; empty-diet hint; error falls back to 0; a non-empty diet grows to the expected score (fake loader and `treesBuilder`) |
| `test/diet/veryfi_service_test.dart` | line-item mapping, total-only items, multi-line descriptions from a real Veryfi response, signed headers and base64 body, `VeryfiException` on non-200 (uses `MockClient`) |

Not covered: `ReceiptStore` against Firestore (only `dayWrite` is tested),
`NutritionService.nutrientsFor` caching / USDA HTTP, `NutrientInsights.load`, and the UI pages.

```sh
flutter test test/diet test/garden
```

## Known issues

1. **Quantities are ignored for nutrition.** Each receipt line and each
   logged food counts as one 100 g serving. `foods` uses `arrayUnion`, so a
   food bought twice on the same day is listed once.
2. **Cache key is the raw lower-cased name.** `nutritionCache/{name}` is used
   as a document id; names containing `/` (for example "1/2 gal milk") are
   not valid document ids and may make the lookup throw.
3. `ReceiptStore.deleteOlderThan` is unused.
