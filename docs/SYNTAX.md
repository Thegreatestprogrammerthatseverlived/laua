# Laua Syntax Reference — v3.46

> **Target:** Laua **v3.46**, transpiling `.laua` into Roblox `.luau`. This is a syntax quick reference; see [Documentation.md](Documentation.md) for behavior, setup, API details, and limitations. Laua is a **transpiler**, not a new runtime or game engine.
>
> **Verification:** Examples are based on the shipped v3.46 source, changelog, and regression tests. Website/standalone JavaScript parity is tested; the native Luau transpiler has **not** been executed in Roblox Studio. Examples containing deliberate errors are marked as such.

## Contents

1. [How to read this reference](#1-how-to-read-this-reference)
2. [Classes and members](#2-classes-and-members)
3. [Namespaces, modules, and enums](#3-namespaces-modules-and-enums)
4. [Events, async, and cleanup](#4-events-async-and-cleanup)
5. [Pattern matching](#5-pattern-matching)
6. [Expressions and collections](#6-expressions-and-collections)
7. [Functions and transpilation-time syntax](#7-functions-and-transpilation-time-syntax)
8. [Schemas and v3.46 language cleanup](#8-schemas-and-v346-language-cleanup)
9. [Project tool and source-map syntax](#9-project-tool-and-source-map-syntax)
10. [Options, diagnostics, and compatibility](#10-options-diagnostics-and-compatibility)

## 1. How to read this reference

- All ordinary supported **Luau** syntax (for example `local`, `function`, `if`, `for`, `--!strict`, Luau types, `task`, and Roblox APIs) remains available, subject to Laua's source-transform limitations.
- Laua **syntax words** can be contextual; a word shown here is not necessarily globally reserved.
- Laua code snippets are **input**, not code to paste directly into an untranspiled Roblox Script.
- `schema`, `exhaustive`, `cancelScope()` and the multi-file project tool remain supported. The former custom `signal` and `network` features have been **removed** in v3.46.
- Runtime helpers are added only for code that requires them. Static `match exhaustive` checking does not add a runtime helper.

## 2. Classes and members

### A class and its instance

```laua
class Player
    Health: number = 100
    Name: string = "Unknown"

    constructor(name: string)
        self.Name = name
    end

    function Damage(amount: number)
        self.Health -= amount
    end
end

local player = new Player("Riley")
player:Damage(20)
print(player.Health)
```

| Syntax | Purpose |
| --- | --- |
| `class Name ... end` | Declare a table/metatable-backed class. |
| `constructor(args) ... end` | Run instance initialization. |
| `new Name(args)` / `new Name` | Instantiate a Laua class. |
| `self` | Instance receiver, as in ordinary Luau. Do **not** replace it with `this`. |
| `public`, `private`, `protected` | Visibility intent and selected static diagnostics. Not a security boundary. |
| `static` | Class-level member. |
| `abstract class` / `abstract function` | Abstract classes and methods. |
| `final class` / `final function` | Prevent selected extensions/overrides. |
| `override function` | Declare an overriding inherited member. |

### Inheritance and `super`

```laua
class Entity
    function Describe()
        return "Entity"
    end
end

class Enemy extends Entity
    override function Describe()
        return super.Describe() .. " / Enemy"
    end
end

print((new Enemy()):Describe())
```

`super(...)` calls the immediate superclass's initializer inside a child constructor. `super.Method(...)` or `super:Method(...)` calls an inherited instance method and forwards `self`; static and explicit receiver cases have different rules.

### Properties, lazy values, and watchers

```laua
class HealthState
    Health: number = 100
    lazy Inventory = {"Bandage"}

    get IsAlive()
        return self.Health > 0
    end

    set CurrentHealth(value: number)
        self.Health = math.max(0, value)
    end

    watch Health(before, after)
        print(before, after)
    end
end
```

`get` is a computed getter; `set` intercepts assignment to its named property; `lazy` caches an initializer on first read; `watch` observes managed property changes. Use Roblox events (`RBXScriptSignal`, `RemoteEvent`, or `BindableEvent`) rather than the removed Laua `signal` declaration.

### Operators and instance test

```laua
class Amount
    Value = 0
    constructor(n: number)
        self.Value = n
    end
    operator +(other)
        return new Amount(self.Value + other.Value)
    end
end

local total = new Amount(2) + new Amount(3)
print(total is Amount)
```

The supported class `operator` symbols map to Luau metamethods: `+`, `-`, `*`, `/`, `//`, `%`, `^`, `..`, `==`, `<`, `<=`, and `#` (subject to metamethod semantics).

## 3. Namespaces, modules, and enums

### Namespaces

```laua
namespace MathTools
    Pi = 3.14159
    function Double(n: number): number
        return n * 2
    end
end

print(MathTools.Double(5))
```

A namespace can also be **directly returned** from a function:

```laua
local function MakeAPI()
    return namespace API
        Version = 341
    end
end
```

`local x = namespace API ... end` is **not** a supported namespace-expression form.

### Enums

```laua
enum State
    Idle
    Running
    Dead
end

local state = State.Running
```

Enum tables are frozen, with automatic numeric values starting at `0`. An explicitly numbered member does **not** automatically advance the next implicit number in the shipped enum lowering; use explicit numbers if sequence continuity matters.

### Module declarations

```laua
-- PlayerData.laua
export class PlayerData
    Health = 100
end

export function StartingHealth(): number
    return 100
end
```

```laua
-- Main.laua
import {PlayerData, StartingHealth as GetHealth} from "./PlayerData"
local player = new PlayerData()
print(GetHealth(), player.Health)
```

Other recognized forms include `import Module from "./Module"` and `import lazy Module from "./Module"`. Imports use relative paths (`./`, `../`) and lower to `require` against the corresponding Roblox ModuleScript hierarchy. Module files must be placed appropriately in the DataModel; transpiling does not create them.

## 4. Events, async, and cleanup

### Roblox events and connections

The custom Laua `signal` declaration was removed in v3.46. Existing Roblox events and their `:Connect(...)` callbacks are unchanged:

```laua
local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    print(input.KeyCode)
end)
```

The playground can offer callback parameter hints when Roblox API metadata is available. Its more demanding strict-annotation policy is a playground lint feature, not a promise of identical Roblox Studio type inference.

### Async functions

```laua
async function Fetch()
    task.wait(0.1)
    return 42
end

async function UseResult()
    return await Fetch()
end

UseResult():andThen(function(value)
    print(value)
end)
```

`await` belongs in supported async contexts. Laua async functions produce a Promise-like result, not parallel CPU execution.

### `defer` and `using`

```laua
local function Monitor()
    using connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
        print(dt)
    end)

    defer
        print("Leaving Monitor")
    end
end
```

Cleanup belongs to the enclosing function's lifetime, not automatically to each nested `if` or `do` block.

### `cancelScope()` — new in v3.41

```laua
local function StartWork()
    using scope = cancelScope()
    scope:Spawn(function()
        print("Running")
    end)
    scope:OnCancel(function()
        print("Cleaned up")
    end)
end
```

| Scope API | Meaning |
| --- | --- |
| `cancelScope()` | Construct a cancellation scope; inject the helper only when used. |
| `scope:Spawn(fn)` | Spawn and track a task thread. |
| `scope:OnCancel(fn)` | Register a callback, invoked in reverse registration order on cancellation. |
| `scope:Cancel()` | Idempotently cancel tracked work and run cleanup callbacks. |
| `scope:Dispose()` | Alias for `Cancel()`, usable by `using`. |

Scope cancellation is **not** automatically propagated through all existing `async`/`await` operations.

## 5. Pattern matching

### Existing `match`

```laua
match state
    case State.Idle
        print("Idle")
    case State.Running
        print("Running")
    default
        print("Other")
end
```

Supports selected table patterns and guarded cases, within the current transformer's limits. It is a statement construct, not a general expression-returning `match`.

### `match exhaustive` — new in v3.41

```laua
enum Status
    Ready
    Busy
    Offline
end

local status: Status = Status.Ready
match exhaustive status
    case Status.Ready
        print("Ready")
    case Status.Busy
        print("Busy")
    case Status.Offline
        print("Offline")
end
```

The transpiler can check enum members or boolean `true`/`false` cases, and diagnose missing or duplicate arms. A `default` handles unsupported/unknown cases; guarded cases require `default`. It does not perform complete union-type exhaustiveness or arbitrary nested pattern analysis.

## 6. Expressions and collections

| Form | Example | Meaning / boundary |
| --- | --- | --- |
| Optional field | `model?.Health` | Returns `nil` if receiver is `nil`. |
| Optional index | `model?.[key]` | Avoid evaluating the index if receiver is `nil`. |
| Optional method | `obj?.:GetHealth()` | Preserves method receiver when non-`nil`. |
| Optional dot-call | `obj?.GetHealth()` | Dot-style call; no automatic `self`. |
| Coalescing | `a ?? fallback` | Uses fallback only when `a == nil`, not when `a == false`. |
| Coalescing assignment | `a ??= fallback` | Assigns only when current value is `nil`. |
| Early-return suffix | `local value = input?` | Limited simple local/const declaration syntax; returns early on `nil`. |
| Arrow function | `local double = (x) => x * 2` | One expression on one line. |
| Pipeline | `local x = 2 |> Double |> tostring` | Single-line named-function stages. |
| Spread-only table | `local both = {...first, ...second}` | Merge supported simple receivers; not arbitrary mixed spreads. |
| Inclusive slice | `local part = text[1:3]` | String/buffer slice with integer bounds, 1-based. |
| Record destructuring | `local {Health, Name: Display} = data` | Single-level fields with optional rename. |

The transpiler also rewrites `table.map`, `table.filter`, `table.reduce`, and `table.findWhere` to embedded helpers where necessary; these are not new native Roblox `table` methods.

## 7. Functions and transpilation-time syntax

### Defaults, memoization and inline specialization

```laua
local function Multiplier(amount: number = 2)
    return amount
end

memo function Square(x: number): number
    return x * x
end

print(Square(4))
memo.clear(Square)
memo.clear()

inline function Increment(x)
    return x + 1
end
```

Default parameters use their declared expression when the caller supplies `nil`/omits the argument. `memo` caches named function results; `memo.clear(MyFunction)` clears a specific cache and `memo.clear()` clears all memo caches in the current script. Neither form removes the function or sets a cache size limit. `inline` is a **restricted** static specialization, not a universal inliner.

### Conditional transpilation

```laua
--#if DEBUG
print("Debug transpilation")
--#else
print("Other mode")
--#end
```

Modes: `Development`, `Debug`, `Release`. Branches are decided when transpiling, not at runtime.

### Lint annotation

```laua
@nolint("UnusedLocal")
local unused = 10
```

`@nolint` is intended for selected editor lint warnings. **Known limitation:** the browser/JavaScript semantic preflight may require an isolated workaround for certain annotations; see [Documentation.md](Documentation.md#151-const-and-semantic-preflight-notes). It is not a universal syntax/type-error suppression.

### `const`, instance method calls and reserved names

`const` is recognized in the editor and forwarded by the transpiler where supported. The playground checks selected attempted reassignments; inspect generated output in your target Studio toolchain instead of assuming complete cross-tool immutability enforcement.

Inside a Laua class, methods implicitly receive `self`. Call `entity:Move()` or explicitly `entity.Move(entity)`; `entity.Move()` is rejected for a known instance method because it omits `self`. A subclass cannot silently replace an inherited getter/setter with an ordinary method (or vice versa). These checks apply to statically recognized Laua classes; fully dynamic receivers remain less predictable.

Internal runtime bindings such as `Promise`, `Promises`, `LauaCore`, `LauaPromiseStatus`, and `__laua...` names are reserved against conflicting user declarations in v3.46. Prefer your own distinct names.

## 8. Schemas and v3.46 language cleanup

### Runtime schema declaration

```laua
schema Purchase
    ItemId: string
    Quantity: number
    Tags: {string}?
end

local valid, reason = Purchase.Validate({ItemId = "Sword", Quantity = 1})
local data = Purchase.Assert({ItemId = "Sword", Quantity = 1})
```

**Supported field annotations:** `number`, `string`, `boolean`, `table`, `function`, `thread`, `Instance`, `Vector3`, `CFrame`, `Color3`, `any`, `{T}` where `T` is supported, and previously defined schema identifiers. One field per line; trailing `?` allows an absent field. No schema defaults, unions, map/index signatures, generic schema declarations, or cross-module schema references. Extra keys are currently accepted.

`Validate(value)` returns `(boolean, string?)` and reports the first invalid field; `Assert(value)` returns the input on success or throws on failure. This validates **shape/types**, not authorization or size/range limits.

### Removed custom signal/network declarations

The previous Laua-language declarations `signal`, `network`, `client_to_server`, and `server_to_client` have been removed. They are **not** Laua keywords or generated helper contracts in v3.46. Former syntax names can be used as ordinary identifiers when valid. Roblox's own networking and event objects still work:

```laua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remote = ReplicatedStorage:WaitForChild("InventoryRemote")
Remote.OnServerEvent:Connect(function(player: Player, itemId: string)
    print(player, itemId)
end)
```

This example assumes server execution and an existing `RemoteEvent`; add server-side authorization and payload validation for real gameplay.

## 9. Project tool and source-map syntax

### CLI

```sh
node project-transpiler.cjs ./src ./out Compact
```

Third argument is optional: `Readable` (default) or `Compact`. The tool recursively processes `.laua` files, verifies relative imports and requested exports, detects import cycles, performs **limited** imported-signature/member checks, and writes matching `.luau` and `.luau.map.json` files.

### Node API

```js
const {transpileProject, originalLocation, remapStackTrace} = require('./project-transpiler.cjs');

const project = transpileProject({
    'main.laua': 'local answer = 42\nprint(answer)'
}, {OutputStyle: 'Compact'});

console.log(project.files['main.luau']);
console.log(project.sourceMaps['main.luau.map.json']);
```

The source maps are **sparse**: generated lines with no unambiguous, identical source line are `null`, and a location is only remapped when a safe mapping exists. They do not provide arbitrary expression/character-level source maps or automatic Studio runtime remapping.

## 10. Options, diagnostics, and compatibility

### JavaScript and native transpiler options

```js
const {transpile, compilationStats} = require('./compiler.js');
const source = 'local coins = nil ?? 50';
const generated = transpile(source, {Mode: 'Development', OutputStyle: 'Readable', SemanticCheck: true});
console.log(generated, compilationStats(source, generated));
```

| Option | Accepted values | Default |
| --- | --- | --- |
| `Mode` | `Development`, `Debug`, `Release` | `Development` |
| `OutputStyle` | `Readable`, `Compact` | `Readable` |
| `SemanticCheck` | `true`, `false` | `true` |

`SemanticCheck: false` disables **some** semantic preflight checks; it does not guarantee syntactically valid output or safe execution.

### Current boundaries

- The JavaScript implementations have tested parity with each other. Native `transpiler.luau` contains corresponding v3.46 lowering, but **was not run** in a native Luau/Roblox Studio environment for this release.
- Laua's analyzer is not a full AST/control-flow type checker, and its project checker handles a conservative subset of module expressions.
- `match exhaustive` checks recognized enum/boolean cases; schemas have a deliberately limited grammar.
- Source maps skip transformed lines; generated Luau still requires Roblox Studio Script Analysis and runtime tests.
- See [Documentation.md](Documentation.md), [KEYWORDS.md](KEYWORDS.md) and the v3.46 validation report for full descriptions and security boundaries.

**Related:** [Full documentation](Documentation.md) · [Keywords](KEYWORDS.md) · [Laua repository](https://github.com/Thegreatestprogrammerthatseverlived/laua) · [Website](https://laua.dev)
