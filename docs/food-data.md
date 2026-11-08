# Food catalogue

The app's knowledge about foods lives in two shared Firestore collections,
`food` and `food_images`. They are filled offline by the scripts in `tool/`
(OpenRouter + web search + Wikipedia), and a snapshot of `food` is compiled
into the app as `lib/food/known_foods.g.dart` so scanned product names can be
matched to a catalogue entry without a network round trip.

Code: `lib/food/` (`food.dart`, `health_condition.dart`, `preference.dart`,
`nutrient.dart`, `food_repository.dart`, `food_matcher.dart`,
`known_foods.g.dart`). How the catalogue is used to decide "buy or avoid" is in
[recommendations.md](recommendations.md).

## `food/{id}` document

| Field | Type | Dart (`Food`) | Meaning |
| --- | --- | --- | --- |
| `food` | string | `name` | Display name, e.g. `Bacon`. |
| `alternatives` | map → map → string[] | `alternatives` | Substitutes by health condition, then preference (see below). |
| `health_conditions` | string[] | `healthConditions` | `HealthCondition.id`s this food clashes with. Never `none`. |
| `personal_prefs` | string[] | `personalPrefs` | `Preference.id`s this food clashes with (e.g. beef for `hinduism`). Never `none`. |
| `local_news` | string | `localNews` | Current food-safety news (outbreak, recall) for Coventry/the UK; `''` when none. `Food.hasNews` is `localNews.isNotEmpty`. |
| `general_info` | string | `generalInfo` | Why even a healthy person should avoid or limit it (e.g. processed meat); `''` when the food is fine. |
| `sources` | string[] | `sources` | Optional. URLs backing the `local_news` and `general_info` answers; empty when there is none. |
| `nutrients` | map string → number | `nutrients` | Optional. Vitamins/minerals per 100 g, keyed by `Nutrient.id`, in each nutrient's unit. |
| `updatedAt` | timestamp | (not kept) | Server timestamp set by `FoodRepository.save` and by `tool/src/food_store.dart`. |

Firestore has no set type, so the two clash sets are arrays. `firestore.rules`
requires `food`, `alternatives`, `health_conditions`, `personal_prefs`,
`local_news` and `general_info` on every write, allows only those plus
`sources`, `nutrients` and `updatedAt`, and lets any signed-in user (including
anonymous) read, write and delete (delete is for `tool/dedupe_food.dart`).

`Food.fromMap` is tolerant: unknown condition, preference and nutrient IDs are
skipped (so older clients survive new IDs), alternatives in an older non-nested
format are skipped, and `Nutrient.parseAmounts` drops non-numeric and
non-positive amounts. `Food.toMap` is the exact inverse.

### Document IDs: `Food.idFor`

```dart
static String idFor(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'[\s/]+'), '_');
```

Lower-case, trimmed, with runs of whitespace and `/` (forbidden in Firestore
IDs) collapsed to `_`. So `Bread (Toast)` → `bread_(toast)` and `  BACON ` →
`bacon`. Every lookup (`FoodRepository.get`, the assistant's `lookup_food`,
`food_images`) goes through this, so names are case/space-insensitive but not
plural-insensitive (`apple` ≠ `apples`; `dedupe_food.dart` exists for that).

### `alternatives`: condition → preference → list

```json
"alternatives": {
  "none":         {"none": ["Roast chicken"], "vegan": ["Smoked tofu", "Tempeh bacon"]},
  "hypertension": {"none": ["Grilled chicken", "Smoked tofu"], "vegan": ["Smoked tofu", "Lentils"]}
}
```

- The outer key is a `HealthCondition.id`, the inner key a `Preference.id`;
  each cell lists 1–3 substitutes suitable for someone with **both**.
- `none` means "no condition" / "no preference". `none` → `none` holds
  healthier substitutes for anyone and only exists when `general_info` is
  non-empty (enforced by `tool/fill_food.dart`, which only asks for the pairs
  `({none} ∪ health_conditions) × ({none} ∪ personal_prefs)` minus
  `none/none` when there is no general info).
- A food that clashes with nothing and has no general info has an empty map.
- `Food.alternativesFor(conditions:, prefs:, tieBreak:)` resolves a person's
  substitutes from this map; the algorithm is described in
  [recommendations.md](recommendations.md#ranking-alternatives).

### Nutrients and thresholds

`Nutrient` (`lib/food/nutrient.dart`) is shared by foods' `nutrients` and diet
days' `nutrition` maps. Element IDs follow the periodic table; vitamins are
prefixed `VIT` so vitamin K never collides with potassium `K`. Reference
amounts are UK label NRVs for adults (vitamin D at the UK's 10 µg advice).

- `richIn` (a "source of"): amount per 100 g ≥ `sourceThreshold` = 15% of
  `dailyValue` (UK labelling rule).
- `highIn`: amount per 100 g ≥ `highThreshold` = 25% of `dailyLimit`. Only
  sodium has a limit; 600 mg sodium is the UK red traffic light (1.5 g salt).

| `id` | Nutrient | Unit | Daily value | Daily limit | `richIn` at ≥ (per 100 g) | `highIn` at ≥ (per 100 g) |
| --- | --- | --- | --- | --- | --- | --- |
| `CA` | Calcium | mg | 800 | – | 120 mg | – |
| `NA` | Sodium | mg | – | 2400 | – | 600 mg |
| `FE` | Iron | mg | 14 | – | 2.1 mg | – |
| `K` | Potassium | mg | 2000 | – | 300 mg | – |
| `MG` | Magnesium | mg | 375 | – | 56.25 mg | – |
| `ZN` | Zinc | mg | 10 | – | 1.5 mg | – |
| `VITA` | Vitamin A | µg | 800 | – | 120 µg | – |
| `VITB6` | Vitamin B6 | mg | 1.4 | – | 0.21 mg | – |
| `VITB12` | Vitamin B12 | µg | 2.5 | – | 0.375 µg | – |
| `VITC` | Vitamin C | mg | 80 | – | 12 mg | – |
| `VITD` | Vitamin D | µg | 10 | – | 1.5 µg | – |
| `VITE` | Vitamin E | mg | 12 | – | 1.8 mg | – |
| `VITK` | Vitamin K | µg | 75 | – | 11.25 µg | – |
| `FOL` | Folate | µg | 200 | – | 30 µg | – |

The `unit` field holds `MG` or `UG`. Absent nutrients are unknown or
negligible. Never change an existing `id`; stored data would stop matching.

### Health conditions (`HealthCondition`)

`id` is stored in `food.health_conditions`, in `alternatives` outer keys and
in `users/{uid}.health_conditions`. `HealthCondition.conditions` is every value
except `none`.

| `id` | Label |
| --- | --- |
| `none` | None (only as an `alternatives` key) |
| `hypertension` | High blood pressure |
| `diabetes` | Diabetes |
| `high_cholesterol` | High cholesterol |
| `heart_disease` | Heart disease |
| `kidney_disease` | Kidney disease |
| `gout` | Gout |
| `coeliac_disease` | Coeliac disease |
| `lactose_intolerance` | Lactose intolerance |
| `ibs` | Irritable bowel syndrome |
| `acid_reflux` | Acid reflux |
| `peanut_allergy` | Peanut allergy |
| `tree_nut_allergy` | Tree nut allergy |
| `milk_allergy` | Milk allergy |
| `egg_allergy` | Egg allergy |
| `fish_allergy` | Fish allergy |
| `shellfish_allergy` | Shellfish allergy |
| `soy_allergy` | Soy allergy |
| `wheat_allergy` | Wheat allergy |
| `sesame_allergy` | Sesame allergy |
| `pregnancy` | Pregnancy |

### Preferences (`Preference`)

`id` is stored on foods (`personal_prefs`, `alternatives` inner keys). The
settings page saves the **label** in `users/{uid}.religion` / `.dietary`, and
`Preference.fromLabel` maps it back. Beliefs without food rules
(`Preference.otherBeliefs`: Christianity, Atheist, Agnostic) are offered on the
settings page but are not preferences, so foods are never checked against them.

| `id` | Label | Kind |
| --- | --- | --- |
| `none` | None | none (only as an `alternatives` key) |
| `islam` | Islam | religion |
| `judaism` | Judaism | religion |
| `hinduism` | Hinduism | religion |
| `buddhism` | Buddhism | religion |
| `sikhism` | Sikhism | religion |
| `gluten_free` | Gluten free | dietary |
| `vegetarian` | Vegetarian | dietary |
| `vegan` | Vegan | dietary |
| `pescatarian` | Pescatarian | dietary |
| `halal` | Halal | dietary |
| `kosher` | Kosher | dietary |
| `dairy_free` | Dairy free | dietary |
| `nut_allergy` | Nut allergy | dietary |

Adding a value to either enum adds it to the settings page and to
`tool/fill_food.dart`'s prompts automatically; existing foods only pick it up
when regenerated with `--full`.

## `food_images/{id}`

`id` is `Food.idFor(name)` for a food **or** an alternative name.

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | The name looked up. |
| `url` | string | English-Wikipedia lead image (400 px thumbnail); `''` when none was found. |
| `page` | string | Wikipedia article URL, for attribution; `''` when none. |
| `updatedAt` | timestamp | Set by the writing tool. |

Read by `FoodRepository.imageUrl(name)` (cached per process, `null` for empty
URLs) and by the assistant's `show_food_images` tool, which additionally
requires an `https` URL and that `Food.idFor(name)` equals the document ID.
Rules allow only these four keys.

## `FoodRepository`

`lib/food/food_repository.dart` wraps the `food` collection: `get(name)`,
`watch(name)`, `imageUrl(name)`, `save(food)` (full replace + `updatedAt`),
`addHealthConditions`, `setLocalNews`, `withCondition(c)` and
`withPreference(p)` (`arrayContains` queries). In the app only `get` is used
today (as the default fetcher of `FoodRecommendationService` and
`FoodNewsService`); the write and query helpers have no callers in `lib/`.

## Matching scanned names: `known_foods.g.dart` + `food_matcher.dart`

Scanned product names ("Tesco Granny Smith Apples 6 Pack") rarely equal a
catalogue name ("Apples"). `lib/food/known_foods.g.dart` is generated by
`tool/generate_food.dart` and declares `enum KnownFood` with one value per
stored food (currently 11: apples, bacon, breadToast, cabbage, cereal,
chocolate, eggs, frozenVeg, redBull, robinsonsFruitShoot,
sweetAndSaltyPopcorn), each holding a full `Food` constant.
`KnownFood.fromId` / `fromName` look values up by `Food.idFor`. Its
`localNews` is a snapshot from generation time; the app re-reads Firestore for
live data.

`matchKnownFood(scannedName)` in `lib/food/food_matcher.dart`:

1. Tokenises both names: lower-case, split on non-alphanumerics, drop stop
   words (`and`, `the`, `of`, `with`, `in`, `a`), crude singularisation
   (`-ies` → `-y`, trailing `s` dropped unless `ss`).
2. Ignores bracketed text in the known name (`Bread (Toast)` → `bread`).
3. A known word is hit if a scanned token equals it, or starts with it when
   the word is ≥ 3 chars (`veg` matches `vegetables`). Runs of known words
   written as one token also hit (`redbull`, `fruitshoot`, `frozenveg`).
4. The known name's **last word** (its head noun) must be hit, and at least
   half its words.
5. The candidate with the most hits wins, ties going to the higher share, so
   "Fruit Shoot Apple & Blackcurrant" is Robinsons Fruit Shoot, not Apples.

It is used only by `_newsFoodName` in `lib/scan/analysis_result_sheet.dart`,
which tries the product name then the display name and falls back to the raw
name; the result is what the news and recommendation cards look up.
Tests: `test/food/food_matcher_test.dart`.

## Filling the catalogue (`tool/`)

The food scripts are plain Dart (run with `dart run`, not `flutter run`) and
talk to Firestore over REST through `tool/src/food_store.dart`, which signs in
**anonymously** with the project's web API key (project `whack-2026-c7898`).
Anonymous sign-in must be enabled and `firestore.rules` deployed.

Keys needed:

| Script | Firestore | OpenRouter (`openRouterApiKey` in `lib/secrets.dart`) | Other |
| --- | --- | --- | --- |
| `fill_food_db.dart` | read/write | yes | Wikipedia (no key) |
| `fill_food.dart` | read/write | yes (web search) | – |
| `dedupe_food.dart` | read/write/delete | yes | – |
| `fill_food_images.dart` | read/write | yes | Wikipedia (no key) |
| `generate_food.dart` | read | no | – |
| `inspect_food_images.dart` | read | no | optional `FIREBASE_ID_TOKEN` |
| `tesco_food_dump.dart` | no | no | Tesco web endpoints, postcodes.io |
| `fetch_tesco_stores.py` | no | no | `curl` on `PATH` |

Create `lib/secrets.dart` from `lib/secrets.example.dart` first;
`OpenRouterService` defaults to `openRouterApiKey` and the
`@preset/glm-flash` model.

### Input: `food.txt`

`food.txt` at the repo root is the list the pipeline is run on: one food per
line, blank lines and `#` comments skipped, duplicates (by `Food.idFor`)
collapsed. It currently lists the 11 foods in `known_foods.g.dart`.

### Whole pipeline: `fill_food_db.dart`

```sh
dart run tool/fill_food_db.dart food.txt            # update Firestore
dart run tool/fill_food_db.dart food.txt --dry-run  # print only
dart run tool/fill_food_db.dart food.txt --full     # regenerate all fields
```

Runs the four steps below in order. Failures in step 1 are reported (exit code
1 at the end) but do not stop later steps. `--dry-run` is passed to steps 2–3
and skips step 4.

### 1. `fill_food.dart`

```sh
dart run tool/fill_food.dart food.txt [--dry-run] [--full]
```

- **New foods** (or all with `--full`): one OpenRouter call **with web
  search** returns `health_conditions`, `personal_prefs`, `general_info` and
  `local_news` (food-safety news for "Coventry and the UK" from the last 30
  days), plus `sources` (the URLs of the consulted search results); a second
  call fills `alternatives` for every condition/preference pair (see above),
  dropping substitutes equal to the food itself and pairs that were not asked
  for; a third fills `nutrients` per 100 g from standard composition tables
  (USDA FoodData Central / UK CoFID style).
- **Existing foods** (without `--full`): only `local_news` and `sources` are
  refreshed, and `nutrients` are filled if the stored food has none.
- Five foods are processed concurrently; web-search calls time out after
  10 minutes.

### 2. `dedupe_food.dart`

```sh
dart run tool/dedupe_food.dart [--dry-run]
```

Asks OpenRouter which names mean the same food (`Apple` / `Apples`, `Toast` /
`Bread (Toast)`), merges each group under the chosen name and deletes the
others in one atomic commit. Clash sets are unioned, alternatives are joined
per pair in first-seen order (dropping the merged foods themselves), the first
non-empty `general_info` is kept, distinct `local_news` is joined and `sources`
are unioned. Note: `_merge` does not carry `nutrients` over, so a merged food
is written with none until the next `fill_food.dart` run refills them.

### 3. `fill_food_images.dart`

```sh
dart run tool/fill_food_images.dart [--dry-run] [--retry]
```

For every food **and every alternative name** not yet in `food_images`,
OpenRouter picks the English-Wikipedia article that best shows it (20 names
per call), and the article's lead image is used (falling back to a Wikipedia
search for that title; SVGs/logos rejected). Names with no image are stored
with an empty `url` and skipped next time unless `--retry`. Names the model
gives no title for are left unstored so the next run retries them.

### 4. `generate_food.dart`

```sh
dart run tool/generate_food.dart
```

Regenerates `lib/food/known_foods.g.dart` from the whole `food` collection
(enum identifiers are camel-cased IDs; reserved words and enum members get a
`Food` suffix, and clashes a numeric suffix). Commit
the regenerated file so the matcher knows about new foods.

### `inspect_food_images.dart`

```sh
dart run tool/inspect_food_images.dart [limit]   # 1–10, default 4
```

Read-only dump of a few `food_images` documents with URL query strings
redacted. Uses `FIREBASE_ID_TOKEN` from the environment if set, otherwise
signs in anonymously (creating an anonymous Auth account).

### Tesco helpers (not part of the catalogue pipeline)

`lib/tesco/tesco_api.dart` is a client for Tesco's undocumented
`xapi.tesco.com` GraphQL gateway plus postcodes.io geocoding. It is not used
by the app at runtime; it backs these tools (and `test/tesco/`):

```sh
python3 tool/fetch_tesco_stores.py [out.json]   # default assets/tesco_stores.json
dart run tool/tesco_food_dump.dart "CV4 7AL" [out.json] [--details] [--large]
```

- `fetch_tesco_stores.py` snapshots Tesco's UK store locator into
  `assets/tesco_stores.json` (shells out to `curl` because Akamai rejects
  Dart/Python TLS fingerprints). `TescoStoreDirectory` reads that asset.
- `tesco_food_dump.dart` geocodes a postcode, town or `lat,lng`, picks the
  nearest store (`--large`: Superstore/Extra only), and writes every food &
  drink product to JSON (default `tesco_food.json`); `--details` adds
  ingredients/allergens/nutrition per product (one request each, slow). The
  output could seed `food.txt`, but no script does that automatically.

## Related readers

- `lib/food_news/food_news_service.dart` (`FoodNewsService`, exported by
  `lib/food_news.dart`): `getNews(name)` reads `local_news` / `general_info`
  through `FoodRepository().get` and substitutes
  `FoodNewsService.noNewsMessage` ("No negative news discovered") for empty
  fields; `hasAlerts` is true when either raw value is non-blank. Shown as the
  "Food alert" card on the scan result sheet.
- `lib/foodbase/foodbase_api.dart`: `identifyFoodProduct` posts a product
  photo to FoodBase (`foodBaseApiKey`) and returns its JSON. It identifies the
  scanned product (`lib/scan/product_identification_service.dart`); it does
  not read or write the catalogue. The identified name is then matched with
  `matchKnownFood`.
