const std = @import("std");
const HtmlTokenizer = @import("HtmlTokenizer.zig");
const TokenTag = HtmlTokenizer.TokenTag;

const W = std.testing.Smith.Weight;
const html_weights: []const W = &.{
    W.value(u8, 0, 20),
    W.rangeAtMost(u8, 1, 8, 1),
    W.value(u8, '\t', 8),
    W.value(u8, '\n', 15),
    W.rangeAtMost(u8, 11, 12, 1),
    W.value(u8, '\r', 8),
    W.rangeAtMost(u8, 14, 31, 1),
    W.value(u8, ' ', 20),
    W.value(u8, '!', 15),
    W.value(u8, '"', 15),
    W.rangeAtMost(u8, '#', '&', 2),
    W.value(u8, '\'', 15),
    W.rangeAtMost(u8, '(', '+', 2),
    W.rangeAtMost(u8, ',', '.', 2),
    W.value(u8, '/', 15),
    W.rangeAtMost(u8, '0', '9', 8),
    W.rangeAtMost(u8, ':', ';', 2),
    W.value(u8, '<', 30),
    W.value(u8, '=', 20),
    W.value(u8, '>', 30),
    W.value(u8, '?', 10),
    W.value(u8, '@', 2),
    W.rangeAtMost(u8, 'A', 'Z', 8),
    W.value(u8, '[', 10),
    W.value(u8, '\\', 2),
    W.value(u8, ']', 10),
    W.rangeAtMost(u8, '^', '`', 2),
    W.rangeAtMost(u8, 'a', 'z', 8),
    W.rangeAtMost(u8, '{', '~', 2),
    W.rangeAtMost(u8, 127, 255, 1),
};

const corpus: []const []const u8 = &.{
    "<div>",
    "</div>",
    "<br/>",
    "<br />",
    "<a href=\"url\">",
    "<a href='url'>",
    "<a href=url>",
    "<a href=\"\">",
    "<input disabled>",
    "<input type=\"text\"/>",
    "<div id=\"a\" class=\"b\">",
    "<div data-foo=\"bar\">",
    "<!-- comment -->",
    "<!---->",
    "<!--->",
    "<!--",
    "<!-- a--b -->",
    "<!DOCTYPE html>",
    "<!doctype html>",
    "<![CDATA[data]]>",
    "<?processing>",
    "</!bogus>",
    "hello world",
    "foo\nbar\rbaz",
    "<",
    ">",
    "</",
    "<!-",
    "<!--",
    "<!DOCTYPE",
    "<div",
    "<div >",
    "<div\n>",
    "<a href=\"",
    "<!DOCTYPE html><html><head></head><body><p>text</p></body></html>",
};

fn runOne(_: void, smith: *std.testing.Smith) anyerror!void {
    const max_len = 512;
    var buf: [max_len + 1]u8 = undefined;
    smith.bytesWeightedWithHash(buf[0..max_len], html_weights, @src().line);
    buf[max_len] = 0;
    const input: [:0]const u8 = buf[0..max_len :0];

    var tok = HtmlTokenizer.init(input);
    var index: usize = 0;
    var prev_index: usize = 0;

    var limit: usize = max_len + 2;
    while (limit > 0) : (limit -= 1) {
        const token = tok.next(&index);

        if (token.loc.end > input.len) return error.LocEndOutOfBounds;
        if (token.loc.start > input.len) return error.LocStartOutOfBounds;
        if (index < prev_index) return error.IndexDecreased;
        prev_index = index;

        if (token.tag == .eof) {
            const again = tok.next(&index);
            if (again.tag != .eof) return error.EofNotSticky;
            return;
        }
    }

    return error.InfiniteLoop;
}

test "fuzz tokenizer" {
    try std.testing.fuzz({}, runOne, .{ .corpus = corpus });
}
