const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Conditionals in Ghostty configuration are based on a static, typed
/// state of the world instead of a dynamic key-value set. This simplifies
/// the implementation, allows for better type checking, and enables a
/// typed C API.
pub const State = struct {
    /// The theme of the underlying OS desktop environment.
    theme: Theme = .light,

    /// The target OS of the current build.
    os: std.Target.Os.Tag = builtin.target.os.tag,

    /// The currently running foreground application/command name.
    /// This is typically set via shell integration when a command starts.
    /// The value is the command name (first word of the command line).
    app: ?[]const u8 = null,

    pub const Theme = enum { light, dark };

    /// Tests the conditional against the state and returns true if it matches.
    pub fn match(self: State, cond: Conditional) bool {
        switch (cond.key) {
            .app => {
                // App matching uses case-insensitive comparison on the
                // command name (first word, without arguments).
                const current_app = self.app orelse return cond.op == .ne;
                const matches = matchAppPattern(current_app, cond.value);
                return switch (cond.op) {
                    .eq => matches,
                    .ne => !matches,
                };
            },
            inline else => |tag| {
                // The raw value of the state field.
                const raw = @field(self, @tagName(tag));

                // For enum values, convert to tag name for comparison.
                const value: []const u8 = @tagName(raw);

                return switch (cond.op) {
                    .eq => std.mem.eql(u8, value, cond.value),
                    .ne => !std.mem.eql(u8, value, cond.value),
                };
            },
        }
    }

    /// Matches an app pattern against the current app string.
    /// - Extracts command name (first word before space)
    /// - Case-insensitive comparison
    fn matchAppPattern(app: []const u8, pattern: []const u8) bool {
        // Extract command name (first word) from the full command
        const app_cmd = if (std.mem.indexOfScalar(u8, app, ' ')) |i| app[0..i] else app;
        return std.ascii.eqlIgnoreCase(app_cmd, pattern);
    }
};

/// An enum of the available conditional configuration keys.
pub const Key = key: {
    const stateInfo = @typeInfo(State).@"struct";
    var fields: [stateInfo.fields.len]std.builtin.Type.EnumField = undefined;
    for (stateInfo.fields, 0..) |field, i| fields[i] = .{
        .name = field.name,
        .value = i,
    };

    break :key @Type(.{ .@"enum" = .{
        .tag_type = std.math.IntFittingRange(0, fields.len - 1),
        .fields = &fields,
        .decls = &.{},
        .is_exhaustive = true,
    } });
};

/// A single conditional that can be true or false.
pub const Conditional = struct {
    key: Key,
    op: Op,
    value: []const u8,

    pub const Op = enum { eq, ne };

    pub fn clone(
        self: Conditional,
        alloc: Allocator,
    ) Allocator.Error!Conditional {
        return .{
            .key = self.key,
            .op = self.op,
            .value = try alloc.dupe(u8, self.value),
        };
    }

    /// Parse a condition from "key=value" or "key!=value" format.
    /// Returns null if the string cannot be parsed as a valid conditional.
    pub fn parse(s: []const u8) ?Conditional {
        // Check for != first (longer operator)
        if (std.mem.indexOf(u8, s, "!=")) |idx| {
            const key_str = std.mem.trim(u8, s[0..idx], " \t");
            const value = std.mem.trim(u8, s[idx + 2 ..], " \t");
            const key = std.meta.stringToEnum(Key, key_str) orelse return null;
            return .{ .key = key, .op = .ne, .value = value };
        }
        if (std.mem.indexOf(u8, s, "=")) |idx| {
            const key_str = std.mem.trim(u8, s[0..idx], " \t");
            const value = std.mem.trim(u8, s[idx + 1 ..], " \t");
            const key = std.meta.stringToEnum(Key, key_str) orelse return null;
            return .{ .key = key, .op = .eq, .value = value };
        }
        return null;
    }
};

test "conditional enum match" {
    const testing = std.testing;
    const state: State = .{ .theme = .dark };
    try testing.expect(state.match(.{
        .key = .theme,
        .op = .eq,
        .value = "dark",
    }));
    try testing.expect(!state.match(.{
        .key = .theme,
        .op = .ne,
        .value = "dark",
    }));
    try testing.expect(state.match(.{
        .key = .theme,
        .op = .ne,
        .value = "light",
    }));
}

test "app conditional matching" {
    const testing = std.testing;
    const state: State = .{ .app = "vim" };
    try testing.expect(state.match(.{
        .key = .app,
        .op = .eq,
        .value = "vim",
    }));
    // Case insensitive
    try testing.expect(state.match(.{
        .key = .app,
        .op = .eq,
        .value = "VIM",
    }));
    try testing.expect(!state.match(.{
        .key = .app,
        .op = .eq,
        .value = "nano",
    }));
    try testing.expect(state.match(.{
        .key = .app,
        .op = .ne,
        .value = "nano",
    }));
}

test "app conditional with command args" {
    const testing = std.testing;
    // Shell integration sends full command with args as title
    const state: State = .{ .app = "vim file.txt" };
    try testing.expect(state.match(.{
        .key = .app,
        .op = .eq,
        .value = "vim",
    }));
    try testing.expect(!state.match(.{
        .key = .app,
        .op = .eq,
        .value = "file.txt",
    }));
}

test "app conditional null handling" {
    const testing = std.testing;
    const state: State = .{ .app = null };
    // When app is null, eq should fail
    try testing.expect(!state.match(.{
        .key = .app,
        .op = .eq,
        .value = "vim",
    }));
    // When app is null, ne should succeed
    try testing.expect(state.match(.{
        .key = .app,
        .op = .ne,
        .value = "vim",
    }));
}

test "Conditional.parse basic" {
    const testing = std.testing;

    // Parse "app=claude"
    const cond1 = Conditional.parse("app=claude").?;
    try testing.expectEqual(Key.app, cond1.key);
    try testing.expectEqual(Conditional.Op.eq, cond1.op);
    try testing.expectEqualStrings("claude", cond1.value);

    // Parse "theme=dark"
    const cond2 = Conditional.parse("theme=dark").?;
    try testing.expectEqual(Key.theme, cond2.key);
    try testing.expectEqual(Conditional.Op.eq, cond2.op);
    try testing.expectEqualStrings("dark", cond2.value);
}

test "Conditional.parse with negation" {
    const testing = std.testing;

    // Parse "app!=vim"
    const cond = Conditional.parse("app!=vim").?;
    try testing.expectEqual(Key.app, cond.key);
    try testing.expectEqual(Conditional.Op.ne, cond.op);
    try testing.expectEqualStrings("vim", cond.value);
}

test "Conditional.parse with whitespace" {
    const testing = std.testing;

    // Parse with spaces around operators
    const cond1 = Conditional.parse("app = claude").?;
    try testing.expectEqual(Key.app, cond1.key);
    try testing.expectEqual(Conditional.Op.eq, cond1.op);
    try testing.expectEqualStrings("claude", cond1.value);

    const cond2 = Conditional.parse("app != vim").?;
    try testing.expectEqual(Key.app, cond2.key);
    try testing.expectEqual(Conditional.Op.ne, cond2.op);
    try testing.expectEqualStrings("vim", cond2.value);
}

test "Conditional.parse invalid" {
    const testing = std.testing;

    // Invalid key
    try testing.expect(Conditional.parse("invalid=value") == null);

    // No operator
    try testing.expect(Conditional.parse("appvalue") == null);

    // Empty string
    try testing.expect(Conditional.parse("") == null);
}
