# Laua Documentation — v3.46

Laua (pronounced **lau-wuh**) is a **source-to-source transpiler for Roblox Luau**. You write `.laua` files using ordinary Luau plus additional constructs; the transpiler produces `.luau` source for Roblox. Laua is **not** a separate Roblox game engine, virtual machine, or security sandbox.

**Version:** v3.46 — October 14, 2026. This reference is grounded in the v3.46 release sources, tests, changelog and validation report. Earlier v3.41 feature guides are historical; some described features were removed in this version.

> **Verification boundary:** The v3.46 release records 23 passing executable Node test scripts, JavaScript/website transpiler parity, and selected Lua 5.3 compatibility comparisons. **Native Luau transpiler execution in Roblox Studio was not verified.** Roblox networking, cancellation, and generated runtime behavior require their own Studio testing before production use.

**Other references:** [Syntax quick reference](SYNTAX.md) · [Keyword inventory](KEYWORDS.md) · [Repository](https://github.com/Thegreatestprogrammerthatseverlived/laua) · [Playground](https://laua.dev)

## Table of contents

1. [Install, transpile, and run](#1-install-transpile-and-run)
2. [Transpiler targets and options](#2-transpiler-targets-and-options)
3. [Classes, members, and inheritance](#3-classes-members-and-inheritance)
4. [Property system and managed fields](#4-property-system-and-managed-fields)
5. [Namespaces, enums, modules, and exports](#5-namespaces-enums-modules-and-exports)
6. [Async, await, defer, and using](#6-async-await-defer-and-using)
7. [Expressions, functions, and collection helpers](#7-expressions-functions-and-collection-helpers)
8. [Match and exhaustive match](#8-match-and-exhaustive-match)
9. [Runtime schemas (v3.41)](#9-runtime-schemas-v341)
10. [Retired custom networking and Roblox events (v3.46)](#10-retired-custom-networking-and-roblox-events-v346)
11. [Cancellation scopes (v3.41)](#11-cancellation-scopes-v341)
12. [Multi-file project transpilation (v3.41)](#12-multi-file-project-transpilation-v341)
13. [Source maps and error reporting (v3.41)](#13-source-maps-and-error-reporting-v341)
14. [Output efficiency and performance](#14-output-efficiency-and-performance)
15. [Static diagnostics and limitations](#15-static-diagnostics-and-limitations)
16. [Testing and release verification](#16-testing-and-release-verification)
17. [Troubleshooting and production checklist](#17-troubleshooting-and-production-checklist)

---

## 1. Install, transpile, and run

### 1.1 Obtain the v3.46 package

The v3.46 release ZIP includes native and JavaScript transpilers, the browser playground, a manual Studio verification harness, examples, and regression tests. The older `docs/V341_FEATURE_GUIDE.md` is historical and describes removed features; use these v3.46 docs instead. In the repository or extracted release root:

| File | Purpose |
| --- | --- |
| `playground.html` | Preferred self-contained web playground with an embedded JavaScript transpiler core; `index.html` can be a hosting alias. |
| `transpiler.luau` | Native Luau ModuleScript transpiler, marked v3.46. Native execution in Roblox Studio is **unverified**. |
| `docs/Documentation.md`, `docs/SYNTAX.md`, `docs/KEYWORDS.md` | Current v3.46 references. |

You do **not** install a separate Laua virtual machine into your game. The transpiled `.luau` code is what Roblox executes.

### 1.2 Transpile one source in Node.js

From the extracted release root, with Node.js available:

```js
const {transpile, compilationStats} = require('./compiler.js');

const input = `
class Counter
    Value: number = 0
    function Increment()
        self.Value += 1
    end
end
local counter = new Counter()
counter:Increment()
print(counter.Value)
`;

const output = transpile(input, {Mode: 'Development', OutputStyle: 'Readable'});
console.log(output);
console.log(compilationStats(input, output));
```

`transpile(source, options?)` returns the generated Luau **string**, not the result of running that Luau. `compilationStats` is the exported historical API name for comparing source/output bytes and line counts; the operation remains **transpilation**.

The standalone JavaScript implementation does not itself create Roblox Instances, run `RemoteEvent`s, or analyze scripts inside Studio.

### 1.3 Use the native Luau ModuleScript

Store `transpiler.luau` as a ModuleScript where your Studio verification setup can require it:

```luau
local Transpiler = require(script.Parent.Transpiler)

local input = [[
class Enemy
    Health = 100
end
local enemy = new Enemy()
print(enemy.Health)
]]

local generated = Transpiler.Transpile(input, {Mode = "Development", OutputStyle = "Readable"})
print(generated)
```

The snippet assumes your ModuleScript was named `Transpiler`. **This call produces source, not a new running Script**. Do not paste raw `class` or `schema` declarations into a regular Script unless they have first been transpiled.

**Native parity caution:** The release contains matching intended transformations in `transpiler.luau`, but running it and comparing exact results with JavaScript remains separate verification work.

### 1.4 Playground and project workflows

The web playground at [laua.dev](https://laua.dev) contains the embedded transpiler and editing tools. The preferred distributed page is `playground.html`; hosts that expect `index.html` need a corresponding entry point or routing configuration. It can transpile source in the browser without running Roblox game code.

For multiple `.laua` files, use the opt-in project transpiler described in [section 12](#12-multi-file-project-transpilation-v341). The generated relative imports require a matching Roblox ModuleScript hierarchy; the project CLI does not itself deploy to the DataModel.

---

## 2. Transpiler targets and options

### 2.1 Options

| Option | Values | Default | Behavior |
| --- | --- | --- | --- |
| `Mode` | `"Development"`, `"Debug"`, `"Release"` | `"Development"` | Selects branches for transpilation-time `--#if` directives. |
| `OutputStyle` | `"Readable"`, `"Compact"` | `"Readable"` | Chooses output formatting; Compact removes safely removable whitespace/comments, not all formatting. |
| `SemanticCheck` | `true`, `false` | `true` | Controls supported name/member/type checks. `false` is a limited diagnostic escape hatch. |

Invalid modes and output styles raise an error. Syntax checks still apply with `SemanticCheck: false`; disabling these checks **does not** validate generated Luau or make unknown methods safe.

**Luau directives** such as `--!strict`, `--!nonstrict`, and `--!nocheck` are separate from Laua transpiler options. Use Studio Script Analysis on the generated source.

### 2.2 Three implementation targets

The v3.46 package has (1) a standalone JavaScript transpiler, (2) the JavaScript transpiler embedded in the web page, and (3) the independent native Luau transpiler. The standalone and embedded JavaScript cores were compared byte-for-byte by release tests. **That does not establish native Luau behavior or diagnostic parity.**

When changing language behavior, update and test every relevant target. A documentation-only change does not increment the transpiler version.

---

## 3. Classes, members, and inheritance

### 3.1 `class`, `constructor`, `new`, and `self`

```laua
class PlayerData
    Name: string = "Player"
    Health: number = 100

    constructor(name: string)
        self.Name = name
    end

    function TakeDamage(amount: number)
        self.Health = math.max(0, self.Health - amount)
    end
end

local player = new PlayerData("Alex")
player:TakeDamage(25)
print(player.Name, player.Health)
```

A Laua class becomes a Luau table, an instance metatable, and an initializer/constructor pair. Instance methods take the receiver through normal Luau `:` method syntax. Use **`self`**, not `this`.

Fields can use ordinary Luau annotations. A declared default value is initialized when the instance is constructed. An explicit assignment inside the constructor happens afterward, even if it appears to repeat the default; those writes can have observable effects.

### 3.2 Inheritance and parent calls

```laua
class Entity
    Name = "Entity"

    constructor(name: string)
        self.Name = name
    end

    function Describe()
        return self.Name
    end
end

class Zombie extends Entity
    constructor(name: string)
        super(name)
    end

    override function Describe()
        return super.Describe() .. " is a zombie"
    end
end

print((new Zombie("Runner")):Describe())
```

- `extends` names the immediate parent class.
- `super(...)` invokes the parent initializer on the **same instance**.
- `super.Method(...)` or `super:Method(...)` invokes the inherited instance method, passing `self` correctly through multi-level inheritance. Static parent calls are handled separately.
- `override` documents a deliberate override and enables known contract checks. The transpiler detects selected missing override targets, final violations, inheritance cycles, and duplicate definitions.

The inherited-method receiver bug identified before v3.38 is covered by later regressions; that does not replace testing new inheritance cases in Studio.

### 3.3 Visibility and modifiers

| Modifier | Meaning | Limit |
| --- | --- | --- |
| `public` | Intended public member. | Ordinary Luau table access is still possible. |
| `private` | Access intended only within defining class. | Checked in known static cases; **not** runtime authorization. |
| `protected` | Access intended within class/subclasses. | Dynamic aliases may bypass static checks. |
| `static` | Member on the class table. | Use class-style access. |
| `abstract` | Abstract class or required method. | Does not eliminate all dynamic runtime misuse. |
| `final` | Non-extensible class or non-overridable method. | Primarily static/known contract enforcement. |
| `override` | Marks an inherited member override. | Selected transpilation-time checks; not a complete nominal type system. |

Example:

```laua
abstract class EnemyBase
    protected Health = 100
    abstract function Move()
    end
end

class Runner extends EnemyBase
    static Spawned = 0
    override final function Move()
        print(self.Health)
    end
end
```

### 3.4 Operators and class membership

```laua
class Score
    Value = 0
    constructor(value: number)
        self.Value = value
    end
    operator +(other)
        return new Score(self.Value + other.Value)
    end
end

local a = new Score(2)
local b = new Score(3)
print((a + b).Value)
print(a is Score)
```

Supported operator symbols are translated to matching Luau metamethods: `+`, `-`, `*`, `/`, `//`, `%`, `^`, `..`, `==`, `<`, `<=`, and `#`. Laua's `is` checks Laua class membership, **not** Roblox Instance ancestry (`Instance:IsA`).

---

## 4. Property system and managed fields

### 4.1 Getters, setters, lazy fields, and watchers

```laua
class HealthState
    Health: number = 100
    lazy Inventory = {"Medkit"}

    get IsAlive()
        return self.Health > 0
    end

    set NewHealth(value: number)
        self.Health = math.max(0, value)
    end

    watch Health(previous, current)
        print(previous, current)
    end
end
```

- `get Property()` calculates a readable property.
- `set Property(value)` handles writes to that property; setters take one parameter.
- `lazy Field = expression` computes the value on first read and caches it for each instance.
- `watch Field(before, after)` runs when a managed field is written. The observer is local, not replicated.

The v3.38/v3.39 lowerings established per-instance lazy state and optimized away unused property machinery for simple class hierarchies. The feature set remains sensitive to Luau metatable semantics: a raw field that shadows a managed property can bypass `__newindex`. Test repeated writes, inheritance, lazy initialization failures, and side effects in Studio.

### 4.2 Roblox events remain available

Laua v3.46 removed its **custom class `signal` declaration**. This does not remove Roblox's event APIs; ordinary `RBXScriptSignal`, `BindableEvent`, and `RemoteEvent` usage works as usual:

```laua
local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then return end
    print(input.KeyCode)
end)
```

No Laua-specific signal object is generated for this example. The playground can display expected callback parameter names/types from available Roblox API metadata. Those hints and the browser linter are **editor tooling**, not substitute security or runtime type guarantees.

---

## 5. Namespaces, enums, modules, and exports

### 5.1 Namespaces

```laua
namespace MathTools
    Pi = 3.14159

    function Double(value: number): number
        return value * 2
    end
end

print(MathTools.Double(6))
```

Namespace lowering produces a Luau table. `local function` inside the namespace is internal; exposed namespace functions and fields appear on the namespace table. A namespace may be directly returned from a function:

```laua
local function BuildAPI()
    return namespace API
        Version = 341
    end
end
```

This does **not** mean `namespace` is a general first-class expression: `local api = namespace API ... end` is not supported.

### 5.2 Enums

```laua
enum State
    Idle
    Running
    Dead
end

print(State.Running)
```

Laua emits a frozen table. Automatic numeric members start at `0`. For mixed explicit/implicit numbering, the current lowering's implicit counter progresses independently of explicit assignments:

```laua
enum Example
    First
    Custom = 10
    Next
end
```

`First` is `0`, `Custom` is `10`, and `Next` is `1` in the shipped JavaScript lowering. Specify each value if the exact enum numbers matter.

### 5.3 Imports and exports

```laua
-- Health.laua
export function GetDefaultHealth(): number
    return 100
end
```

```laua
-- Main.laua
import {GetDefaultHealth as Health} from "./Health"
print(Health())
```

Recognized forms include named imports with `as`, importing a module's entire returned value, and lazy imports. Relative paths begin with `./` or `../`. Laua emits normal Luau `require()` chains using Roblox ModuleScripts. The corresponding hierarchy must exist when the generated scripts run; a relative file path alone does not create it.

`export` from Laua module syntax should not be confused with the native Luau type syntax `export type`.

**New in v3.41:** The project tool validates **known** relative imported module existence, requested exports, cycles, and selected direct member/argument operations before emission. See [section 12](#12-multi-file-project-transpilation-v341).

---

## 6. Async, await, defer, and using

### 6.1 `async` and `await`

```laua
async function FetchScore()
    task.wait(0.1)
    return 100
end

async function PrintScore()
    local score = await FetchScore()
    print(score)
end

PrintScore():catch(function(message)
    warn(message)
end)
```

Async functions return a Promise-like object. It supports methods such as `:andThen(...)` and `:catch(...)`. `await` yields within supported asynchronous contexts, and the transpiler injects the required helper only when used. Async does **not** make calculations automatically parallel, guarantee thread safety, or imply network replication.

### 6.2 `defer`

```laua
local function Process()
    defer
        print("Cleanup")
    end

    print("Processing")
end
```

`defer` registers cleanup for the **enclosing function**. Deferred callbacks execute on function exit (including supported error exits) in reverse registration order, not after every nested block.

### 6.3 `using`

```laua
local function WatchHeartbeat()
    using connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
        print(dt)
    end)
    task.wait(1)
end
```

`using value = resource` creates a resource and registers function-exit cleanup through a supported `Disconnect`, `Destroy`, or `Dispose` operation. Do not use `using` for a resource that must survive past the function's return unless ownership is explicitly transferred.

### 6.4 Cancellation is opt-in

v3.41 adds `cancelScope()`, but this is **not** a complete transformation of existing `async`/`await` into a structured-cancellation tree. See [section 11](#11-cancellation-scopes-v341).

---

## 7. Expressions, functions, and collection helpers

### 7.1 Optional chaining

```laua
local character = nil
local health = character?.Humanoid?.Health
local item = character?.["Item"]
local value = character?.:GetValue()
```

Optional access returns `nil` when the receiver is `nil`. Optional index expressions and call arguments are evaluated lazily where supported. The distinction between `obj?.Method()` (dot-style) and `obj?.:Method()` (method receiver) is important. A **non-`nil`** Roblox Instance with an invalid member name may still fail; optional chaining does not silence arbitrary bad member access.

### 7.2 Nil-coalescing and early return

```laua
local coins = nil
local fallback = coins ?? 25

local enabled = false
enabled ??= true -- remains false
```

`??` and `??=` operate on **`nil` only**. Do not use them as truthiness-based `or` replacements unless that is what you want.

```laua
local function ReadValue(input)
    local value = input?
    return value
end
```

The early-return postfix `?` is only supported on selected **single-name local/const assignments**, not general expression subtrees. It is different from `?.`, `??`, and optional type `T?`.

### 7.3 Arrow functions, pipelines, destructuring, spreads, and slices

```laua
local double = (x) => x * 2
local value = 5 |> double |> tostring

local info = {Health = 100, Name = "Player"}
local {Health, Name: Label} = info

local first = {1, 2}
local second = {3, 4}
local combined = {...first, ...second}

local text = "Laua"
local prefix = text[1:3]
```

Current grammar boundaries:

- Arrow functions are **one-line expressions**, not full block closures.
- Pipelines support selected single-line named-function stages (including supported dotted names); some arbitrary expressions and multiline chains are unsupported.
- Destructuring is single-level **named field** extraction, optionally renaming a field with `:`.
- Spread tables are spread-only literals with supported simple sources; mixed literal/spread forms are not generally supported.
- Slicing uses **inclusive**, 1-based integer bounds, including supported negative/end-relative bounds; the target is a simple string/buffer name or dotted receiver.

### 7.4 Table helpers

```laua
local values = {1, 2, 3}
local mapped = table.map(values, function(v)
    return v * 2
end)
local filtered = table.filter(values, function(v)
    return v > 1
end)
local sum = table.reduce(values, function(acc, v)
    return acc + v
end, 0)
local found = table.findWhere(values, function(v)
    return v == 2
end)
```

These are Laua-recognized helper calls and lower to its embedded Core functionality; they are not guaranteed built-ins on Roblox's global `table` library. `map`, `filter`, and `findWhere` callbacks take `(value, index)`; `reduce` takes `(accumulator, value, index)`.

### 7.5 Named memoization and limited inline substitution

```laua
memo function Square(x: number): number
    return x * x
end

print(Square(4))
memo.clear(Square) -- Clear Square only
memo.clear()       -- Clear every memo cache in this script

inline function AddOne(x)
    return x + 1
end
```

`memo` caches named-function results by arguments. v3.46 adds `memo.clear(Fn)` to reset the cache of one memoized function and `memo.clear()` to reset all memo caches in the script. A specific target must be a memoized function. Clearing does **not** replace the function, limit cache growth, or automatically invalidate results when outside state changes. Avoid memoizing side-effectful or time-dependent operations. `inline` only specializes restricted simple top-level functions; it does not inline arbitrary closures or complex bodies.

### 7.6 Transpilation-time branches

```laua
--#if DEBUG
print("Debug only")
--#else
print("Other modes")
--#end
```

The transpiler evaluates directives using `Mode` (`Development`, `Debug`, `Release`). Nested branches are supported within the current preprocessor; malformed/mismatched directives raise an error. These are transpilation-time decisions, not runtime `if` statements.

---

## 8. Match and exhaustive match

### 8.1 Existing `match`

```laua
match target
    case {Health = 0}
        print("Dead")
    case {Health = 100}
        print("Full health")
    default
        print("Other")
end
```

Laua evaluates the match subject once and checks cases in source order. Supported cases include selected table patterns and guards. It does **not** implement every possible destructuring/capture pattern, a general expression-returning match, or full union-type narrowing.

### 8.2 `match exhaustive` (new in v3.41)

```laua
enum State
    Idle
    Running
    Dead
end

local current: State = State.Idle
match exhaustive current
    case State.Idle
        print("Idle")
    case State.Running
        print("Running")
    case State.Dead
        print("Dead")
end
```

`exhaustive` is an **opt-in analysis modifier**. The JavaScript transpiler checks recognized enum members or boolean `true`/`false` arms, reports duplicate or missing cases, and detects some references to unknown enum members. The emitted Luau uses the existing `match` lowering and incurs **no additional runtime exhaustiveness helper**.

If the analyzer cannot prove completeness, include `default`; guarded cases also require `default`. This is **not** an exhaustive checker for every union, nested table pattern, or dynamic expression.

Example of intentionally invalid source:

```laua
-- INVALID: State.Dead is missing
enum State
    Idle
    Running
    Dead
end
local current: State = State.Idle
match exhaustive current
    case State.Idle
        print("Idle")
    case State.Running
        print("Running")
end
```

The v3.41 feature tests assert that a missing recognized enum member raises a diagnostic.

---

## 9. Runtime schemas (v3.41)

### 9.1 Declare a schema

```laua
schema PlayerData
    Name: string
    Health: number
    Items: {string}?
end

local valid, message = PlayerData.Validate({Name = "Player", Health = 100})
local player = PlayerData.Assert({Name = "Player", Health = 100})
```

A `schema` generates a Luau table with two methods:

| Method | Result |
| --- | --- |
| `Name.Validate(value)` | `(boolean, string?)`; returns `false` and an error describing the **first** invalid field, or `true, nil`. |
| `Name.Assert(value)` | Returns the **original value** if valid; throws an error for invalid values. |

These are **runtime data validators**, not a replacement for native Luau types or a database security policy. No general `schema<T>` or arbitrary schema-expression syntax is implemented.

### 9.2 Supported field grammar

Each field must be on its **own line** with a name, colon, and supported type:

```text
schema SchemaName
    Field: Type
    OptionalField: Type?
    List: {Type}
end
```

Supported field types in this version's JavaScript lowering:

- Luau value categories: `number`, `string`, `boolean`, `table`, `function`, `thread`, and `any`.
- Roblox types: `Instance`, `Vector3`, `CFrame`, `Color3`.
- Homogeneous arrays written `{T}` where `T` is a supported type name.
- A **previously declared schema** identifier, resolved by invoking that schema's `Validate` method at runtime.
- A trailing `?` denotes an optional value, including optional arrays such as `{string}?`.

The implementation does **not** currently support schema default expressions, union types, generic schemas, map/index signatures, cross-module schema references, or recursive/cyclic data validation. Extra table keys are currently accepted. Nested schema identifiers must resolve by the time validation runs, so declaration order matters.

### 9.3 Validation behavior and safety

```laua
schema Purchase
    ItemId: string
    Quantity: number
end

local ok, reason = Purchase.Validate({ItemId = "Sword", Quantity = "five"})
-- ok == false; reason identifies the invalid Quantity field.
```

Type validation **does not** check string lengths, quantity bounds, payload sizes, ownership, prices, item availability, rate limits, or whether a request is authorized. Treat schema checks as a layer of validation, not the complete trusted-server policy.

**Performance caution:** An array schema checks its members by iteration. Large or adversarially structured payloads need additional size and complexity caps on the server. Do not rely on schema validation to handle cyclic tables.

---

## 10. Retired custom networking and Roblox events (v3.46)

### 10.1 Removed Laua language constructs

The custom `network` contract and `signal` declarations, along with contextual `client_to_server` and `server_to_client`, are **not supported in v3.46**. Their dedicated runtime helper generation, keyword entries and autocomplete templates were removed. Laua does not reserve those names solely because an older version used them; they may be ordinary identifiers in valid expressions. The transpiler intentionally does **not** generate a migration warning or automatic replacement for old contract syntax.

Do not use the `network Inventory ... end` or `signal Updated(...)` examples found in historical v3.41 documentation; they no longer describe the current release.

### 10.2 Normal Roblox RemoteEvents and signals

Use ordinary Roblox APIs. For example, assuming an existing `RemoteEvent` named `InventoryRemote` in `ReplicatedStorage`:

```luau
-- Server Script
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("InventoryRemote")

remote.OnServerEvent:Connect(function(player, itemId)
    if typeof(itemId) ~= "string" then return end
    -- Validate permissions, price, ownership and rate limits on the server.
    print(player, itemId)
end)
```

```luau
-- LocalScript
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("InventoryRemote")
remote:FireServer("Sword")
```

This is standard Roblox Luau, not new Laua syntax. Laua's API-aware autocomplete and linting may suggest the events, but full API completion depends on a successfully loaded Roblox API database. Client input is untrusted: types alone do not authorize a purchase or prevent abuse.

## 11. Cancellation scopes (v3.41)

### 11.1 Basic usage

```laua
local function StartTask()
    using scope = cancelScope()
    scope:Spawn(function()
        print("Work began")
    end)
    scope:OnCancel(function()
        print("Cleanup")
    end)
end
```

`cancelScope()` is lowered into a small helper **only if a call appears in the source**. The scope object implements:

| Method | Behavior |
| --- | --- |
| `scope:Spawn(callback)` | Uses `task.spawn`, records the created thread, and returns the thread (or `nil` if already cancelled). |
| `scope:OnCancel(callback)` | Registers cleanup; if already cancelled, runs the callback immediately. |
| `scope:Cancel()` | Idempotently marks cancelled, attempts to cancel tracked threads, and invokes cleanups in reverse registration order. |
| `scope:Dispose()` | Alias for `Cancel()`, enabling `using` cleanup. |

The implementation wraps `task.cancel` and registered cleanup execution in protected calls. A cleanup that throws does not necessarily stop subsequent cleanup callbacks; investigate unexpected errors in your own cleanup functions.

### 11.2 Ownership and lifetime

- If you write `using scope = cancelScope()` **inside a function**, existing Laua `using` behavior disposes it when that function exits.
- If work must survive the function return, hold the scope outside that function and call `scope:Cancel()` when the owning object is destroyed or a player leaves.
- `scope:Spawn(fn)` tracks the spawned thread, but existing independent async work is **not** automatically registered with the scope.
- A callback should cooperate with cancellation; blocking native/yielding operations and non-tracked async/await chains are outside the current automatic-propagation model.

This is foundational cancellation/lifecycle support, **not** full structured concurrency or automatic propagation through nested promises.

---

## 12. Multi-file project transpilation (v3.41)

### 12.1 CLI

```sh
node project-transpiler.cjs ./src ./out Compact
```

Usage:

```text
node project-transpiler.cjs <input-folder> <output-folder> [Compact|Readable]
```

The third argument defaults to `Readable`. The command walks input subfolders, transpiles `.laua` files, and writes corresponding `.luau` and `.luau.map.json` outputs in the output tree.

Example input:

```text
src/
  common/
    Counter.laua
  main.laua
```

Example output:

```text
out/
  common/
    Counter.luau
    Counter.luau.map.json
  main.luau
  main.luau.map.json
```

The project tool orders dependencies before consumers, rejects imports outside the project root, and checks known imports/exports and cycles. **Import references still require a matching Roblox ModuleScript hierarchy at runtime.**

### 12.2 JavaScript API

```js
const {transpileProject} = require('./project-transpiler.cjs');

const result = transpileProject({
    'common/Math.laua': 'export function Double(n: number): number\n    return n * 2\nend',
    'main.laua': 'import {Double} from "./common/Math"\nprint(Double(10))'
}, {OutputStyle: 'Compact'});

console.log(result.order);
console.log(result.files['main.luau']);
console.log(result.sourceMaps['main.luau.map.json']);
console.log(result.stats);
```

`transpileProject(files, options?)` returns an object with:

- `files`: generated `.luau` text keyed by project-relative output path.
- `sourceMaps`: `*.luau.map.json` mapping objects, keyed by generated path plus `.map.json`.
- `order`: `.laua` input paths in dependency-first order.
- `stats`: total input and output source bytes.

The project tool also exports `verifiedLineMap`, `originalLocation`, `remapStackTrace`, and `LauaProjectError`.

### 12.3 Analysis scope

Current multi-file checks include missing modules, unexported named imports, cycles, and known direct calls/fields on imported top-level exported functions or instantiated classes. They do **not** constitute a complete multi-module type solver. Unsupported cases include arbitrary deeply nested expressions, all dynamic imports, generically instantiated cross-file types, arbitrary closure aliases, and all possible re-export/inheritance patterns.

For errors, the project tool uses codes such as `LAUA_IMPORT_NOT_FOUND`, `LAUA_IMPORT_EXPORT`, `LAUA_IMPORT_CYCLE`, `LAUA_IMPORT_MEMBER`, `LAUA_IMPORT_TYPE`, and `LAUA_IMPORT_ARITY`. Use the error code, filename, and source location when reporting a regression.

---

## 13. Source maps and error reporting (v3.41)

### 13.1 Sparse line mappings

A project build emits line-based maps under names such as `main.luau.map.json`. A generated line is mapped only if it matches a source line **exactly**, is not ambiguous, and preserves source order. Synthesized or transformed lines are deliberately `null` rather than being assigned an invented source line.

This conservative approach is especially important for code expanded from `class`, `schema`, and other Laua constructs. A single Laua line can become many Luau lines; the current project tool does **not** supply reliable character-level maps of such generated regions.

### 13.2 Mapping APIs

```js
const {originalLocation, remapStackTrace} = require('./project-transpiler.cjs');

// sourceMaps comes from transpileProject(...).sourceMaps.
const original = originalLocation(sourceMaps, 'main.luau', 12);
// Returns {file: 'main.laua', line: N} when an exact safe mapping exists,
// or null when the generated line is unmapped.

const readableStack = remapStackTrace('main.luau:12: error', sourceMaps);
```

`remapStackTrace` operates on a **string supplied to it**. It doesn't automatically subscribe to Roblox Studio runtime errors or rewrite every stack trace; unmapped locations are unchanged. Path matching and line syntax must match the map keys and supported stack format.

### 13.3 Static diagnostics

The standalone and browser JavaScript implementations can report selected malformed expressions, invalid types, unknown members, incorrect known function/constructor calls, invalid namespace or enum uses, invalid class contracts, and project-import errors.

In v3.40, semantic diagnostics were expanded to include selected typed fields, arrays, nested tables, parameter assignments, return expressions, operators, aliases, and more. Source offsets and browser error-marker locations were improved, including the earlier class/namespace use-site underline bugs. **This still is not a full AST/CFG type checker**, and the native implementation does not have complete semantic parity.

---

## 14. Output efficiency and performance

### 14.1 Existing optimizations

Laua v3.46 retains optimizations from earlier releases and adds the v3.45 class-output changes:

- **No unused runtime families:** shared core and async helpers are injected only when source code requires them, with selective helper insertion where supported.
- **Feature-selective class lowering (v3.45):** Classes and known inheritance chains only emit getter, setter, lazy, watcher, abstract and final infrastructure when required. Inherited accessors retain needed dispatch; unknown/external parent types use conservative behavior.
- **Static exhaustive checks:** `match exhaustive` requires no extra runtime helper beyond existing match lowering.
- **Cancellation helper injection:** `cancelScope()` helper code is only emitted when its call syntax is used.
- **Conservative output formatting:** `OutputStyle: 'Compact'` removes selected unnecessary whitespace/comments, not arbitrary syntax.

Do not remove class field initializers simply because a later constructor assignment overwrites them: a field initializer may call a function, trigger a setter/watch, or otherwise have observable behavior.

### 14.2 Benchmark interpretation

The package includes benchmark output files and test scripts for synthetic source size/timing. The release records transpilation of a 100,000-line synthetic program in the JavaScript environment, but those results only measure **transpilation throughput**. They do **not** establish Roblox client/server runtime speed or memory usage for generated code.

Use `compilationStats(input, output)` for source/output byte and line comparisons. Benchmark representative real projects separately, and compare behavior before optimizing code with side effects.

---

## 15. Static diagnostics and limitations

### 15.1 `const` and semantic preflight notes

The v3.46 editor includes `const` in its syntax registry and applies selected reassignment lint checks. The standalone transpiler preserves some `const` declarations in the emitted source; it does **not** replace those tokens with `local`. Because the native Studio execution and complete `const` semantics were not verified in this release, review the output with the target Luau tooling rather than equating syntax highlighting or linting with guaranteed runtime enforcement.

Likewise, the browser and JavaScript semantic passes are conservative, not a complete control-flow or whole-project type checker. `SemanticCheck: false` can bypass selected semantic preflight errors; it does not fix invalid grammar or guarantee runnable generated Luau. Do not disable it as a blanket workaround in production.

**v3.46 class diagnostics:** Statically resolved instance-method calls require receiver forwarding (`object:Method()` or `object.Method(object)`); omitting `self` with `object.Method()` raises a diagnostic. Known inherited getter/setter-versus-method collisions also produce errors. Some dynamic aliases and runtime-only class relationships remain beyond these checks.

**v3.46 reserved identifiers:** The source rejects user bindings that collide with generated runtime names such as `Promise`, `Promises`, `LauaPromiseStatus`, `LauaPackedValues`, `LauaPromiseState`, `LauaCore`, and `__laua`-prefixed names. Rename those bindings; this policy is specific to the current implementation.

### 15.2 Known syntax boundaries

The current transpiler combines token-aware validation with source-level transforms. It is **not** a complete AST-based parser/control-flow type system. In particular:

- Deeply nested/ambiguous expression forms and unusual long literals can expose transformation or analysis gaps.
- `match` cannot produce a value as a general expression; exhaustive checking is limited to known enum/boolean cases.
- Schema declarations do not have unions/maps/defaults/generics or built-in range/size checks.
- Custom `network` and `signal` declarations were removed in v3.46; use Roblox APIs directly.
- `cancelScope()` does not automatically track every async/await operation.
- Source maps omit rewritten lines and have no full column-level mapping.
- Project-wide analysis doesn't completely resolve complex module scopes, imports, or types.
- Static modifier enforcement (`private`, `protected`, `final`) is not a security boundary.
- Native transpiler execution and real Roblox Studio runtime behavior were not verified in this release.

Existing Luau generics, unions, `type` aliases, Roblox API types, and Luau Script Analysis remain important tools; the Laua analyzer does not replace them.

### 15.3 Avoid assuming nonexistent syntax

Not available as **general, complete** Laua features in this package: interfaces/traits, unrestricted named arguments, labeled multi-loop `break`/`continue`, full generic/union exhaustiveness, nested destructuring defaults, arbitrary spread expressions, full AST optimizations, automatic client/server remote creation, and automatic cancellation propagation through unrelated promises.

Do not infer a feature's existence from another language's syntax or from a playground syntax-highlight token.

---

## 16. Testing and release verification

### 16.1 Run the release suites

From the extracted v3.46 release root:

```sh
node --check compiler.js
node --check project-transpiler.cjs
node tests/release-integrity.cjs
node tests/feature-retirement-v346.cjs
node tests/class-calls-v346.cjs
node tests/memo-and-reserved-v346.cjs
node tests/lean-class-v345.cjs
node tests/nested-auto-end-v345.cjs
node tests/features-v341.cjs
node tests/stress-v341.cjs
node tests/runtime-v341.cjs
node tests/semantic-v340.cjs
node tests/correctness-v339.cjs
node tests/inheritance-v338.cjs
node tests/deep-inheritance-v338.cjs
node tests/v337-smoke.cjs
node tests/semantic-v336.cjs
node tests/semantic.cjs
node tests/editor-markers.cjs
node tests/expanded-stress.cjs
```

`tests/runtime-v341.cjs` uses the `luatex` executable for **Lua 5.3 compatibility runtime tests**; it is optional when that executable is unavailable. Those tests are not native Luau/Studio execution.

### 16.2 Recorded v3.46 verification

The v3.46 package's `V346_VALIDATION.md` reports:

| Test group | Recorded result |
| --- | ---: |
| Executable Node test scripts | **23 passed** |
| Expanded transpiler stress cases | **4,249 / 4,249** |
| Custom keyword retirement checks | **62** |
| Class-call, inherited accessor collision and location assertions | **1,738** |
| Memo-cache clearing and reserved-name assertions | **645** |
| Cross-feature diagnostic assertions | **8,683** |

The package also records JavaScript/website transpiler parity and HTML inline-script syntax checks. These are **recorded automated test results**, not a claim of full native Luau or Roblox Studio execution parity. Historic test filenames such as `features-v341.cjs` remain, but obsolete feature assertions have been updated.

### 16.3 Native Studio validation remains necessary

Before shipping a generated game module:

1. Transpile the same fixtures with standalone JavaScript and the **native** ModuleScript; compare semantics and diagnostics.
2. Run Roblox Studio **Script Analysis** on generated Scripts and ModuleScripts.
3. Test inherited properties, async cleanup, optional access, memo caches and class-call validation on representative generated code.
4. Independently test ordinary Roblox RemoteEvents from untrusted clients, including wrong types, negative/extreme values, repeated calls and unauthorized requests.
5. Verify ModuleScript `require` paths, event names, and connection cleanup manually in Studio.
6. Run generated output under representative real-game workloads; compare size, memory, and runtime behavior.

Do not describe a feature as Studio-verified until it has actually been run there.

---

## 17. Troubleshooting and production checklist

### “The source transpiles, but Roblox reports a syntax error”

Inspect the generated `.luau`, not only the original `.laua`. Run Studio Script Analysis. Source-level transformations may emit unsupported patterns; review preserved syntax such as `const` against the target toolchain. If possible, build a minimal reproduction and record both the source and output.

### “Why isn't custom `network` or `signal` syntax recognized?”

Those Laua features were retired in v3.46. Use standard Roblox `RemoteEvent`, `BindableEvent`, and `RBXScriptSignal` APIs. Older v3.41 examples do not apply to this release.

### “Why is `obj.Move()` rejected?”

An instance method expects `self`; call `obj:Move()` or supply it explicitly as `obj.Move(obj)`. A static class method is different and can use `Class.Method()` without an instance receiver.

### “How do I clear cached `memo` results?”

Call `memo.clear(MyMemoizedFunction)` to clear one cache, or `memo.clear()` to clear all memoized caches in the same script. Clearing a cache keeps the function callable and its next call recomputes results.

### “Why did my schema accept an unexpected field?”

Extra keys are intentionally accepted by the current `schema` implementation. Add your own strict allowed-key and domain-specific validation when needed. A valid type does not imply an authorized action.

### “Why doesn't cancellation stop all my async work?”

Only threads started through `scope:Spawn()` are tracked by the current cancellation helper. Track non-scope resources explicitly and make callbacks cooperate. `using` disposes a scope when its enclosing function exits, which can happen earlier than the lifetime you intended.

### “Why is there no original source line in the map?”

The generated line was likely transformed or synthesized. The sparse mapper deliberately leaves such lines unmapped rather than returning a misleading source location.

### “Why does a class or namespace error point somewhere unexpected?”

v3.40 improved browser markers and many use-site diagnostics, but complex cases can still have limited source-span support. Report the exact error code, line/column, relevant source, and generated output; the project analyzer is conservative.

### Recommended release discipline

Keep the `.laua` files in version control, deploy only generated `.luau` to execution contexts, keep the playground and standalone JavaScript cores aligned, verify native behavior before relying on native-only code, and maintain regression tests for every reported syntax or runtime failure. Keep all trusted game decisions on the server: **never trust the client**.

---

**Current documented release:** v3.46. **Next regular update:** v3.47. This documentation update does not itself modify any transpiler implementation.
