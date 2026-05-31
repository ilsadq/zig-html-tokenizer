const std = @import("std");
const HtmlTokenizer = @import("HtmlTokenizer.zig");

fn fuzzTokenizer(_: void, smith: *std.testing.Smith) anyerror!void {
    var buf: [2049]u8 = undefined;

    smith.bytes(buf[0..2048]);
    buf[2048] = 0;

    const input: [:0]const u8 = buf[0..2048 :0];

    var tok = HtmlTokenizer.init(input);
    var index: usize = 0;
    var prev_index: usize = 0;

    var limit: usize = input.len + 1000;
    while (limit > 0) : (limit -= 1) {
        const token = tok.next(&index);

        if (token.loc.end > input.len) std.debug.panic("LocEndOutOfBounds", .{});
        if (token.loc.start > input.len) std.debug.panic("LocStartOutOfBounds", .{});
        if (index < prev_index) std.debug.panic("IndexDecreased", .{});

        prev_index = index;

        if (token.tag == .eof) {
            const again = tok.next(&index);
            if (again.tag != .eof) std.debug.panic("EofNotSticky", .{});
            break;
        }

        std.mem.doNotOptimizeAway(token);
    }
}

test "fuzz tokenizer" {
    try std.testing.fuzz({}, fuzzTokenizer, .{});
}
