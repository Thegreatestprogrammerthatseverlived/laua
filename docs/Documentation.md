# Laua Documentation — v3.37

**Laua** (pronounced *Lawah*) extends [Roblox Luau](https://luau.org/) with classes, signals, async functions, pattern matching, safe access, and additional syntax. Laua is a **source-to-source transpiler**: it produces Luau code for Roblox, not a separate game engine or VM.

This reference targets the **v3.37 release package (October 12, 2026)**, not the older v3.9 documentation. It describes implemented syntax and the limits of the current compiler. For a searchable list of 35 Laua syntax words recognized by the playground, see [KEYWORDS.md](KEYWORDS.md). That list includes contextual words and editor-recognized tokens, **not 35 globally reserved keywords**.

> **Verification status:** The shipped v3.37 package passes its Node.js JavaScript compiler and embedded-playground parity suites. The native Luau ModuleScript has only been checked structurally in that package; it has **not** been executed in Roblox Studio. Passing transcription and static checks does not establish that every generated script passes Studio Script Analysis or behaves correctly at runtime.

## Contents

1. [Getting started](#1-getting-started)
2. [Classes, inheritance and visibility](#2-classes-inheritance-and-visibility)
3. [Signals and asynchronous programming](#3-signals-and-asynchronous-programming)
4. [Namespaces, enums, imports and exports](#4-namespaces-enums-imports-and-exports)
5. [Control flow and expressions](#5-control-flow-and-expressions)
6. [Collection and function syntax](#6-collection-and-function-syntax)
7. [Compiler controls and diagnostics](#7-compiler-controls-and-diagnostics)
8. [Playground and Studio workflow](#8-playground-and-studio-workflow)
9. [Unsupported syntax and known limits](#9-unsupported-syntax-and-known-limits)
10. [Tests and verification](#10-tests-and-verification)

## 1. Getting started

### Source files and output

Write Laua in `.laua` files and transpile it to `.luau` before execution. Regular Luau syntax, including types, generics, attributes, `for ... in` loops, `--!strict`, standard Roblox APIs, and ordinary `self` method parameters, can be used alongside Laua extensions.

The native compiler is a **single ModuleScript** stored in the repository at [`transpiler/transpiler.luau`](../transpiler/transpiler.luau). Its public entry point is `Transpiler.Transpile(source, options)`. It returns a **string containing Luau source**; it does not run the result.

```luau
local Transpiler = require(script.Parent.transpiler)
local source = [[
class Counter
    Value = 0

    function Increment()
        self.Value += 1
    end
end

local counter = new Counter()
counter:Increment()
print(counter.Value)
]]

local generated = Transpiler.Transpile(source, {Mode = "Development", OutputStyle = "Readable"})
print(generated)
```

The `source` example above is a string passed to the transpiler; `class` and `new` must **not** be pasted directly into a regular Roblox Script without compilation.

The package also contains a standalone Node/VS Code-oriented `compiler.js` with:

```js
const {transpile, compilationStats} = require('./compiler.js');
const luau = transpile('local result = nil ?? 25');
console.log(luau);
```

The website's `playground.html` is a self-contained HTML file with an **embedded** JavaScript compiler. The v3.37 release ZIP labels that file `index.html`. The native Luau and JavaScript implementations are separate: do not assume that updating one automatically updates the others.

### Compiler options

| Option | Values | Default | Effect |
| --- | --- | --- | --- |
| `Mode` | `"Development"`, `"Debug"`, `"Release"` | `"Development"` | Chooses `--#if` compile-time branches. |
| `OutputStyle` | `"Readable"`, `"Compact"` | `"Readable"` | Compact removes safe blank lines/comments; it does **not** mean full minification. |
| `SemanticCheck` | `true`, `false` | `true` | `false` disables part of the name/member/type preflight. Syntax checks still run. |

`SemanticCheck = false` is a compatibility/debugging escape hatch, **not** a guarantee of valid code. Use the default for new projects. Invalid mode/style names throw compiler errors. `--!strict` is a **Luau directive**, not a compiler option, and emitted source still needs Studio type checking.

### Generated runtime

Newly generated files are self-contained: when a feature needs one, the compiler embeds the relevant Laua Async, Core, or Signal runtime. Unused runtime families are omitted and selected Core helpers can be omitted individually. You do **not** need separate `LauaAsync`, `LauaCore`, `LauaSignal` ModuleScripts or third-party signal packages for newly generated output. Old already-compiled files that import those modules should be recompiled before the older modules are deleted.

## 2. Classes, inheritance and visibility

### `class`, `constructor`, `new` and `self`

```luau
class PlayerData
    Health: number = 100
    Name: string = "Player"

    constructor(name: string)
        self.Name = name
    end

    function TakeDamage(amount: number)
        self.Health -= amount
    end
end

local player = new PlayerData("Alex")
player:TakeDamage(25)
print(player.Health)
```

Methods use Luau's **`self`**, not `this`. Define instance functions inside the class and call them with `:`. `new PlayerData(...)` creates an instance; classes without required arguments also accept `new PlayerData`. Fields may include Luau type annotations. Laua lowers classes to Luau tables, metatables and constructors.

### Inheritance, `extends`, `super`, `override`

```luau
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
        return super:Describe()
    end
end

local zombie = new Zombie("Runner")
print(zombie:Describe())
```

`super(...)` invokes the inherited initializer on the current instance. `super:Method()` invokes an inherited method. Put an explicit parent constructor call near the start of the child constructor. The compiler has checks for known inheritance and override contracts, but it is **not** a complete class type system.

### Visibility, static members and modifiers

```luau
abstract class BaseEnemy
    protected Health = 100

    abstract function Move()
    end
end

class Enemy extends BaseEnemy
    private Token = "hidden"
    public Name = "Enemy"
    static Count = 0

    override final function Move()
        print(self.Name)
    end
end
```

| Modifier | Use | Important limitation |
| --- | --- | --- |
| `public` | Public class member | Access is ordinary Luau member access. |
| `private` | Member intended for defining class | The v3.37 compiler checks some known illegal accesses, but it is **not a security boundary**. |
| `protected` | Member intended for class/subclasses | Same caveat; dynamic aliases and external Luau can bypass static checks. |
| `static` | Field/method on class table | Access through the class, e.g. `Enemy.Count`. |
| `abstract` | Abstract class or method | Intended to require subclass implementation. |
| `final` | Prevent subclassing/overriding at recognized sites | Not a universal protection against Luau table mutation. |
| `override` | Declare inherited method replacement | Compiler can reject selected incorrect overrides. |

Avoid using an abstract class as a concrete instance. None of the class modifiers make client-side game state secure; enforce important behavior on the server.

### Computed and observed properties

```luau
class HealthState
    Health = 100
    lazy Inventory = {"Bandage"}

    get IsAlive()
        return self.Health > 0
    end

    set NewHealth(value: number)
        self.Health = math.max(0, value)
    end

end
```

`get` reads like a property, `set` reacts to property assignment, and `lazy` evaluates and caches an initializer on first access. Getters accept no parameters and setters take exactly one. Do not give a computed property and stored field the same name.

The `watch` syntax observes writes to a property:

```luau
class WatchedHealth
    Health = 100
    watch Health(previous, current)
        print(previous, current)
    end
end
```

**v3.37 issue:** The default JavaScript semantic preflight incorrectly diagnoses some valid watcher declarations as `Unknown function 'Health'`. For such a declaration, `SemanticCheck = false` allows the lowering step to proceed, but you must verify its behavior and types in Studio. This is a known preflight bug, not a guarantee that every watcher is runtime-correct. Watchers are not a replacement for Roblox replication.

### Custom operators and `is`

```luau
class Amount
    Value = 0

    constructor(value: number)
        self.Value = value
    end

    operator +(other)
        return new Amount(self.Value + other.Value)
    end
end

local a = new Amount(4)
local b = new Amount(6)
print((a + b).Value)
print(a is Amount)
```

`operator` maps supported symbols to Luau metamethods. `is` tests membership in Laua class hierarchies using an embedded helper. It does **not** replace Roblox `Instance:IsA()` and does not provide general Luau type narrowing.

## 3. Signals and asynchronous programming

### Class signals

```luau
class HealthTracker
    signal Damaged(amount: number, reason: string?)

    function Damage(amount: number)
        self.Damaged:Fire(amount, nil)
    end
end

local tracker = new HealthTracker()
local connection = tracker.Damaged:Connect(function(amount, reason)
    print("Damage:", amount, reason)
end)
tracker:Damage(10)
connection:Disconnect()
```

Signals are original **pure-Luau** per-instance event objects. They are **not** `BindableEvent`, GoodSignal, or RemoteEvents. APIs are `:Connect(callback)`, `:Once(callback)`, `:Fire(...)`, `:Wait()`, connection `:Disconnect()`, and signal `:Destroy()`. A declaration such as `signal Damaged(amount: number)` carries runtime argument checks for simple types and counts; `?` allows `nil`. `:Fire` schedules connected callbacks using `task.spawn`, so do not assume callbacks run synchronously before `:Fire()` returns. Waiters can yield until the next firing. Destroyed signals reject new operations as appropriate and resume waiting coroutines with an error. **Signals never replicate automatically** between server and clients.

### `async` and `await`

```luau
async function FetchHealth()
    task.wait(0.1)
    return 100
end

async function Run()
    return await FetchHealth()
end

Run():andThen(function(value)
    print(value)
end):catch(function(err)
    warn(err)
end)
```

An `async function` returns a Promise-like object. `await` suspends inside asynchronous work and propagates failures; it also supports waiting on Laua signals in supported contexts. The embedded Async runtime exposes `Async.run` internally. Async work is coroutine-based, **not CPU parallelism**. Use care with cancellation, errors and multi-return behavior when integrating other Promise libraries.

### Cleanup with `defer` and `using`

```luau
local function Listen()
    using connection = game:GetService("RunService").Heartbeat:Connect(function(delta)
        print(delta)
    end)

    defer
        print("Done listening")
    end

    task.wait(1)
end
```

`defer` registers a block to run when the enclosing **function** exits; cleanup runs in reverse order and also runs on errors. `using name = expression` creates a resource and schedules supported cleanup (`Disconnect`, `Destroy`, or `Dispose`). It does not close the resource at the end of each nested `do` or `if` block. Avoid holding event connections beyond the function without explicitly managing their lifetime.

## 4. Namespaces, enums, imports and exports

### `namespace`, including direct return

```luau
namespace MathTools
    Value = 10

    function Double(value)
        return value * 2
    end
end

print(MathTools.Value)
print(MathTools.Double(5))
```

A namespace compiles to a Luau table in a `do` block, with exported fields and namespace functions. `local function` inside a namespace stays internal. In v3.37, a namespace may be **standalone or directly returned** from a function:

```luau
local function CreateAPI()
    return namespace API
        Version = 337
    end
end
```

Do not use `local api = namespace API ... end` as an expression; that form is unsupported. The v3.37 rewrite eliminates an older IIFE in basic namespace output.

### `enum`

```luau
enum State
    Idle
    Running
    Dead
end

print(State.Running) -- 1
```

Enums become frozen Luau tables. Auto-numbered members start at **0**. You may set explicit values:

```luau
enum Example
    First
    Custom = 10
    Next
end
-- First = 0, Custom = 10, Next = 1 in v3.37
```

**Important:** Explicit enum values **do not advance the auto-number counter** in the v3.37 JavaScript compiler. Avoid assuming `Next` will be `11`; use explicit values if the numbering must be exact.

### Modules: `import`, `export`, `from`, `as`, and lazy imports

One module:

```luau
export class Zombie
    Health = 100
end

export function StartingHealth()
    return 100
end
```

Another module:

```luau
import {Zombie, StartingHealth as GetHealth} from "./Zombies"
local health = GetHealth()
```

Named exports produce a return table. Named imports read fields from that table; `import ZombieModule from "./Zombies"` imports the entire return value. Paths must begin with `./` or `../` and resolve relative to the compiled Script's parent hierarchy. The transpiler emits `require()` and `:WaitForChild()` calls, so the corresponding ModuleScripts must exist in Studio. For a deferred module load, use `import lazy Registry from "./Registry"`; this creates a lazy proxy and **does not guarantee safe arbitrary cyclic imports**. Normal Luau `export type` is not the same as Laua value exports.

## 5. Control flow and expressions

### `match`, `case`, `default`

```luau
local status = {Health = 0}
match status
    case {Health = 0}
        print("Dead")
    case {Health = 100}
        print("Full")
    default
        print("Other")
end
```

`match` evaluates its scrutinee once, walks cases in order, and supports selected nested table patterns and `if` guards. Patterns are intentionally limited: no array destructuring patterns, capture variables, exhaustive enum analysis, or expression-returning `match`.

### Optional chaining `?.`

```luau
local character = nil
local hp = character?.Humanoid?.Health
local object = nil
local value = object?.["Health"]
local result = object?.:GetValue()
```

When the receiver is `nil`, optional property, index, call or method access returns `nil`. `object?.Method()` is a **dot-style call** without implicit `self`; `object?.:Method()` passes the receiver as `self`. `object?.(args)` is supported for some optional callable expressions. When the receiver is `nil`, optional key expressions and call arguments are skipped. The Core optional helper also handles Roblox Instances; the transformer does not make arbitrary wrong property names safe on non-nil receivers.

### Nil coalescing `??` / assignment `??=`

```luau
local coins = nil
local saved = coins ?? 50

local enabled = false
enabled ??= true -- still false
```

Only `nil` triggers the fallback, not `false`. Simple safe cases lower to Luau's `if` expression; more complex cases can use a helper. Some nested expressions and assignment targets are not supported by the current source-level transformer.

### Early-return postfix `?`

```luau
local function Read(input)
    local value = input?
    return value
end
```

This limited suffix form becomes `local value = input` followed by `if value == nil then return end`. It applies to **single-name `local`/`const` assignments on a line**, not general nested expressions. Do not confuse it with `?.`, `??`, optional types, or the conditional `if ... then ... else ...` expression already available in Luau.

### Compile-time branches

```luau
--#if DEBUG
print("Debug build")
--#else
print("Other build")
--#end
```

The compiler uses `Mode` (`Debug`, `Development`, or `Release`) to decide which branch to emit. Branches may nest; unknown flags, missing ends and duplicated `--#else` cause errors. This is a compile-time source preprocessor, not Lua runtime conditionals.

## 6. Collection and function syntax

### Destructuring

```luau
local data = {Health = 90, Speed = 16}
local {Health, Speed: WalkSpeed} = data
print(Health, WalkSpeed)
```

Single-level named-field destructuring evaluates the source once. Renaming uses `field: localName`. Nested/array destructuring and default values in patterns are not implemented.

### Spread expressions

```luau
local first = {1, 2}
local second = {3, 4}
local joined = {...first, ...second}
```

The supported spread literal is **spread-only**: `{...name, ...otherName}` (simple dotted receivers are also supported). It copies array items and named keys. Mixed `{"a", ...other}` and arbitrary spread expressions are not generally supported. Native Luau vararg `{...}` remains distinct.

### Slices

```luau
local word = "Compiler"
local first = word[1:4]
local last = word[-3:-1]
```

Laua slices use 1-based inclusive bounds, with negative indices measured from the end. String and buffer slicing are supported by the embedded Core helper. The receiver must be a simple name or dotted path; bounds must currently be integer literals (or one omitted bound), not arbitrary expressions.

### Higher-order table helpers

```luau
local values = {2, 4, 6}
local doubled = table.map(values, function(value)
    return value * 2
end)
local positive = table.filter(values, function(value)
    return value > 0
end)
local sum = table.reduce(values, function(total, value)
    return total + value
end, 0)
local found = table.findWhere(values, function(value)
    return value == 4
end)
```

These named calls are rewritten to **embedded Laua Core helpers**, not added to Roblox's global `table` library. `map`, `filter`, and `findWhere` callbacks take `(value, index)`, while `reduce` takes `(accumulator, value, index)`.

### Arrow functions `=>`

```luau
local double = (x) => x * 2
print(double(3))
```

This is a **one-line, one-expression** function body. Multiline arrow bodies and some deeply nested expression forms are unsupported.

### Default parameters

```luau
local function Damage(amount: number = 10)
    return amount
end
```

A missing or `nil` argument uses the default. Default expressions may include nested table/call arguments in supported signature forms, but this is still a source-level rewrite, not a full function-grammar implementation. Verify generated typing in Studio for more complex annotations.

### `memo` function caching

```luau
memo function Square(x)
    return x * x
end
```

`memo` wraps a named function with a tuple-preserving memoization helper. Results are cached by argument identities/values, including `nil` in returned tuples. No built-in invalidation or cache-size bound exists; don't use it for time-dependent or side-effectful computations. **Known issue:** v3.37 can omit the newline between a generated memo wrapper and a statement immediately following the function. Inspect generated output and use caution before shipping memoized functions.

### `inline` specialization

```luau
inline function AddOne(x)
    return x + 1
end

print(AddOne(5))
```

`inline` is **conservative**: the top-level function must have zero or one parameter and return a constant, its parameter, or simple parameter arithmetic with a numeric literal. Complex functions, mutation, or type annotations can prevent specialization or result in an error. A function declaration may remain in the generated output. This is not a general optimizer.

### Pipeline `|>`

```luau
local function Double(x)
    return x * 2
end
local result = 5 |> Double |> tostring
```

Pipelines are currently **single-line** assignment/return constructs where each stage is a named function (also `math.abs`-style dotted names). They are lowered to nested calls; arbitrary expressions or multiline pipelines are not guaranteed.

### `const` status

The editor's syntax list contains `const`, and the limited `const name = value?` early-return syntax can be lowered to `local`. **However, plain `const name = value` is currently emitted unchanged by the v3.37 JavaScript transpiler.** It is not a reliable immutable variable declaration and is **not valid ordinary Luau syntax**. Use `local` for normal variable declarations until a complete `const` lowering/immutability feature is implemented.

## 7. Compiler controls and diagnostics

### Lint suppression

```luau
@nolint("UnusedLocal")
local unusedValue = 10
```

`@nolint("WarningName")` is intended to control an appropriate **playground diagnostic**, not the compiler's semantic correctness. It is replaced with a comment in generated source. **Known v3.37 bug:** the default JavaScript semantic preflight can incorrectly reject this syntax as `Unknown function 'nolint'`; `SemanticCheck = false` allows it through, at the cost of skipping other semantic checks. It cannot make an invalid program valid, silence missing members, or replace Luau Script Analysis. Standard Luau directives such as `--!strict` remain separate.

### Errors the compiler can catch

The v3.37 semantic/syntax preflight rejects selected cases such as:

```luau
local x = 5 + * 3 -- malformed expression
```

```luau
class Player
    function Damage(amount: number)
        print(amount)
    end
end
local player = new Player()
player:Heal(10) -- unknown method on a known class
```

Also tested: undeclared simple variables/functions, some out-of-scope local references, incorrect known method/constructor argument counts or primitive literal types, missing enum/namespace members, selected invalid signal arguments, mismatched separators and bracket structures. **This is not a complete AST parser, name resolver, type checker, source-map generator, or Roblox API type analyzer.** Dynamic `require()` results and arbitrary Instance APIs need normal Studio checks.

`SemanticCheck = false` relaxes part of these semantic errors for legacy compatibility; it is not an opt-out from all syntax checking.

## 8. Playground and Studio workflow

The website at [laua.dev](https://laua.dev) hosts the playground. In the repository, the published single-file HTML is `playground.html` (named `index.html` in the v3.37 package). The playground contains the JavaScript compiler internally and supports Monaco editing, syntax highlighting, diagnostics, autocomplete, generation/copying of `.luau`, output style and mode selection, and a **multi-file project workspace**.

The v3.37 HTML also includes compiled `.rbxmx` project export, **editable Studio `.rbxmx` export**, project `.rbxmx` import, project files, comparison/statistics tools and built-in tests. A compiled-only export is for generated Lua source; the editable Studio export is for retaining source as well. Verify both versions of a project before replacing your originals, and don't assume Roblox Studio will interpret `.laua` directly.

Suggested workflow:

1. Write and save `.laua` files.
2. Transpile every source file, preferably with `SemanticCheck` enabled and `OutputStyle = "Readable"`.
3. Inspect compile diagnostics and generated output; don't treat a lack of warnings as proof of correctness.
4. Keep source `.laua` files under version control alongside compiled `.luau` files or an editable project export.
5. Run Roblox Studio Script Analysis on generated source, then execute tests in the correct server/client context.

The Studio plugin (separately versioned) can refresh its native compiler from `transpiler/transpiler.luau` on GitHub. The plugin, website compiler and any VS Code extension must all match your chosen Laua release; refreshing one does not silently synchronize the others. Evaluate plugin permissions and downloaded code before enabling automatic updates.

## 9. Unsupported syntax and known limits

**Not implemented as full language features in v3.37:** labeled `break`/`continue`, constrained generic enforcement, nominal `unique type`, tuple-like positional typed tables, truthy/falsy types, a full regex library, mixins/`derive`, general named arguments, expression-returning `match`, captured/array match patterns, and exhaustive pattern checking. Plain `const` lowering/immutability is incomplete.

Additional important limits:

- Source rewrites are partly regex/token-based, not a complete lexer/AST pipeline. Complex nested expressions, scopes, and long literals can expose unsupported cases or incorrect transformations.
- The compiler's semantic checker is conservative and incomplete. Some valid complex Luau and some invalid programs may slip through or trigger false positives. A warning-free compile is not full type safety.
- Type checks focus on known symbols and simple types/literal arguments; they do not replace Studio's Luau type checker, Roblox API information, generic inference, or user-defined dynamic modules.
- `private`/`protected` are not security protection; signals and local async work do not replicate to clients.
- Compiled code may require validation of `--!strict` typing, timing/yield behavior and runtime helper interactions in Studio.
- The generated memo-wrapper newline issue described above is a known v3.37 case.
- The JavaScript semantic preflight can incorrectly flag `watch Name(...)` and `@nolint(...)` under its default settings. Do not mistake these for unsupported syntax, and do not disable semantic checks globally without separately verifying generated output.
- **Never trust the client:** keep authorization, currency, inventories and other sensitive game decisions server-side regardless of Laua syntax.

## 10. Tests and verification

The v3.37 release ZIP includes these commands. Run them from its extracted root using Node.js 18+ (its recorded verification used Node.js 22):

```bash
node --check compiler.js
node tests/release-integrity.cjs
node tests/v337-smoke.cjs
node tests/semantic-v336.cjs
node tests/expanded-stress.cjs
node tests/editor-markers.cjs
node tests/semantic.cjs
```

The shipped test baselines are **438** v3.37 targeted compiler/browser checks, **737** semantic/literal checks, **4,249** expanded cases, and separate editor/semantic/integrity suites. Those are distinct suites; don't treat static native structural checks as native execution. The ZIP includes `Studio-Verification.luau` for manual use with the native ModuleScript in Studio, but **Studio execution was not established by the package**.

If a compiler output looks suspicious, minimize the failing `.laua` file, record the expected behavior and actual emitted `.luau`/error, and test it against the standalone JS compiler, embedded website compiler and native Luau transpiler. Publish all changed implementation targets together for language changes. Documentation-only edits such as this reference **do not change the language version**.

---

**Related:** [Keyword reference](KEYWORDS.md) · [Repository](https://github.com/Thegreatestprogrammerthatseverlived/laua) · [Playground](https://laua.dev)
