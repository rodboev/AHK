# MButton Drag Scroll: Context Transfer Summary

## Current State (January 2025)

### Method Assignments
| App/Region | Method | Target | Timer | Status |
|------------|--------|--------|-------|--------|
| mmc.exe | UIA | Control | 10ms | Working |
| Explorer file lists | UIA | Control | 10ms | Working |
| Explorer nav bar (SysTreeView32) | VSCROLL | Control | 50ms | Working |
| SystemInformer | WHEEL_CTRL | Control | 10ms | Working |
| VS Code | WHEEL | Window | 10ms | Working |

### Scroll Methods Explained
| Method | Mechanism | Granularity | Best For |
|--------|-----------|-------------|----------|
| **UIA** | SetScrollPercent via IUIAutomationScrollPattern | Fractional % | Apps exposing ScrollPattern (Explorer lists, mmc) |
| **WHEEL** | WM_MOUSEWHEEL with sub-120 delta to window | Sub-notch | Apps with internal cursor routing (VS Code, Electron) |
| **WHEEL_CTRL** | WM_MOUSEWHEEL to control (with fallback detection) | 1 line* | Controls that scroll 1 line per message (SI) |
| **VSCROLL** | WM_VSCROLL 1 line per tick, dynamic timer | 1 line | Universal fallback (tree views, controls that scroll 3 lines per wheel) |

*Note: WHEEL_CTRL does NOT actually do sub-120 accumulation. SI just happens to scroll 1 line per wheel message instead of the typical 3 lines. The fallback detection identifies controls that scroll >1 line per message and switches to VSCROLL.

---

## Architecture Overview

### File Location
`c:\Dropbox\Projects\AHK\AutoHotkey.ahk` lines 843-1054

### Execution Flow

```
MButton Down (843-956)
    │
    ├─► Gather context (window, control, exe, class)
    │
    ├─► Evaluate filters:
    │   ├── HasNativeScroll? → Passthrough (Chrome, Everything)
    │   ├── IsAllowedApp/Content? → Continue
    │   └── IsExcludedRegion? → Passthrough (toolbars, headers)
    │
    ├─► Select method:
    │   ├── ForceUIA (mmc, Explorer file lists)
    │   ├── UseWheelCtrl (SI)
    │   ├── UseVScroll (SysTreeView32)
    │   └── UseWheel (VS Code)
    │
    ├─► Initialize method-specific state:
    │   └── UIA: Create COM object, get ScrollPattern, get ViewSize
    │
    └─► Start timer (50ms for VSCROLL, 10ms for others)

Timer Loop (958-1043)
    │
    ├─► Safety: Exit if MButton released
    │
    ├─► Calculate displacement from origin
    │
    ├─► Apply acceleration curve:
    │   └── curveValue = dist^0.8 (≤100px) or 100^0.8 + (dist-100)^0.6 (>100px)
    │
    └─► Execute scroll method:
        ├── UIA: deltaPct = curve * 0.006 * (ViewSize/3); SetScrollPercent
        ├── WHEEL/WHEEL_CTRL: delta = min(119, curve/2); PostMessage WM_MOUSEWHEEL
        └── VSCROLL: send 1 line per tick (slower timer handles speed)

MButton Up (1045-1065)
    │
    ├─► Stop timer, clear tooltip
    │
    ├─► Release UIA COM objects
    │
    └─► If not triggered (no drag): send middle-click
```

---

## Architectural Goals

### 1. Full App-Agnostic Fallback Chain (GOAL - NOT YET IMPLEMENTED)

**Goal**: Auto-detect the best scroll method at runtime via a fallback chain, eliminating hardcoded app lists.

**Current State**: All method selection is hardcoded. No automatic fallback detection is working yet.
- ❌ UIA → WHEEL fallback (hardcoded via `ForceUIA`)
- ❌ WHEEL → WHEEL_CTRL fallback (hardcoded via `UseWheel`)
- ❌ WHEEL_CTRL → VSCROLL fallback (code exists at lines 1021-1038 but logic is flawed)

**Why current WHEEL_CTRL → VSCROLL detection doesn't work**:
The code at lines 1021-1038 compares `expectedLines` (what we requested) to `MB_LinesScrolled` (messages we sent). Both are OUR counters - we have no way to detect how many lines the control ACTUALLY scrolled. The fallback condition can never trigger.

**How to actually implement fallback detection**:
Query scroll position before/after sending WHEEL_CTRL using `GetScrollPos` (works cross-process):
1. Get scroll position before sending WHEEL_CTRL message
2. Send WHEEL_CTRL message
3. Get scroll position after
4. If position jumped by more than 1 line (~40 units):
   - Immediately send message to revert to previous position (invisible to user)
   - Switch to VSCROLL method for remainder of drag
5. If position moved ~1 line, stay with WHEEL_CTRL

**Important**: Do NOT check for ScrollPattern - it always returns NO even when scrolling works.

**Target Architecture** (future goal):
```
┌─────────────────────────────────────────────────────────────────┐
│                    Method Priority Chain                         │
├─────────────────────────────────────────────────────────────────┤
│  1. UIA (best: fractional %, knows content size)                │
│     └── Fallback if: SetScrollPercent fails or no movement      │
│                                                                  │
│  2. WHEEL (to window - good for Electron apps)                  │
│     └── Fallback if: No scroll response detected                │
│                                                                  │
│  3. WHEEL_CTRL (to control - 1 line/msg apps like SI)           │
│     └── Fallback if: GetScrollPos shows >1 line jump (~40 units)│
│         → Revert position immediately, switch to VSCROLL        │
│                                                                  │
│  4. VSCROLL (universal fallback - always works)                 │
│     └── 1 line per tick, dynamic timer for acceleration         │
└─────────────────────────────────────────────────────────────────┘
```

**Key Insight** (for future implementation): Controls don't do sub-120 delta accumulation. SI works with WHEEL_CTRL because it scrolls 1 line per wheel message (regardless of delta), while most controls scroll 3 lines per message.

### 2. Dynamic VSCROLL Timer (IMPLEMENTED)

**Goal**: VSCROLL acceleration via timer speed instead of line count.

**How It Works**:
```
Drag Distance → Timer Interval → Scroll Speed
     8px      →     150ms      →   ~7 lines/sec (slow)
    100px     →     100ms      →  ~10 lines/sec (moderate)
    200px+    →      50ms      →  ~20 lines/sec (fast)
```

**Formula**:
```autohotkey
timerMs := 150 - Floor((Min(AbsDist, 200) - 8) * (100 / 192))
timerMs := Max(50, Min(150, timerMs))
SetTimer, MBScrollTimer, %timerMs%
```

### 3. Consolidate Configuration

**Current**: Scattered boolean expressions.

**Proposed**: Single configuration block:
```autohotkey
; === SCROLL CONFIG ===
PassthroughApps := ["chrome.exe", "everything64.exe", "VmConnect.exe"]
EnabledApps := ["mmc.exe", "7zFM.exe", "code.exe", "SystemInformer.exe"]
ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "SysHeader"]
; Methods auto-detected via fallback chain
```

### 4. Clean Up Dead Code

**Remove**:
- SCROLLBAR method (commented out, lines ~1000)
- Unused globals: `MB_ScrollbarHwnd`, `MB_ScrollMin`, `MB_ScrollMax`

---

## Key Technical Insights

### Why Each Method Exists

| Method | Why It's Needed |
|--------|-----------------|
| UIA | Only method that provides true fractional scrolling and knows content size |
| WHEEL | VS Code/Electron route wheel internally; control targeting breaks it |
| WHEEL_CTRL | Controls that scroll 1 line per wheel message (SI); includes fallback detection |
| VSCROLL | Universal fallback for controls that scroll 3+ lines per wheel message |

**Important**: WHEEL_CTRL doesn't actually support sub-120 delta accumulation. SI works well with it simply because SI scrolls 1 line per wheel message (regardless of delta), while most controls scroll 3 lines. The fallback detection auto-switches to VSCROLL for controls that scroll >1 line per message.

### Dynamic Timer for VSCROLL
- VSCROLL can only send 1 line per message
- Timer now dynamically adjusts based on drag distance:
  - 8px drag → 150ms timer → ~7 lines/sec (slow start)
  - 200px+ drag → 50ms timer → ~20 lines/sec (fast)
- This provides natural acceleration without needing fractional lines

### Wheel Delta Behavior
- Standard wheel notch = 120 = 3 lines in most apps
- **Misconception**: Sub-120 deltas do NOT accumulate in controls
- **Reality**: Each wheel message scrolls a fixed number of lines (1 or 3) regardless of delta
- SI happens to scroll 1 line per message → works well with WHEEL_CTRL
- Most controls scroll 3 lines per message → need VSCROLL for smooth 1-line scrolling
- The fallback detection compares requested lines (via delta accumulator) to actual scroll events

### ViewSize Normalization (UIA only)
```
ViewSize = what % of content is visible
mult = ViewSize / 3.0

Examples:
  3 items in 3-item list   → ViewSize=100% → mult=33  → very fast
  10 items in 100-item list → ViewSize=10%  → mult=3.3 → moderate
  10 items in 1000-item list → ViewSize=1%  → mult=0.3 → slow
```

---

## Test Matrix

| Scenario | Method | Expected Behavior |
|----------|--------|-------------------|
| Explorer file list (few files) | UIA | Fast scroll, mult > 10 |
| Explorer file list (many files) | UIA | Slower scroll, mult < 5 |
| Explorer nav bar | VSCROLL | 1 line per 50ms tick |
| VS Code editor pane | WHEEL | Smooth sub-line scroll |
| VS Code file tree | WHEEL | Routes to correct pane |
| SystemInformer process list | WHEEL_CTRL | Smooth acceleration |
| mmc.exe snap-in list | UIA | Normalized scroll |
| Chrome (passthrough) | - | Native MButton behavior |
| Toolbar/header click | - | Native MButton behavior |

---

## Session History Notes

### Methods Tried and Rejected
| Method | App | Result |
|--------|-----|--------|
| UIA | SystemInformer | No ScrollPattern exposed |
| UIA | Explorer nav bar | Erratic jumping, position instability |
| WHEEL | Explorer nav bar | No response |
| WHEEL_CTRL | Explorer nav bar | Not smooth (ignores sub-120) |
| SCROLLBAR (SetScrollPos) | mmc, SI | Cross-process pointer issues |
| SendMessage vs PostMessage | WHEEL_CTRL | No difference |
| VSCROLL with accumulator | SI, nav bar | Unnecessary complexity |

### What Works
- **UIA + ViewSize normalization**: Explorer file lists, mmc (hardcoded via `ForceUIA`)
- **WHEEL to window**: VS Code (hardcoded via `UseWheel`)
- **WHEEL_CTRL to control**: SystemInformer (hardcoded via `UseWheelCtrl`)
- **VSCROLL with dynamic timer**: Explorer nav bar (hardcoded via `UseVScroll` for SysTreeView32)
