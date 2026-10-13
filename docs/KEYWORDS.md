# Laua Keywords and Syntax Words — v3.41

Laua (*Lawah*) transpiles `.laua` source into Roblox `.luau`. This reference covers the **40 distinct Laua-specific syntax words** present in the v3.41 website/playground list, including the five introduced in v3.41. For complete examples and rules, see [Documentation.md](Documentation.md) and [SYNTAX.md](SYNTAX.md).

> **Source and verification:** Checked against the v3.41 release's `index.html` syntax-word list, `compiler.js`, `transpiler.luau` source, `docs/V341_FEATURE_GUIDE.md`, and the v3.41 tests. The website list has **41 entries but only 40 unique spellings** because `exhaustive` occurs twice. This is a duplicate list entry, **not** a second keyword. Website/standalone JavaScript parity was tested in the release; native Luau and Roblox Studio execution were **not** verified.

## What counts as a Laua syntax word?

Many entries below are **contextual words**, not globally reserved identifiers. For instance, `constructor` belongs in a class, `from` belongs in an import, and `exhaustive` follows `match`. The syntax-highlighting list is **not** a complete formal grammar, and merely highlighting a token does not guarantee that every use of it will transpile.

Ordinary Luau (`local`, `function`, `if`, `then`, `end`, `for`, `while`, `return`, `type`, `export type`, `continue`, and Roblox APIs) is available separately and is **not** part of this inventory.

## Complete inventory — 40 unique words

The table follows the v3.41 playground list, with the newly added words marked **v3.41**.

| # | Word | Role and accepted context | Example or note |
| ---: | --- | --- | --- |
| 1 | `class` | Define a Laua class. | `class Enemy ... end` |
| 2 | `extends` | Specify a direct superclass. | `class Boss extends Enemy` |
| 3 | `constructor` | Declare a class initializer. | `constructor(name: string) ... end` |
| 4 | `private` | Declare member visibility intent. | `private Value = 0`; limited static enforcement |
| 5 | `public` | Mark a public class member. | `public Health = 100` |
| 6 | `protected` | Declare subclass-oriented member visibility. | `protected Health = 100`; limited enforcement |
| 7 | `static` | Mark a class-level method or field. | `static Count = 0` |
| 8 | `new` | Instantiate a Laua class. | `new Enemy()` |
| 9 | `namespace` | Define a named namespace table. | `namespace MathTools ... end` |
| 10 | `super` | Call an immediate parent initializer or member. | `super(...)`, `super.Move(...)` |
| 11 | `abstract` | Mark an abstract class or method. | `abstract class Entity ... end` |
| 12 | `override` | Identify an overriding inherited method. | `override function Move() ... end` |
| 13 | `enum` | Define an enum table. | `enum State ... end` |
| 14 | `final` | Restrict class extension or method override. | `final class Root ... end` |
| 15 | `get` | Define a computed getter. | `get IsAlive() ... end` |
| 16 | `set` | Define a managed setter. | `set Health(value) ... end` |
| 17 | `defer` | Run cleanup at the enclosing function's exit. | `defer ... end` |
| 18 | `using` | Register a resource for function-exit disposal. | `using scope = cancelScope()` |
| 19 | `async` | Define an asynchronous function. | `async function Fetch() ... end` |
| 20 | `await` | Wait for supported asynchronous results. | `local value = await Fetch()` |
| 21 | `match` | Start a pattern-match statement. | `match status ... end` |
| 22 | `case` | Start a match branch. | `case State.Running` |
| 23 | `default` | Declare a fallback match branch. | `default` |
| 24 | **`exhaustive`** | **v3.41:** opt in to completeness checks after `match`. | `match exhaustive state` |
| 25 | `import` | Import supported exports from a module. | `import {Value} from "./Data"` |
| 26 | `from` | Specify an import's relative source. | `from "./Data"` |
| 27 | `operator` | Define supported class metamethod operators. | `operator +(other) ... end` |
| 28 | `signal` | Define a local per-instance class signal. | `signal Changed(value: number)` |
| 29 | `lazy` | Define lazily initialized class data or lazy module import. | `lazy Cache = Create()` |
| 30 | `watch` | Define a managed-property change observer. | `watch Health(before, after) ... end` |
| 31 | `export` | Export a supported module declaration. | `export class Account ... end` |
| 32 | `as` | Rename a named import. | `import {Create as Make} from "./Module"` |
| 33 | `memo` | Define a named memoized function. | `memo function Square(x) ... end` |
| 34 | `is` | Test Laua class membership/inheritance. | `object is Enemy` |
| 35 | `inline` | Request restricted inline specialization. | `inline function Double(x) ... end` |
| 36 | `const` | Recognized declaration word with implementation limitations. | See [the `const` note](#const-declaration-caveat) |
| 37 | **`schema`** | **v3.41:** declare a runtime data-shape validator. | `schema PlayerData ... end` |
| 38 | **`network`** | **v3.41:** declare a typed RemoteEvent contract. | `network Inventory ... end` |
| 39 | **`client_to_server`** | **v3.41:** mark a client-to-server `network` function event. | `client_to_server function Buy(id: string)` |
| 40 | **`server_to_client`** | **v3.41:** mark a server-to-client `network` signal event. | `server_to_client signal Updated(id: string)` |

**Count:** 35 pre-v3.41 unique syntax words + 5 added in v3.41 = **40 unique syntax words**. The playground currently duplicates `exhaustive` at the end of its list, for 41 raw entries.

## The five new v3.41 words

### `schema`: opt-in runtime validation

```laua
schema PlayerData
    Name: string
    Health: number
    Inventory: {string}?
end

local ok, message = PlayerData.Validate({Name = "Alex", Health = 100})
local data = PlayerData.Assert({Name = "Alex", Health = 100})
```

A schema produces `.Validate(value)` returning `(boolean, string?)` and `.Assert(value)` returning the value or throwing an error. A trailing type `?` permits absence; supported field types are restricted to documented primitives, selected Roblox types, homogeneous arrays, and previously declared schemas. Fields are **one per line**. Extra fields are allowed; schemas do not check authorization, minimum/maximum values, size limits, cycles, or ownership. Generic and union schema declarations are not supported by v3.41.

### `network`, `client_to_server`, and `server_to_client`: RemoteEvent contracts

```laua
schema Purchase
    ItemId: string
    Quantity: number
end

network Inventory
    client_to_server function Buy(purchase: Purchase)
    server_to_client signal Updated(items: {string})
end

Inventory.Bind(game:GetService("ReplicatedStorage"):WaitForChild("InventoryRemotes"))
```

These declarations emit a `Bind(folder)` API and named wrappers such as `Inventory.SendBuy`, `Inventory.OnBuy`, `Inventory.SendUpdated`, and `Inventory.OnUpdated`. `Bind` caches **existing** matching `RemoteEvent` children; it does not create them. A client-to-server listener receives the `Player` first. Incoming data is validated against declared types, but the server must still check permissions, quantities, rates, balances, and game rules. The source form documented and tested for v3.41 is **`client_to_server function`** and **`server_to_client signal`**; do not assume every direction/declaration pairing is supported.

### `exhaustive`: opt-in enum/boolean coverage checks

```laua
enum State
    Idle
    Running
    Dead
end

local state: State = State.Idle
match exhaustive state
    case State.Idle
        print("Idle")
    case State.Running
        print("Running")
    case State.Dead
        print("Dead")
end
```

`exhaustive` detects missing or duplicate cases for recognized enum members and boolean subjects, including some invalid enum member references. Guarded cases require `default`; other patterns may also need a `default` when complete coverage cannot be proved. The analysis runs **during transpilation** and does not add a runtime exhaustiveness helper. It does **not** provide complete matching for arbitrary union types or nested patterns.

## Other syntax that is **not** a keyword

| Form | Role and boundary |
| --- | --- |
| `cancelScope()` | **v3.41 helper call, not a keyword.** Creates a cancellation scope with `:Spawn(fn)`, `:OnCancel(fn)`, `:Cancel()`, and `:Dispose()`. Cancellation of unrelated promises/async work is not automatic. |
| `?.`, `?.[key]`, `?.:Method()` | Optional member, index, and method access with `nil` short-circuiting. |
| `??`, `??=` | Nil-only coalescing or assignment; `false` is not treated as missing. |
| `?` in `local value = result?` | Early return for supported local/const assignment forms; distinct from optional types `T?`. |
| `=>` | One-expression arrow functions. |
| `\|>` | Supported single-line function pipelines. |
| `{...left, ...right}` | Table spread, currently limited to supported spread-only literals. |
| `text[1:3]` | Inclusive 1-based string/buffer slice, within supported receiver grammar. |
| `local {Health, Name: Label} = data` | Single-level table destructuring with optional rename. |
| `function F(x = 10)` | Default parameter values, used when the argument is `nil`/omitted. |
| `table.map`, `table.filter`, `table.reduce`, `table.findWhere` | Laua-recognized helper calls; not new standard Luau `table` functions. |
| `--#if DEBUG`, `--#else`, `--#end` | Transpilation-time branches, governed by the `Mode` option. |
| `@nolint("UnusedLocal")` | Selected lint-suppression annotation; the v3.41 JavaScript preflight can mistakenly flag it as an unknown call. |

### Native Luau words and annotations

`and`, `break`, `continue`, `do`, `else`, `elseif`, `end`, `false`, `for`, `function`, `if`, `in`, `local`, `nil`, `not`, `or`, `repeat`, `return`, `then`, `true`, `type`, `until`, and `while` are ordinary Lua/Luau syntax, **not Laua-exclusive features**. Luau directives such as `--!strict`, `--!nonstrict`, `--!nocheck`, `--!native`, and `--!optimize` are also separate from Laua keywords.

`self` is the normal instance receiver used in generated class methods: **use `self`, not `this`**. `self` is an identifier, not a new Laua language keyword. `cancelScope`, `Validate`, `Assert`, `Bind`, and `SendBuy` are generated/runtime API names, not reserved syntax words.

## Known caveats

### `const` declaration caveat

`const` already appears in Laua's syntax-word list and parts of its checking logic, but the **packaged v3.41 standalone JavaScript transpiler** may emit plain `const MAX = 100` unchanged, rather than convert it into a Luau `local` declaration. Plain `const` is not native Luau declaration syntax. This is a **v3.41 implementation discrepancy**, not a proposal to add `const` as a new feature. See [Documentation.md §15.1](Documentation.md#151-const-and-known-preflight-gaps).

### Scope and completeness limitations

- `private`, `protected`, `abstract`, `override`, and `final` can carry static and/or runtime checks, but visibility modifiers are not Roblox security boundaries.
- A `network` declaration currently has a limited grammar; certain same-file references such as `return Inventory` may be incorrectly rejected by JavaScript semantic preflight even when the generated binding exists.
- `namespace` supports a declaration and a directly returned namespace from a function; not every namespace-expression form is recognized.
- The transpiler uses source-level transformations and semantic preflight, **not** a complete AST/type solver. Diagnostics can be conservative or incomplete, especially for complex nested expressions and cross-file cases.
- The new project tool is invoked using `node project-transpiler.cjs ./src ./out Compact`; its import analysis is limited, and its line source maps leave rewritten/ambiguous lines unmapped. These are **tool features, not syntax keywords**.
- Interfaces, traits, arbitrary named arguments, fully generic schemas, and automatic creation of Roblox RemoteEvents are **not** v3.41 syntax features.

## Related documentation

- [Full documentation](Documentation.md)
- [Syntax reference](SYNTAX.md)
- `docs/V341_FEATURE_GUIDE.md` inside the v3.41 release package
- [Laua GitHub repository](https://github.com/Thegreatestprogrammerthatseverlived/laua)
- [Laua website](https://laua.dev)

**Version:** v3.41. **Terminology:** Laua is a **transpiler**, not a separate runtime. The v3.41 package does not establish native Luau or Roblox Studio execution verification.
