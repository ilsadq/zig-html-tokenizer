const Self = @This();

const std = @import("std");

const Loc = std.zig.Token.Loc;

buffer: [:0]const u8,
index: usize,
state: enum {
    data,
    text,
    tag_open,
    tag_name,
    self_closing_start_tag,
    before_attribute_name,
    after_attribute_name,
    attribute_name,
    before_attribute_value,
    attribute_value_single_quoted,
    attribute_value_double_quoted,
    attribute_value_unquoted,
    after_attribute_value_quoted,
    markup_declaration_open,
    comment_start,
    before_doctype_name,
    doctype,
    bogus_comment,
    comment_start_dash,
    comment_end_dash,
    comment_state,
    comment_end,
    end_tag_open,
    cdata_section,
    cdata_section_bracket,
    cdata_section_end,
    eof,
},
close_type: CloseType,

pub const CloseType = enum {
    false,
    true,
    self_close,
};

pub const TokenTag = enum {
    eof,
    invalid,
    open_tag,
    close_tag,
    text,
    comment,
    doctype,
    attribute_name,
    attribute_value,
    self_close_tag,
    r_bracket,
};

pub const Token = struct {
    loc: Loc,
    tag: TokenTag,
};

pub fn init(buffer: [:0]const u8) Self {
    return .{
        .buffer = buffer,
        .index = 0,
        .state = .data,
        .close_type = .false,
    };
}

pub fn next(self: *Self) Token {
    var start = self.index;

    return state: switch (self.state) {
        // https://html.spec.whatwg.org/multipage/parsing.html#data-state
        .data => switch (self.buffer[self.index]) {
            0 => continue :state .eof,
            '<' => {
                self.close_type = .false;
                self.index += 1;
                start = self.index;
                continue :state .tag_open;
            },
            else => continue :state .text,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#tag-open-state
        .tag_open => switch (self.buffer[self.index]) {
            '!' => {
                self.index += 1;
                continue :state .markup_declaration_open;
            },
            '/' => {
                self.index += 1;
                start = self.index;
                self.close_type = .true;
                continue :state .end_tag_open;
            },
            'A'...'Z', 'a'...'z' => {
                self.index += 1;
                continue :state .tag_name;
            },
            '?' => continue :state .bogus_comment,
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
            else => {
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#end-tag-open-state
        .end_tag_open => switch (self.buffer[self.index]) {
            'A'...'Z', 'a'...'z', '0'...'9' => continue :state .tag_name,
            '>' => {
                self.index += 1;
                self.state = .data;
                continue :state .data;
            },
            0 => break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid },
            else => continue :state .bogus_comment,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#tag-name-state
        .tag_name => switch (self.buffer[self.index]) {
            '\t', '\x0C', ' ', '\n', '\r' => {
                const end = self.index;
                self.index += 1;
                self.state = .before_attribute_name;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .open_tag };
            },
            '/' => {
                self.index += 1;
                self.close_type = .self_close;
                continue :state .self_closing_start_tag;
            },
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                const tag: TokenTag = if (self.close_type == .true) .close_tag else .open_tag;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = tag };
            },
            'A'...'Z', 'a'...'z', '0'...'9' => {
                self.index += 1;
                continue :state .tag_name;
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
            else => {
                self.index += 1;
                continue :state .tag_name;
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#self-closing-start-tag-state
        .self_closing_start_tag => switch (self.buffer[self.index]) {
            '>' => {
                start = self.index - 1;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .self_close_tag };
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
            else => continue :state .before_attribute_name,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-name-state
        .before_attribute_name => switch (self.buffer[self.index]) {
            '\t', '\n', ' ', '\x0C', '\r' => {
                self.index += 1;
                continue :state .before_attribute_name;
            },
            '/' => {
                self.close_type = .self_close;
                self.index += 1;
                continue :state .self_closing_start_tag;
            },
            '>' => {
                const gt = self.index;
                self.index += 1;
                self.state = .data;
                if (self.close_type == .true) {
                    break :state .{ .loc = .{ .start = start, .end = gt }, .tag = .close_tag };
                } else {
                    break :state .{ .loc = .{ .start = gt, .end = self.index }, .tag = .r_bracket };
                }
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
            else => continue :state .attribute_name,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#attribute-name-state
        .attribute_name => switch (self.buffer[self.index]) {
            '\t', '\n', ' ', '/', '>', '\x0C', '\r', 0 => {
                self.state = .after_attribute_name;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .attribute_name };
            },
            '=' => {
                const end = self.index;
                self.index += 1;
                self.state = .before_attribute_value;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .attribute_name };
            },
            else => {
                self.index += 1;
                continue :state .attribute_name;
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-name-state
        .after_attribute_name => switch (self.buffer[self.index]) {
            '\t', '\n', ' ', '\x0c', '\r' => {
                self.index += 1;
                continue :state .after_attribute_name;
            },
            '/' => {
                self.index += 1;
                self.close_type = .self_close;
                continue :state .self_closing_start_tag;
            },
            '=' => {
                self.index += 1;
                continue :state .before_attribute_value;
            },
            '>' => {
                const gt = self.index;
                self.index += 1;
                self.state = .data;
                if (self.close_type == .true) {
                    break :state .{ .loc = .{ .start = start, .end = gt }, .tag = .close_tag };
                } else {
                    break :state .{ .loc = .{ .start = gt, .end = self.index }, .tag = .r_bracket };
                }
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
            else => continue :state .attribute_name,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#before-attribute-value-state
        .before_attribute_value => switch (self.buffer[self.index]) {
            '\t', '\n', '\x0c', ' ', '\r' => {
                self.index += 1;
                continue :state .before_attribute_value;
            },
            '"' => {
                self.index += 1;
                start = self.index;
                continue :state .attribute_value_double_quoted;
            },
            '\'' => {
                self.index += 1;
                start = self.index;
                continue :state .attribute_value_single_quoted;
            },
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .invalid };
            },
            else => continue :state .attribute_value_unquoted,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(single-quoted)-state
        .attribute_value_single_quoted => switch (self.buffer[self.index]) {
            '\'' => {
                const end = self.index;
                self.index += 1;
                self.state = .after_attribute_value_quoted;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .attribute_value };
            },
            else => {
                self.index += 1;
                continue :state .attribute_value_single_quoted;
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#after-attribute-value-(quoted)-state
        .after_attribute_value_quoted => switch (self.buffer[self.index]) {
            '\t', '\n', '\x0c', ' ', '\r' => {
                self.index += 1;
                start = self.index;
                continue :state .before_attribute_name;
            },
            '/' => {
                self.index += 1;
                self.close_type = .self_close;
                continue :state .self_closing_start_tag;
            },
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = end, .end = self.index }, .tag = .r_bracket };
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
            else => continue :state .before_attribute_name,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(double-quoted)-state
        .attribute_value_double_quoted => switch (self.buffer[self.index]) {
            '"' => {
                const end = self.index;
                self.index += 1;
                self.state = .after_attribute_value_quoted;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .attribute_value };
            },
            else => {
                self.index += 1;
                continue :state .attribute_value_double_quoted;
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(unquoted)-state
        .attribute_value_unquoted => switch (self.buffer[self.index]) {
            '\t', '\n', '\x0c', ' ', '\r' => {
                self.index += 1;
                continue :state .before_attribute_name;
            },
            '>' => {
                const gt = self.index;
                self.index += 1;
                self.state = .data;
                if (self.close_type == .true) {
                    break :state .{ .loc = .{ .start = start, .end = gt }, .tag = .close_tag };
                } else {
                    break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .r_bracket };
                }
            },
            else => {
                self.index += 1;
                continue :state .attribute_value_unquoted;
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .invalid };
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#markup-declaration-open-state
        .markup_declaration_open => {
            if (std.mem.startsWith(u8, self.buffer[self.index..], "--")) {
                self.index += 2;
                start = self.index;
                continue :state .comment_start;
            } else if (self.buffer[self.index..].len >= 7 and std.ascii.eqlIgnoreCase(self.buffer[self.index..][0..7], "doctype")) {
                self.index += 7;
                start = self.index;
                continue :state .before_doctype_name;
            } else if (std.mem.startsWith(u8, self.buffer[self.index..], "[CDATA[")) {
                self.index += 7;
                continue :state .cdata_section;
            } else continue :state .bogus_comment;
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#bogus-comment-state
        .bogus_comment => switch (self.buffer[self.index]) {
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .comment };
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .comment };
            },
            else => {
                self.index += 1;
                continue :state .bogus_comment;
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-state
        .comment_start => switch (self.buffer[self.index]) {
            '-' => {
                self.index += 1;
                continue :state .comment_start_dash;
            },
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .comment };
            },
            else => continue :state .comment_state,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#comment-start-dash-state
        .comment_start_dash => switch (self.buffer[self.index]) {
            '-' => {
                self.index += 1;
                continue :state .comment_end;
            },
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .comment };
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .comment };
            },
            else => continue :state .comment_state,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#comment-state
        .comment_state => switch (self.buffer[self.index]) {
            '-' => {
                self.index += 1;
                continue :state .comment_end_dash;
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .comment };
            },
            else => {
                self.index += 1;
                continue :state .comment_state;
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-dash-state
        .comment_end_dash => switch (self.buffer[self.index]) {
            '-' => {
                self.index += 1;
                continue :state .comment_end;
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .comment };
            },
            else => {
                self.index += 1;
                continue :state .comment_state;
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#comment-end-state
        .comment_end => switch (self.buffer[self.index]) {
            '>' => {
                const end = self.index - 2;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .comment };
            },
            '-' => {
                self.index += 1;
                continue :state .comment_end;
            },
            0 => {
                self.state = .eof;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .comment };
            },
            else => {
                self.index += 1;
                continue :state .comment_state;
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#before-doctype-name-state
        .before_doctype_name => switch (self.buffer[self.index]) {
            '\t', '\n', '\x0C', ' ', '\r' => {
                self.index += 1;
                start = self.index;
                continue :state .before_doctype_name;
            },
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .doctype };
            },
            0 => break :state .{ .loc = .{ .start = self.index, .end = self.index }, .tag = .eof },
            else => continue :state .doctype,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#doctype-state
        .doctype => switch (self.buffer[self.index]) {
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .doctype };
            },
            0 => break :state .{ .loc = .{ .start = self.index, .end = self.index }, .tag = .eof },
            else => {
                self.index += 1;
                continue :state .doctype;
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-state
        .cdata_section => switch (self.buffer[self.index]) {
            ']' => {
                self.index += 1;
                continue :state .cdata_section_bracket;
            },
            0 => break :state .{ .loc = .{ .start = self.index, .end = self.index }, .tag = .eof },
            else => {
                self.index += 1;
                continue :state .cdata_section;
            },
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-bracket-state
        .cdata_section_bracket => switch (self.buffer[self.index]) {
            ']' => {
                self.index += 1;
                continue :state .cdata_section_end;
            },
            else => continue :state .cdata_section,
        },
        // https://html.spec.whatwg.org/multipage/parsing.html#cdata-section-end-state
        .cdata_section_end => switch (self.buffer[self.index]) {
            '>' => {
                const end = self.index;
                self.index += 1;
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = end }, .tag = .text };
            },
            ']' => {
                self.index += 1;
                continue :state .cdata_section_end;
            },
            else => continue :state .cdata_section,
        },

        .text => switch (self.buffer[self.index]) {
            0, '<' => {
                self.state = .data;
                break :state .{ .loc = .{ .start = start, .end = self.index }, .tag = .text };
            },
            else => {
                self.index += 1;
                continue :state .text;
            },
        },

        .eof => break :state .{ .loc = .{ .start = self.index, .end = self.index }, .tag = .eof },
    };
}
