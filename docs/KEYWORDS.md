# Laua Keywords and Syntax Words — v3.46

Laua (pronounced **lau-wuh**) is a Luau **transpiler**. This inventory is generated from the **37 distinct names** in the v3.46 playground’s `LAUA_LANGUAGE_FEATURES` registry and checked against the shipped `playground.html`. Refer to [SYNTAX.md](SYNTAX.md) and [Documentation.md](Documentation.md) for accepted grammar and limitations.

> **Scope:** This is the Laua-specific editor/syntax vocabulary. Roblox API names, ordinary Luau words, contextual runtime helper calls, and aliases are separate. Syntax highlighting does not imply that a token is globally reserved or valid in every context. Native execution in Roblox Studio has not been verified.

## Complete inventory — 37 words

| # | Word | Meaning | Example or note |
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
| 11 | `self` | Contextual current instance inside Laua constructors and instance methods. | `self.Health = health`; not a global object |
| 12 | `abstract` | Mark an abstract class or method. | `abstract class Entity ... end` |
| 13 | `override` | Identify an overriding inherited method. | `override function Move() ... end` |
| 14 | `enum` | Define an enum table. | `enum State ... end` |
| 15 | `final` | Restrict class extension or method override. | `final class Root ... end` |
| 16 | `get` | Define a computed property getter. | `get Health() ... end` |
| 17 | `set` | Define a managed property setter. | `set Health(value) ... end` |
| 18 | `defer` | Run cleanup at the enclosing function's exit. | `defer ... end` |
| 19 | `using` | Register a resource for function-exit disposal. | `using scope = cancelScope()` |
| 20 | `async` | Define an asynchronous function. | `async function Fetch() ... end` |
| 21 | `await` | Wait for supported asynchronous results. | `local value = await Fetch()` |
| 22 | `match` | Start a pattern-match statement. | `match status ... end` |
| 23 | `case` | Start a match branch. | `case State.Running` |
| 24 | `default` | Declare a fallback match branch. | `default` |
| 25 | `exhaustive` | **v3.41:** opt in to completeness checks after `match`. | `match exhaustive state` |
| 26 | `import` | Import supported exports from a module. | `import {Value} from "./Data"` |
| 27 | `from` | Specify an import's relative source. | `from "./Data"` |
| 28 | `operator` | Define supported class metamethod operators. | `operator +(other) ... end` |
| 29 | `lazy` | Define lazily initialized class data or lazy module import. | `lazy Cache = Create()` |
| 30 | `watch` | Define a managed-property change observer. | `watch Health(before, after) ... end` |
| 31 | `export` | Export a supported module declaration. | `export class Account ... end` |
| 32 | `as` | Rename a named import. | `import {Create as Make} from "./Module"` |
| 33 | `memo` | Declare a memoized function. | `memo function F(x) ... end`; `memo.clear(F)` resets a cache |
| 34 | `is` | Test Laua class membership/inheritance. | `object is Enemy` |
| 35 | `inline` | Request restricted inline specialization. | `inline function Double(x) ... end` |
| 36 | `const` | Immutable declaration token recognized by the editor/lint system. | `const MAX = 100`; reassignment checking is subject to scope analysis |
| 37 | `schema` | Define a runtime data-shape validator. | `schema PlayerData ... end` |

## Context and examples

### Classes, instances and `self`

```laua
class Entity
    public Health: number

    constructor(health: number)
        self.Health = health
    end

    function GetHealth(): number
        return self.Health
    end
end

local entity = new Entity(100)
print(entity:GetHealth())
```

`self` is contextual: constructors and instance methods receive an implicit instance. A `static function` does not receive one. In v3.46, known instance methods must be called using `obj:Method(...)`, or with explicit receiver as `obj.Method(obj, ...)`. An argument-free `obj.Method()` is rejected where the analyzer can prove it omits the instance. Getter/setter versus method collisions across known inheritance are also rejected.

### Runtime schemas and exhaustive matching

```laua
schema PlayerData
    Name: string
    Health: number
end

local valid, reason = PlayerData.Validate({Name = "Alex", Health = 100})
local value = PlayerData.Assert({Name = "Alex", Health = 100})
```

`schema` checks supported field types and optional fields; it is not permission validation and accepts additional keys. `match exhaustive ...` checks coverage for recognized enum/boolean cases, not arbitrary union-type exhaustiveness.

### Memoization and clearing cached results

```laua
memo function Square(x: number): number
    return x * x
end

print(Square(4))
memo.clear(Square) -- Clear this function’s cache
memo.clear()       -- Clear all memo caches in this script
```

`memo.clear` is an API call, **not an additional keyword**. It resets cached results without replacing the memoized function. Clearing a specific cache expects a memoized function; unrelated functions are not valid targets. `memo` does not automatically bound caches or invalidate them when other state changes.

### Imports and exports

```laua
-- PlayerData.laua
export class PlayerData
    Health: number = 100
end

-- In another .laua source file
import {PlayerData as Data} from "./PlayerData"
local player = new Data()
```

`as` renames the local imported binding. Exported named values appear in the returned module table, such as `return {PlayerData = PlayerData}`. The web playground does not automatically create Roblox ModuleScripts; use the project workflow or place transpiled modules in the correct Roblox hierarchy.

## Helpers, syntax operators, and directives (not extra Laua keywords)

| Token or API | Function |
| --- | --- |
| `memo.clear(F)` / `memo.clear()` | Clear one or all memoized caches in the current script. |
| `cancelScope()` | Opt-in cancellation and cleanup helper with `:Spawn`, `:OnCancel`, `:Cancel`, `:Dispose`. |
| `?.`, `?.[key]`, `?.:Method()` | Nil-safe access on supported receivers. |
| `??`, `??=` | Nil-only fallback operators, not boolean `or`. |
| `value?` on supported declarations | Early return if nil (limited syntax). |
| `=>`, `|>` | One-expression arrow functions and supported pipeline syntax. |
| `{...left, ...right}` | Restricted table spread syntax. |
| `items[1:3]` | Inclusive slicing of supported string/buffer receivers. |
| `table.map`, `table.filter`, `table.reduce`, `table.findWhere` | Laua table extensions, **not** ordinary Roblox Luau table-library APIs. |
| `--#if`, `--#else`, `--#end` | Conditional transpilation directives. |
| `--!strict`, `--!nonstrict`, `--!nocheck` | Luau mode directives, separate from Laua keywords. |

## Retired Laua syntax in v3.46

The former **custom-language** `signal`, `network`, `client_to_server`, and `server_to_client` constructs are removed from the syntax registry, autocomplete, and transpilation paths. The words may be used as ordinary identifiers where valid. Roblox `RBXScriptSignal`, `BindableEvent`, `RemoteEvent`, and built-in event methods remain available as normal Roblox APIs. No special deprecation or “feature removed” diagnostic is emitted.

## Names not intended for user declarations

v3.46 diagnoses user declarations colliding with its internal runtime identifiers, including `Promise`, `Promises`, `LauaPromiseStatus`, `LauaPackedValues`, `LauaPromiseState`, `LauaCore`, and names prefixed `__laua`. Avoid these identifiers for user-defined bindings. This is not a complete assertion about every identifier in future releases.

## Ordinary Luau words and type notes

Keywords such as `local`, `function`, `return`, `if`, `else`, `end`, `while`, `type`, and `continue` belong to Luau. The playground also recognizes Roblox globals, types, services and class members when its API data is available. The v3.46 playground highlights `self` with Laua syntax, but it is still emitted as the standard Luau instance receiver.

`const` appears in the v3.46 syntax registry and the transpiler may preserve its original token in the emitted text; the playground implements selected reassignment linting. Do not confuse editor checks with verified native Luau execution—check resulting source with your target Studio toolchain.

## Related files

- [SYNTAX.md](SYNTAX.md) — grammar and short examples
- [Documentation.md](Documentation.md) — full behavior, limitations and usage
- [GitHub repository](https://github.com/Thegreatestprogrammerthatseverlived/laua)
- [Website](https://laua.dev)

**Release:** v3.46. **Native Luau / Roblox Studio execution:** not verified by the recorded automated tests.
