# Mini games design

Six offline, touch-friendly Flutter mini games for the app's home screen. These are recreational activities, with no medical claims or health-data dependencies. Keep scan, tracking, and health navigation working.

## Shared experience
A polished, responsive collection with six distinct colored cards, icons, descriptions, and duration/difficulty tags. Open a dedicated game route with instructions before Start, a visible score/progress display, pause/resume for timed games, end results and Play again. Large accessible targets, meaningful labels, text feedback in addition to color, animations respecting reduced motion where practical. Pause gameplay when app goes inactive; cancel timers on disposal. Session best scores may live in memory and should be labeled accordingly. Avoid new dependencies or Firebase writes.

## 1. Rainbow Match
12 face-down cards (6 food-icon pairs), shuffled at start. Reveal two; matched pairs remain face-up, mismatches hide after a short delay. Lock input during mismatch resolution. Win by finding all pairs. Score rewards fewer moves; show moves and pairs found. Replay reshuffles. No time pressure.

## 2. Garden Recall
Four large garden tiles. Demonstrate a sequence with timed highlights, then accept player repetition. Add one random tile each successful round, with slightly quicker demonstrations capped at a readable minimum. Show clearly 'Watch' versus 'Your turn'. Incorrect input ends with highest completed round and replay. Disable taps during playback; cancel playback safely on exit/pause.

## 3. Hydration Dash
45-second arcade round. Water drops and leaf obstacles descend on a bounded playfield. Drag the cup horizontally or use large left/right controls. Catch drops for points, leaf hits deduct points without going negative. Increase spawn speed gradually. Score each object once, remove missed objects, use elapsed frame delta for consistent motion, pause timer and motion together. End at zero with score and replay.

## 4. Focus Flow
An orbiting dot travels around a ring with a clearly marked target arc. Tap a large button when the dot is inside the arc. 10 attempts; success scores points, consecutive successes add a bonus. Vary target position and gently increase speed each attempt; provide explicit hit/miss feedback. Start without automatic attempts; pause motion on inactivity. Show attempts and score, then results.

## 5. Market Sort
12 randomized prompts from an unambiguous catalog of fruits, vegetables, and grains. Tap one of three labeled category baskets (drag optional, never required). Correct answer earns points and streak bonus; wrong answer reveals correct category before Next. No ambiguous examples such as tomato/corn. After 12, show accuracy, score, and replay. Educational recreational content without dietary prescriptions.

## 6. Trail Tiles
3x3 numbered sliding puzzle with eight landscape-themed tiles and one blank. Tap a tile adjacent to the blank to move. Generate board by legal random moves from solved state so it is always solvable; ensure not solved at start. Show goal preview, move count, reset/new puzzle; detect solved state and show results. Use number labels as well as visual decoration. No time pressure.

## Validation
Flutter analyze and existing tests. Add meaningful widget/logic tests for catalog navigation, match locking/completion, sequence input gating, sorting feedback/results, sliding-puzzle solvability/moves, and timed game lifecycle as feasible. Smoke all six routes at narrow/mobile and normal sizes. No changes to unrelated user edits.
