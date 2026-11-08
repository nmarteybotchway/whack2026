# Pantry news

A demo pantry tracker: 30 seconds after app startup, the app "discovers"
breaking news about a food the user already has at home and delivers it as
if a tracker service had found it in real time — an OS notification plus a
cancellable banner over the Home tab. The History tab gains a "Flagged
items" section between the AI diet review and the receipt purchases list.

## How it works

- `lib/pantry_news/demo_news.dart` holds the demo data as a hardcoded map
  (`demoPantryNews`), plus the kill switch (`pantryNewsEnabled`) and the
  delay (`pantryNewsDelay`). No database is involved.
- `lib/pantry_news/pantry_news_controller.dart` fires the map's first entry
  on a `Timer` started from `HomePage`'s post-frame callback, runs the food
  through `FoodRecommendationService.recommend` (the same pure recommender
  the scan result sheet uses) to get the "try instead" alternatives, shows
  the OS notification, and tracks this session's flagged foods.
- `lib/pantry_news/pantry_news_card.dart` is the red banner over the Home
  tab (styled after the scan sheet's `_FoodNewsAlert`), with a sources
  dialog and a dismiss button that cancels pending and future deliveries.
- `lib/pantry_news/flagged_items_card.dart` lists the session's flagged
  foods on the History tab; it is in-session only and repopulates 30 s
  after each restart.
- `lib/pantry_news/os_notifier.dart` wraps `flutter_local_notifications`
  (channel `pantry-news`), Android/iOS only like `ReceiptScanPage`.

All of it is **simulated demo data**, not a real recall.

## Android setup (already applied)

- `AndroidManifest.xml`: `android.permission.POST_NOTIFICATIONS`.
- `android/app/build.gradle.kts`: `coreLibraryDesugaringEnabled = true` and
  the `desugar_jdk_libs` dependency, as the plugin requires.

## Demo script

1. `flutter run` on an Android device/emulator, accept the notification
   permission prompt.
2. Stay on the Home tab; after 30 s the OS notification and the red
   "Breaking news: Strawberries" banner appear, naming Coventry and the
   West Midlands, with "Try instead" alternatives.
3. Tap the info button for sources, X to dismiss.
4. History tab: the flagged item is listed between the AI diet review and
   the receipt purchases.
5. Kill and relaunch to see it fire again; flip `pantryNewsEnabled` to
   `false` to disable it.

## Extending to a real receipt

The tracker is independent of receipt scanning. To flag another food, add
an entry to `demoPantryNews` in `lib/pantry_news/demo_news.dart` — no other
code changes. (The controller currently announces the map's first entry;
iterate the map's entries in `_deliver` to announce several.)
