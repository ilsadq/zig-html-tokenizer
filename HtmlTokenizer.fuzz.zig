const std = @import("std");
const HtmlTokenizer = @import("HtmlTokenizer.zig");

const corpus: []const []const u8 = &.{
    // text / data state
    "hello",
    "foo\nbar\rbaz",
    "",

    // tag_open: each branch
    "<div>",           // A-Z/a-z → tag_name
    "<?pi>",           // '?' → bogus_comment
    "< >",             // else → invalid

    // end_tag_open: each branch
    "</div>",          // letter → tag_name
    "</>",             // '>' → skip empty close tag

    // tag_name: each exit
    "<br/>",           // '/' → self_closing_start_tag
    "<DIV>",           // uppercase
    "<h1>",            // digit
    "<my-elem>",       // '-' → else arm

    // self_closing_start_tag: each branch
    "<br/",            // 0 → invalid (EOF)
    "<br/ >",          // else → before_attribute_name

    // before_attribute_name: each branch
    "<div >",          // '>' → phantom attribute_name
    "<br />",          // '/' → phantom attribute_name
    "<div ",           // 0 → phantom attribute_name (EOF)
    "<div =>",         // '=' branch

    // after_attribute_name: each branch
    "<a href >",       // '>' after whitespace
    "<input disabled/>",  // '/' → self_closing_start_tag
    "<a href =\"x\">", // '=' with whitespace before it

    // before_attribute_value: each branch
    "<a href=\"url\">",
    "<a href='url'>",
    "<a href=url>",
    "<a href=\"\">",
    "<a href=>",       // '>' → invalid (missing value)

    // attribute_value_* EOF
    "<a href=\"",      // double-quoted → 0
    "<a href='",       // single-quoted → 0

    // after_attribute_value_quoted: each branch
    "<a href=\"x\"y>", // else → before_attribute_name
    "<input type=\"text\"/>",
    "<div id=\"a\" class=\"b\">",

    // markup_declaration_open: each branch
    "<!-- comment -->",
    "<!DOCTYPE html>",
    "<![CDATA[data]]>",
    "<!xyz>",          // fallthrough → bogus_comment
    "<!doctype html>", // lowercase → bogus_comment

    // comment branches
    "<!---->",         // comment_start → '>'
    "<!--->",          // comment_start_dash → '>'
    "<!---",           // comment_start_dash → 0 (EOF)
    "<!--",            // comment_state → 0 (EOF)
    "<!-- a--b -->",   // comment_end → else (non-'>' after '--')
    "<!-- a-b -->",    // comment_end_dash → else (non-'-' after single '-')
    "</!bogus>",       // end_tag_open → else → bogus_comment

    // cdata branches
    "<![CDATA[] ]]>",   // cdata_section_bracket → else (non-']' after ']')
    "<![CDATA[]]x]]>",  // cdata_section_end → else (non-'>' non-']' after ']]')

    // truncated (EOF mid-tag)
    "<",
    "</",
    "<!-",
    "<!DOCTYPE",
    "<div",

    // full document
    "<!DOCTYPE html><html><head></head><body><p>text</p></body></html>",
};

fn fuzzTokenizer(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [2049]u8 = undefined;

    smith.bytes(buf[0..2048]);
    buf[2048] = 0;

    const input: [:0]const u8 = buf[0..2048 :0];

    var tok = HtmlTokenizer.init(input);
    var prev_index: usize = 0;

    var limit: usize = input.len + 1000;
    while (limit > 0) : (limit -= 1) {
        const token = tok.next();

        if (token.loc.end > input.len) std.debug.panic("LocEndOutOfBounds", .{});
        if (token.loc.start > input.len) std.debug.panic("LocStartOutOfBounds", .{});
        if (tok.index < prev_index) std.debug.panic("IndexDecreased", .{});

        prev_index = tok.index;

        if (token.tag == .eof) {
            const again = tok.next();
            if (again.tag != .eof) std.debug.panic("EofNotSticky", .{});
            break;
        }

        std.mem.doNotOptimizeAway(token);
    }
}

test "fuzz tokenizer" {
    try std.testing.fuzz({}, fuzzTokenizer, .{ .corpus = corpus });
}
