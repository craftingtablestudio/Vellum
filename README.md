<p align="center">
  <img src="assets/vellum_logo.png" alt="vellum" width="300" />
</p>

# Vellum 📜

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmesqueeb%2FVellum%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mesqueeb/Vellum)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmesqueeb%2FVellum%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mesqueeb/Vellum)

```
.package(url: "https://github.com/mesqueeb/Vellum", from: "0.0.6")
```

Pure-Swift move ledger for board games — tracks positions, orientations, and supports undo, redo, and history branching.

## Overview

Vellum is a cross-platform pure-Swift package without platform specific library reliances. It models the move history of a board game as a typed, codable ledger that supports:

- Recording moves made up of one or more parallel/sequential groups
- Undo and redo with full state reconstruction
- Non-linear history browsing (jump to any move)
- Divergence detection and backup when a player branches off history
- Magnetic hugging — entities that travel with a parent entity

## Non-obvious design choices

### `EID` — Entity Identifier

`EID` stands for **Entity Identifier**. It has two meaningful cases, not one, because there are two fundamentally different kinds of entities in a scene:

- **`.other(name)`** — a static, unique entity. Its name alone is enough to identify it because only one instance ever exists (e.g. `"white-king"`, `"board"`). Entities with this case should ideally have an entry in `initialStateDic` so their state can be restored during undo.
- **`.clone(name, cloneId: UUID)`** — a dynamically created entity. Multiple copies of the same template can exist simultaneously (e.g. several cards dealt from a deck), so a UUID is required to tell them apart. The `name` identifies the template; the UUID identifies the specific instance.
- **`.none`** — a sentinel representing the absence of an entity.

## Examples

### Recording a move

```swift
var history = MoveHistory()
// moveNr is -1 by default, meaning "always point to the latest move"
// moveNrActual resolves -1 to the real count: 0 moves recorded so far
print(history.moveNr)              // -1
print(history.moveNrActual.value)  // 0

let move = Move([[CoreMove(eid: pawnEID, target: .position([2, 0, 0]))]])
let appendResult = try history.appendMove(move, initialStateDic: entityInitialStates, atIndex: nil, setMoveNr: true)
// appendResult == (addOrBrowseIndex: .addedAtIndex(0), newMoveNr: .lastMove, backupForDivergence: nil)
// nil when the move was a no-op (duplicate of current state)

print(history.moveNr)              // -1 (still latest)
print(history.moveNrActual.value)  // 1
```

### Recording a move with parallel and sequential groups

```swift
// A Move is a nested array: [[CoreMove, CoreMove], [CoreMove], ...]
// CoreMoves in the same inner array are intended to be applied in parallel by the caller
// Inner arrays are intended to be applied sequentially: the first group before the second
let move = Move([
  [                                                                // first group:
    CoreMove(eid: blackStoneEID, target: .position([3, 0, 2])),   //   black places a stone
  ],
  [                                                                // then sequential group:
    CoreMove(eid: whiteStone1EID, target: .magnet(bowlEID)),      //   surrounded white stones
    CoreMove(eid: whiteStone2EID, target: .magnet(bowlEID)),      //   are captured
    CoreMove(eid: whiteStone3EID, target: .magnet(bowlEID)),      //   all at once (in parallel)
  ],
])
try history.appendMove(move, initialStateDic: entityInitialStates, atIndex: nil, setMoveNr: true)
```

### Undoing a move

```swift
// Assume history has 3 moves recorded
print(history.moves.count)         // 3
print(history.moveNr)              // -1 (latest)
print(history.moveNrActual.value)  // 3

let browseResult = history.browseHistory(action: .undo, animatingTowards: nil, currentlyAnimating: nil)
// browseResult == .animateMoves([(reverseMove, fromMoveNr: 3, toMoveNr: 2)])

// moves.count is unchanged — undo only moves the cursor, not the ledger
// (cursor is updated to toMoveNr.value after animating, see "Undoing a move and animate" below)
print(history.moves.count)         // 3 (unchanged)
print(history.moveNr)              // -1 (cursor not yet updated — see below)
print(history.moveNrActual.value)  // 3 (cursor not yet updated — see below)
```

**Example undo handling via animation:**

```swift
// Your app tracks these as state — nil when idle, non-nil while an animation is running
var animatingTowards: ActualMoveNr? = nil
var currentlyAnimating: ActualMoveNr? = nil

let browseResult = history.browseHistory(
  action: .undo,
  animatingTowards: animatingTowards,   // pass current animation state, not hardcoded nil
  currentlyAnimating: currentlyAnimating
)

switch browseResult {
case .animateMoves(let movesAndNrs):
  // Set the overall destination once before the loop
  animatingTowards = movesAndNrs.last?.newMoveNr
  for (reverseMove, fromMoveNr, toMoveNr) in movesAndNrs {
    print(fromMoveNr.value, "→", toMoveNr.value)  // e.g. 3 → 2
    // Update to the current step's destination so browseHistory can detect mid-animation reversals
    currentlyAnimating = toMoveNr
    await animateEntities(reverseMove)
    history.moveNr = toMoveNr.value
  }
  animatingTowards = nil
  currentlyAnimating = nil
case .stopAnimating(let stopAt):
  // Fires when the user acts mid-animation and the new target falls between
  // currentlyAnimating and animatingTowards (i.e. they adjusted the destination mid-flight)
  // stopAt is NOT a pause at the current step — it's a new destination derived from
  // animatingTowards adjusted by the new action
  // e.g. showMove 5→0 (animatingTowards=0), currently animating step 3→2 (currentlyAnimating=2),
  //      user taps redo → new target = 0+1 = 1, which is between 2 and 0 → stopAt=1
  // Do NOT set history.moveNr here — update animatingTowards to stopAt, trim your animation
  // queue to stop at stopAt, and let the animation loop update moveNr naturally as it finishes
  animatingTowards = stopAt
  currentlyAnimating = nil
}

print(history.moves.count)         // 3 (unchanged)
print(history.moveNr)              // 2
print(history.moveNrActual.value)  // 2
```

### Jumping to a specific move

```swift
// Assume history has 5 moves, currently at the latest
print(history.moveNr)              // -1 (latest)
print(history.moveNrActual.value)  // 5

let browseResult = history.browseHistory(
  action: .showMove(moveNr: .specific(2)),
  animatingTowards: nil,
  currentlyAnimating: nil
)
// Returns .animateMoves with all 3 intermediate steps to apply (5→4, 4→3, 3→2)
// browseHistory doesn't move the cursor — you do that manually as each animation completes
print(history.moveNrActual.value)  // 5
```

### Branching history (player makes a new move after undoing)

```swift
// Player undid back to move 2 out of 5, then makes a different move
print(history.moves.count)         // 5
print(history.moveNr)              // 2
print(history.moveNrActual.value)  // 2

let appendResult = try history.appendMove(newMove, initialStateDic: entityInitialStates, atIndex: nil, setMoveNr: true)

// The 3 future moves were trimmed and replaced by the new one
print(history.moves.count)         // 3
print(history.moveNr)              // -1 (latest)
print(history.moveNrActual.value)  // 3

if let backup = appendResult?.backupForDivergence {
  // Non-nil when more than one future move was discarded — save it so the player can restore later
  gameState.historyBackup = backup
}
```

### Restoring the original history (going back to the main game)

```swift
let backup = gameState.historyBackup
guard backup.hasBackup else { return }

print(history.moves.count)         // 3 (alternate branch)
print(history.moveNr)              // -1 (latest)
print(history.moveNrActual.value)  // 3

// 1. Animate back to the divergence point
let browseResult = history.browseHistory(
  action: .showMove(moveNr: .specific(UInt(backup.divergenceMoveNr))),
  animatingTowards: nil,
  currentlyAnimating: nil
)
// ... handle browseResult the same way as in the undo example above ...

// 2. Restore the original moves and clear the backup
history.moves = history.moves.slice(0, backup.divergenceMoveNr) + backup.moves
gameState.historyBackup = HistoryBackup()

print(history.moves.count)         // 5 (original history restored)
print(history.moveNr)              // -1 (latest)
print(history.moveNrActual.value)  // 5
```

## Versioned Types

Types are namespaced by version (`v0`, `v1`, …) so breaking Codable changes never invalidate older saved data. Migration code can reference two versions simultaneously without any SPM version conflict.

Vellum does not define top-level type aliases — that's up to the consumer. Define your own aliases to keep call sites clean:

```swift
import Vellum

public typealias EID = v0.EID
public typealias EIDCustomDecodingError = v0.EIDCustomDecodingError
public typealias SoundGroup = v0.SoundGroup
public typealias PhysicsBodyMode = v0.PhysicsBodyMode
public typealias MagneticHugsComponent = v0.MagneticHugsComponent
public typealias ModelMetaComponent = v0.ModelMetaComponent
public typealias EntityState = v0.EntityState
public typealias CoreMoveTarget = v0.CoreMoveTarget
public typealias CoreMove = v0.CoreMove
public typealias Move = v0.Move
public typealias HistoryBackup = v0.HistoryBackup
public typealias MoveHistory = v0.MoveHistory
```

Then use the short names everywhere in your app:

```swift
var history = MoveHistory()
let move = Move([[CoreMove(eid: myEID, target: .position([1, 0, 0]))]])
try history.appendMove(move, initialStateDic: [:], atIndex: nil, setMoveNr: true)
```

For migrations, reference the version namespace directly:

```swift
let old = try decoder.decode(Vellum.v0.CoreMove.self, from: data)
```

## Test Coverage

```bash
./coverage.sh
```

Runs the test suite with coverage enabled and prints a per-file coverage table to the terminal.

## Documentation

See the [documentation](https://swiftpackageindex.com/craftingtablestudio/Vellum/main/documentation/Vellum/Vellum) for more info.
