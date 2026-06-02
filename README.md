# zig-html-tokenizer

A zero-allocation HTML tokenizer for Zig 0.16. It walks a null-terminated byte slice and emits tokens one at a time — no heap, no callbacks.

## What it does

Implements the WHATWG tokenizer state machine for the common states: tags, attributes, comments, DOCTYPE, CDATA, and bogus comments. Each call to `next()` advances the cursor and returns one token with a `tag` (kind) and a `loc` (byte range into your input). Tokens are cheap — just a tag enum plus two `usize` offsets.

The tokenizer is deliberately not a full parser. It does not build a tree, resolve entities, or handle `<script>`/`<style>` raw-text modes. If you need to slice attribute values or text nodes out of the source, you already have the byte range.

## Usage

Add to `build.zig.zon`:

```zig
.dependencies = .{
    .zig_html_tokenizer = .{
        .url = "https://github.com/ilsadq/zig-html-tokenizer/archive/refs/heads/main.tar.gz",
        .hash = "zig_html_tokenizer-0.0.1-aALtTZdXDwBaMjl4aS3UNt1S2xrmP9noouyYqgVRwsvP",
    },
},
```

Add to `build.zig`:

```zig
const dep = b.dependency("zig_html_tokenizer", .{ .target = target, .optimize = optimize });
your_module.addImport("HtmlTokenizer", dep.module("HtmlTokenizer"));
```

Then in your code:

```zig
const HtmlTokenizer = @import("HtmlTokenizer");

const html: [:0]const u8 = "<p class=\"note\">hello</p>";
var tok = HtmlTokenizer.init(html);

while (true) {
    const token = tok.next();
    if (token.tag == .eof) break;
    const slice = html[token.loc.start..token.loc.end];
    std.debug.print("{s}: \"{s}\"\n", .{ @tagName(token.tag), slice });
}
```

Output:

```
open_tag: "p"
attribute_name: "class"
attribute_value: "note"
r_bracket: ">"
text: "hello"
close_tag: "p"
```

## Token kinds

| Tag | Slice covers |
|---|---|
| `open_tag` | tag name (`p`, `div`, …) |
| `close_tag` | tag name |
| `self_close_tag` | `/>` |
| `r_bracket` | `>` that closes the open tag; for unquoted attribute values the slice includes the value too (`foo>`) |
| `attribute_name` | attribute name |
| `attribute_value` | quoted attribute value (without quotes) |
| `text` | raw text between tags |
| `comment` | content between `<!--` and `-->` |
| `doctype` | name after `DOCTYPE ` (case-insensitive match) |
| `invalid` | malformed input; tokenizer recovers and continues |
| `eof` | end of input; sticky — keeps returning `eof` |

Attributes arrive as `attribute_name` followed (if there is a value) by `attribute_value`. A boolean attribute like `disabled` produces only `attribute_name`. The tag closes with `r_bracket` or `self_close_tag`.

## Building and testing

```sh
zig build test          # unit tests
zig build fuzz          # run the corpus through the fuzz harness once
zig build fuzz --fuzz   # coverage-guided fuzzing (runs until you stop it)
```

Requires Zig 0.16.
