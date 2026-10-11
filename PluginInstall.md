# Laua v3.30 — Roblox Studio Integration

## Install the local plugin

1. Open Roblox Studio in **Edit mode** (not Play mode), and save your place.
2. Import **`LauaStudio-v3.30-LocalPlugin.rbxmx`** into the place using Studio's model import workflow (or drag the file into Studio).
3. In Explorer, find `LauaStudioPlugin` (a **Script**) with a child ModuleScript named `transpiler`.
4. Move `LauaStudioPlugin` into **ServerStorage** before proceeding so it cannot accidentally run as an ordinary Script.
5. Right-click `LauaStudioPlugin` and choose **Save as Local Plugin**. If Studio prompts for plugin permissions, review and allow script editing only if you trust the local file.
6. Enable the local plugin in Studio if necessary, then open the **Laua** toolbar and click **Laua Studio**.
7. Delete the *imported copy* of `LauaStudioPlugin` from your place after it has been saved as a local plugin. Do **not** delete the installed local plugin.

> A local plugin is editor tooling. The plugin is **not** required to be present inside the game at runtime. The packaged compiler is a single self-contained `transpiler.luau` ModuleScript. No `LauaCore`, `LauaAsync`, or `LauaSignal` siblings are required.

## Create and run your first source

1. In Laua Studio, click **New**. Enter `main` and click **New** again if creating from an already selected file; choose `ModuleScript`, `Script`, or `LocalScript` before creation.
2. Paste your Laua source into the plugin editor. For a ModuleScript, try:
   ```laua
   --!strict
   class Greeting
       function Say(name: string)
           return "Hello, " .. name
       end
   end
   return Greeting.new():Say("Studio")
   ```
3. Click **Compile**. The output appears in `ReplicatedStorage/LauaCompiled/main` (ModuleScript).
4. For a ModuleScript, require it from a normal Roblox Script. Select **Script** or **LocalScript** when creating a new Laua source if you want executable server/client code; generated Scripts go into `ServerScriptService/LauaGeneratedScripts`, and generated LocalScripts go into `StarterPlayer/StarterPlayerScripts/LauaGeneratedLocalScripts`.
5. **Auto: On** compiles after saved Laua source changes (debounced). **Compile All** updates every tracked source. It stops and reports an error for each failed source, without writing a partial compilation for that source.

## Website → Studio, preserving original Laua source

1. On the updated Laua v3.30 website, click **Export Editable Studio .rbxmx**. This differs from **Export Project .rbxmx**, which continues to produce compiled ModuleScripts only.
2. Import the exported model into Roblox Studio. It contains a `LauaStudioProject` folder and a `Sources` folder of `StringValue` instances; all `.laua`/`.luau` file text is preserved.
3. In Explorer, select that imported `LauaStudioProject` folder, not the full Workspace.
4. In the Laua Studio plugin, click **Import Selected**. The plugin copies editable sources to `ServerStorage/LauaStudioProject/Sources` while keeping the original model untouched.
5. Click **Compile All**, or edit and compile individual source files.
6. You may delete the temporary imported model from Workspace after verifying the managed copies, so it does not remain in the published game.

The plugin can also import a compiled-only `LauaProject` model: select the model and click **Import Selected**. Those files become **Luau** sources because the original Laua syntax cannot be reconstructed from compiled output.

## What gets written

| Purpose | Studio location |
|---|---|
| Original editable source | `ServerStorage/LauaStudioProject/Sources` (StringValue objects) |
| Managed snapshots for conflict protection | `ServerStorage/LauaStudioProject/Snapshots` |
| Compiled modules | `ReplicatedStorage/LauaCompiled` |
| Executable server scripts | `ServerScriptService/LauaGeneratedScripts` |
| Executable client scripts | `StarterPlayer/StarterPlayerScripts/LauaGeneratedLocalScripts` |

Nested folders from imported projects are preserved. Source names and folders are restricted to Luau-style identifiers (letters, digits, underscores; names cannot start with digits). A source's output kind is fixed after creation in this first version.

## Safety and limits

- **No automatic network requests.** The native compiler is bundled, not fetched from an unverified URL. Updating the plugin means installing a new plugin package.
- **No overwriting unrelated scripts.** Laua writes inside its dedicated output folders and checks a per-source ownership ID.
- **No overwriting manually edited compiled output.** Laua stores the last generated text and refuses an update if the current script no longer matches. To resolve a conflict, save your edits elsewhere, restore/reconcile the generated script, or create a new source with a different name. The plugin deliberately has no silent force-overwrite.
- **Source is authoritative.** Do not edit the generated ModuleScript as your normal workflow. Edit its original StringValue via Laua Studio instead.
- Source files and snapshots are normal Roblox instances in the place; they are not encrypted. Keep secrets and credentials out of replicated generated modules and user-shared place files.
- The plugin uses a basic multiline TextBox, **not** Monaco or the Roblox Script Editor for custom Laua syntax. Advanced syntax highlighting and IntelliSense in the Studio widget are **not implemented**.
- The Studio plugin compiles on source changes **inside Studio** when Auto is enabled. It does not establish a live network connection to the website, VS Code, Rojo, GitHub, or cloud file systems.
- The plugin can compile `ModuleScript`, `Script`, and `LocalScript`, but cannot guarantee runtime type checking or program correctness. Roblox Studio Script Analysis is still the authority for generated Luau diagnostics.
- A folder source import is limited to 200 items at a time. Sources with unsupported names are rejected rather than silently renamed.
- Renaming/moving managed source files in Explorer does **not** automatically move or delete the previous generated output. For v3.30, avoid renaming after compilation unless you manually migrate the generated files.

## Verification limits

Automated checks cover exact plugin packaging, XML parsing, browser editable-project round-trip, malformed input rejection, unchanged compiled-only export, and JavaScript compiler smoke tests. **Roblox Studio plugin installation, live source editing, ScriptEditorService permissions, and runtime execution could not be tested in this environment.**

## Uninstall

Disable/remove the local Laua Studio plugin via Studio's plugin management UI. Source files and generated scripts remain in your place intentionally; delete those project folders in Explorer if you also want to remove the project assets.
