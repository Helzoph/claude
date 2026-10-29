# Plane HTML: Format Rules and Silent Failures

Read this before sending any `description_html`. Every failure below returns HTTP 200, so nothing tells you it happened except reading the item back.

## Format

- `h3` is used only for block names. No `h1`–`h6` inside blocks.
- Allowed tags: `h3`, `p`, `strong`, `ul`, `li`, `code`. Nothing else has been verified to survive the Plane editor.
- Write tags as raw HTML. In text, write `<`, `>`, `&` as `&lt;`, `&gt;`, `&amp;`.
- **Write the whole body as one line. No newline anywhere between tags, and no whitespace next to a block tag (`h3`, `p`, `ul`, `li`).** Plane stores the newlines and indentation between tags as text; the next time anyone saves the item from the web editor, each of those gaps becomes an empty bullet or empty paragraph — every real bullet ends up sandwiched between blank ones. A space between two inline tags inside one line of text (`<code>a</code> 和 <code>b</code>`) is real text and is fine.
- Send the body in `description_html`, never `description_stripped`. Plane wraps stripped text into plain paragraphs, so the `h3` blocks never exist.
- Read back with `description_html`, never `description_stripped` — stripping removes the `h3` tags and the blocks become indistinguishable lines.
- A body that has been saved from the Plane web editor comes back with attributes on every element (`<h3 class="editor-heading-block" data-id="…">`) and without the outer `<div>`. Match tags with patterns that allow attributes, e.g. `<h3[^>]*>`.

## Silent Failures (HTTP 200, Wrong Data)

- **Escaped tags** (`&lt;p&gt;`) are stored literally and render as visible tag text.
- **Unknown tags** (custom XML-style tags) are stripped on write — their content vanishes, and the call still succeeds.
- **`state_group` returned by `create` / `update` is stale** (null on create, the pre-change value on update). Confirm state with `list`.
- **A stale browser tab wins.** After an API edit, a Plane tab that was open before the edit will save its old copy over the whole body the next time the user edits there.
- **Long Chinese payloads occasionally come back with U+FFFD (`�`) in place of a character.** Always read the body back after writing and search it for U+FFFD; if found, rewrite (rephrasing the affected sentence helps).
