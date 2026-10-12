# Laua Keywords and Syntax — v3.37

This is the companion to [Documentation.md](Documentation.md) for **Laua v3.37 (October 12, 2026)**. The playground's `LAUA_KEYWORDS` list contains **35 words**. They are listed below **exactly by spelling**, with their implemented roles and limitations.

**Important distinctions:**

- A *Laua syntax word* is not necessarily globally reserved. Many are **contextual** (e.g. `constructor` inside a class, `as` inside an import). Ordinary table fields such as `record.namespace` or `{new = 3}` are meant to remain legal.
- This inventory comes from the v3.37 **playground's keyword list**, not from a formal language grammar or complete reserved-word scanner. Some listed words have limited or incomplete support, especially `const`.
- Built-in **Luau** words such as `local`, `function`, `if`, `then`, `else`, `end`, `return`, `while`, `for`, `type`, `continue`, `nil`, `true`, `false` are inherited, **not counted** in the 35 Laua words.
- Operators (`?.`, `??`, `??=`, `=>`, `|>`) and directives (`--#if`, `@nolint`) have their own section; they are **not words**.

## Complete 35-word inventory

| Word | Role in Laua | Example / scope |
| --- | --- | --- |
| `class` | Declare a class. | `class Player ... end` |
| `extends` | Inherit from another class. | `class Zombie extends Entity` |
| `constructor` | Declare an initializer inside a class. | `constructor(name: string) ... end` |
| `private` | Mark a class member as private. | `private Secret = 1` — partially checked |
| `public` | Mark a class member as public. | `public Health = 100` |
| `protected` | Mark a member for subclass access. | `protected Health = 100` — partially checked |
| `static` | Declare a class-level field/method. | `static Count = 0` |
| `new` | Construct an instance of a Laua class. | `new Player("Alex")` |
| `namespace` | Create a scoped exported table. | `namespace Math ... end` |
| `super` | Call an inherited initializer or method. | `super(name)` / `super:Move()` |
| `abstract` | Declare abstract class/method semantics. | `abstract class Entity` |
| `override` | Mark an inherited method replacement. | `override function Move()` |
| `enum` | Declare a frozen enum table. | `enum State ... end` |
| `final` | Mark a class/method as not extendable/overridable. | `final class Root` |
| `get` | Declare a computed property getter. | `get IsAlive() ... end` |
| `set` | Declare a computed property setter. | `set Health(value) ... end` |
| `defer` | Schedule cleanup on enclosing function exit. | `defer ... end` |
| `using` | Bind a cleanup-managed resource. | `using connection = event:Connect(fn)` |
| `async` | Declare an async function. | `async function Load() ... end` |
| `await` | Await supported async work or a signal. | `local value = await Load()` |
| `match` | Start pattern matching. | `match value ... end` |
| `case` | Declare a pattern arm. | `case {Health = 0}` |
| `default` | Catch-all match arm. | `default` |
| `import` | Import a compiled ModuleScript export/value. | `import Data from "./Data"` |
| `from` | Specify relative module path in import. | `from "./Data"` |
| `operator` | Declare supported class operator metamethod. | `operator +(other) ... end` |
| `signal` | Declare a per-instance event in a class. | `signal Changed(value: number)` |
| `lazy` | Declare lazy property or lazy module import. | `lazy Cache = Build()` / `import lazy M ...` |
| `watch` | Watch a class property for changes. | `watch Health(old, new) ... end` |
| `export` | Export named class/function/value declaration. | `export function Spawn()` |
| `as` | Rename a named import. | `import {Spawn as Make} ...` |
| `memo` | Memoize a named function. | `memo function Double(x) ... end` — known newline edge case |
| `is` | Check Laua class membership/inheritance. | `object is Entity` |
| `inline` | Request limited compile-time function specialization. | `inline function Double(x) ... end` |
| `const` | Editor-recognized / limited guard syntax. | **Plain `const x = 1` does not lower to valid Luau in v3.37. Use `local`.** |

**Count: 35.** Modifiers (`public`, `static`, etc.) are contextual class syntax, not stand-alone executable statements. `default`, `case` and `from` likewise only have meaning in their corresponding constructs.

## Operators and additional syntax

| Syntax | Purpose | Example / limit |
| --- | --- | --- |
| `?.` | Optional property/method/call access. | `x?.Health`, `x?.:Heal(10)`, `x?.(10)` |
| `?.[key]` | Optional indexed access. | `inventory?.[slot]` |
| `??` | Use right side only if left is `nil`. | `coins ?? 0` |
| `??=` | Nil-only fallback assignment. | `coins ??= 0` |
| `?` | Early-return suffix on a simple local/const assignment. | `local value = source?` |
| `=>` | One-expression arrow function. | `local f = (x) => x + 1` |
| `|>` | Single-line function pipeline. | `local x = 5 |> Double` |
| `...name` | Spread table members in a spread-only literal. | `{...left, ...right}` |
| `[start:end]` | Inclusive string/buffer slice. | `text[1:3]` |
| `local {a, b: alias} = obj` | Single-level record destructuring. | Does not support nested defaults |
| `function F(x = value)` | Default parameter expression. | `nil` triggers default, `false` does not |
| `table.map`, `table.filter`, `table.reduce`, `table.findWhere` | Transpiler-rewritten collection helpers. | These are **helper calls**, not keywords |

## Compile-time directives and annotations

| Form | Meaning |
| --- | --- |
| `--#if DEBUG` | Include branch when `Mode = "Debug"` (also `DEVELOPMENT` and `RELEASE`). |
| `--#else` | Alternate compile-time branch. |
| `--#end` | End compile-time branch. |
| `@nolint("UnusedLocal")` | Suppress a supported named playground warning near the following statement. Not a general error suppression. |
| `--!strict`, `--!nonstrict`, `--!nocheck` | **Native Luau** checking directives, not new Laua keywords. |

Other native Roblox/Luau attributes such as `@native` and `@deprecated` are separate from Laua-specific syntax.

## Example: ordinary identifiers are not always Laua syntax

```luau
local record = {
    class = 1,
    namespace = 2,
    new = 3,
    is = false,
    memo = "value",
}
print(record.namespace, record.new, record.memo)

local message = "signal Changed() new Something await Fetch()"
```

The compiler attempts to avoid rewriting keyword-like text inside table fields, property access, comments, quoted strings, long-bracket literals, and backtick strings. Because v3.37 uses several source-level passes rather than a complete parser, edge cases can still exist.

## Known limits and non-keywords

`self` is the ordinary **Luau** method receiver and the correct identifier inside Laua class methods. **`this` is not a Laua replacement for `self`.** Ordinary Lua/Luau `and`, `or`, `not`, `in`, `do`, `end`, `elseif`, `until`, `return`, etc. still behave as native Luau constructs.

The following are **not implemented complete Laua keywords/features**: `derive`, `unique type`, labeled `break outer`, labeled `continue outer`, constrained generic enforcement, full regular expressions, and general named arguments. Do not add them to source and assume the compiler supports them.

For full examples, supported compiler options, warnings and test instructions, use [Documentation.md](Documentation.md).
