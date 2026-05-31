const std = @import("std");
const testing = std.testing;
const HtmlTokenizer = @import("HtmlTokenizer.zig");
const TokenTag = HtmlTokenizer.TokenTag;

const E = struct {
    tag: TokenTag,
    slice: ?[]const u8 = null,
};

fn e(tag: TokenTag, slice: []const u8) E {
    return .{ .tag = tag, .slice = slice };
}

fn expectTokens(buf: [:0]const u8, expected: []const E) !void {
    var tok = HtmlTokenizer.init(buf);
    var index: usize = 0;
    for (expected, 0..) |exp, i| {
        const token = tok.next(&index);
        errdefer std.debug.print(
            "token[{d}]: expected .{s}, got .{s}\n",
            .{ i, @tagName(exp.tag), @tagName(token.tag) },
        );
        try testing.expectEqual(exp.tag, token.tag);
        if (exp.slice) |want| {
            const s = token.loc.start;
            const end = token.loc.end;
            const got: []const u8 = if (s <= end and end <= buf.len) buf[s..end] else "";
            try testing.expectEqualStrings(want, got);
        }
    }
}

test "text plain" {
    try expectTokens("hello", &.{
        e(.text, "hello"),
        e(.eof, ""),
    });
}

test "text newline folded" {
    try expectTokens("foo\nbar\rbaz", &.{
        e(.text, "foo\nbar\rbaz"),
        e(.eof, ""),
    });
}

test "text stops at tag" {
    try expectTokens("hello<br>", &.{
        e(.text, "hello"),
        e(.open_tag, "br"),
        e(.eof, ""),
    });
}

test "open tag" {
    try expectTokens("<div>", &.{
        e(.open_tag, "div"),
        e(.eof, ""),
    });
}

test "open tag uppercase" {
    try expectTokens("<DIV>", &.{
        e(.open_tag, "DIV"),
        e(.eof, ""),
    });
}

test "open tag with digits and hyphens" {
    try expectTokens("<h1>", &.{ e(.open_tag, "h1"), e(.eof, "") });
    try expectTokens("<my-elem>", &.{ e(.open_tag, "my-elem"), e(.eof, "") });
}

test "close tag" {
    try expectTokens("</div>", &.{
        e(.close_tag, "div"),
        e(.eof, ""),
    });
}

test "self-closing no space" {
    try expectTokens("<br/>", &.{
        e(.self_close_tag, "br/>"),
        e(.eof, ""),
    });
}

test "text between tags" {
    try expectTokens("<p>hello</p>", &.{
        e(.open_tag, "p"),
        e(.text, "hello"),
        e(.close_tag, "p"),
        e(.eof, ""),
    });
}

test "nested tags" {
    try expectTokens("<a><b></b></a>", &.{
        e(.open_tag, "a"),
        e(.open_tag, "b"),
        e(.close_tag, "b"),
        e(.close_tag, "a"),
        e(.eof, ""),
    });
}

test "attribute double-quoted" {
    try expectTokens("<a href=\"url\">", &.{
        e(.open_tag, "a"),
        e(.attribute_name, "href"),
        e(.attribute_value, "url"),
        e(.open_tag_end, ""),
        e(.eof, ""),
    });
}

test "attribute double-quoted empty" {
    try expectTokens("<div class=\"\">", &.{
        e(.open_tag, "div"),
        e(.attribute_name, "class"),
        e(.attribute_value, ""),
        e(.open_tag_end, ""),
        e(.eof, ""),
    });
}

test "attribute single-quoted" {
    try expectTokens("<a href='url'>", &.{
        e(.open_tag, "a"),
        e(.attribute_name, "href"),
        e(.attribute_value, "url"),
        e(.open_tag_end, ""),
        e(.eof, ""),
    });
}

test "attribute unquoted" {
    try expectTokens("<div class=foo>", &.{
        e(.open_tag, "div"),
        e(.attribute_name, "class"),
        e(.open_tag_end, "foo"),
        e(.eof, ""),
    });
}

test "attribute boolean" {
    try expectTokens("<input disabled>", &.{
        e(.open_tag, "input"),
        e(.attribute_name, "disabled"),
        e(.open_tag_end, ""),
        e(.eof, ""),
    });
}

test "attribute multiple" {
    try expectTokens("<div id=\"a\" class=\"b\">", &.{
        e(.open_tag, "div"),
        e(.attribute_name, "id"),
        e(.attribute_value, "a"),
        e(.attribute_name, "class"),
        e(.attribute_value, "b"),
        e(.open_tag_end, ""),
        e(.eof, ""),
    });
}

test "comment normal" {
    try expectTokens("<!-- hello -->", &.{
        e(.comment, " hello "),
        e(.eof, ""),
    });
}

test "comment empty" {
    try expectTokens("<!---->", &.{
        e(.comment, ""),
        e(.eof, ""),
    });
}

test "comment abrupt close" {
    try expectTokens("<!-->", &.{
        e(.comment, ""),
        e(.eof, ""),
    });
}

test "comment dash in body" {
    try expectTokens("<!-- a--b -->", &.{
        e(.comment, " a--b "),
        e(.eof, ""),
    });
}

test "doctype" {
    try expectTokens("<!DOCTYPE html>", &.{
        e(.doctype, "html"),
        e(.eof, ""),
    });
}

test "cdata section" {
    try expectTokens("<![CDATA[hi]]>", &.{
        .{ .tag = .text },
        e(.eof, ""),
    });
}

test "bogus comment processing instruction" {
    try expectTokens("<?foo>", &.{
        e(.comment, "?foo"),
        e(.eof, ""),
    });
}

test "bogus comment invalid end tag" {
    try expectTokens("</!foo>", &.{
        e(.comment, "!foo"),
        e(.eof, ""),
    });
}

test "invalid tag open with space" {
    try expectTokens("< div>", &.{
        e(.invalid, ""),
        e(.text, " div>"),
        e(.eof, ""),
    });
}

test "unclosed tag at eof" {
    try expectTokens("<div", &.{
        e(.invalid, "div"),
        e(.eof, ""),
    });
}

test "empty input" {
    try expectTokens("", &.{
        e(.eof, ""),
    });
}

test "self-closing with space" {
    // <br /> — the slash triggers a phantom empty attribute_name before the self-close
    try expectTokens("<br />", &.{
        e(.open_tag, "br"),
        .{ .tag = .attribute_name },
        e(.self_close_tag, "/>"),
        e(.eof, ""),
    });
}

test "tag trailing space" {
    // <div > — space before '>' emits a phantom empty attribute_name
    try expectTokens("<div >", &.{
        e(.open_tag, "div"),
        .{ .tag = .attribute_name },
        .{ .tag = .open_tag_end },
        e(.eof, ""),
    });
}

test "self-closing with attribute" {
    try expectTokens("<input type=\"text\"/>", &.{
        e(.open_tag, "input"),
        e(.attribute_name, "type"),
        e(.attribute_value, "text"),
        e(.self_close_tag, "/>"),
        e(.eof, ""),
    });
}

test "attribute with hyphen" {
    try expectTokens("<div data-foo=\"bar\">", &.{
        e(.open_tag, "div"),
        e(.attribute_name, "data-foo"),
        e(.attribute_value, "bar"),
        e(.open_tag_end, ""),
        e(.eof, ""),
    });
}

test "eof inside comment" {
    try expectTokens("<!--", &.{
        e(.comment, ""),
        e(.eof, ""),
    });
}

test "eof inside double-quoted attribute" {
    try expectTokens("<a href=\"", &.{
        e(.open_tag, "a"),
        e(.attribute_name, "href"),
        e(.invalid, ""),
        e(.eof, ""),
    });
}

test "lowercase doctype becomes bogus comment" {
    // DOCTYPE check is case-sensitive; lowercase falls through to bogus_comment
    try expectTokens("<!doctype html>", &.{
        e(.comment, "!doctype html"),
        e(.eof, ""),
    });
}

test "full document" {
    try expectTokens("<!DOCTYPE html><html><head></head><body></body></html>", &.{
        e(.doctype, "html"),
        e(.open_tag, "html"),
        e(.open_tag, "head"),
        e(.close_tag, "head"),
        e(.open_tag, "body"),
        e(.close_tag, "body"),
        e(.close_tag, "html"),
        e(.eof, ""),
    });
}

test "whitespace between tags is text" {
    try expectTokens("<a> </a>", &.{
        e(.open_tag, "a"),
        e(.text, " "),
        e(.close_tag, "a"),
        e(.eof, ""),
    });
}

test "comment with extra dashes" {
    try expectTokens("<!-- a---b -->", &.{
        e(.comment, " a---b "),
        e(.eof, ""),
    });
}

test "attribute value with ampersand" {
    try expectTokens("<a href=\"a&amp;b\">", &.{
        e(.open_tag, "a"),
        e(.attribute_name, "href"),
        e(.attribute_value, "a&amp;b"),
        e(.open_tag_end, ""),
        e(.eof, ""),
    });
}

test "HTML Standard fully tokenizes without panic" {
    const html: [:0]const u8 = @embedFile("HTML Standard.html");
    var tok = HtmlTokenizer.init(html);
    var index: usize = 0;
    var count: usize = 0;

    while (true) {
        const token = tok.next(&index);
        try testing.expect(token.loc.end <= html.len);
        count += 1;
        if (token.tag == .eof) break;
        if (count > html.len + 1) {
            std.debug.print("infinite loop: count={d} index={d}\n", .{ count, index });
            return error.InfiniteLoop;
        }
    }

    try testing.expectEqual(TokenTag.eof, tok.next(&index).tag);
    try testing.expect(count > 10_000);
    std.debug.print("HTML Standard: {d} tokens\n", .{count});
}

fn nanotime() u64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(std.posix.system.CLOCK.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

test "bench HTML Standard" {
    const html: [:0]const u8 = @embedFile("HTML Standard.html");
    const iterations: usize = 10;

    var token_count: usize = 0;
    const t0 = nanotime();

    for (0..iterations) |_| {
        var tok = HtmlTokenizer.init(html);
        var index: usize = 0;
        while (true) {
            const token = tok.next(&index);
            token_count += 1;
            if (token.tag == .eof) break;
        }
    }

    const ns = nanotime() - t0;
    const mb = @as(f64, @floatFromInt(html.len * iterations)) / (1024.0 * 1024.0);
    const secs = @as(f64, @floatFromInt(ns)) / 1e9;
    std.debug.print(
        "\nbench: {d:.1} MB/s  ({d} tokens/iter, {d} iter)\n",
        .{ mb / secs, token_count / iterations, iterations },
    );
}
