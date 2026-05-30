const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const File = std.Io.File;

const FileInfo = struct {
    path: []const u8,
    basename_lower: []const u8,
    has_outbound: bool,
    size: u64,
    mtime_ns: i96,
};

fn asciiLower(a: std.mem.Allocator, s: []const u8) ![]u8 {
    const out = try a.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        out[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
    return out;
}

fn normalizeTarget(
    a: std.mem.Allocator,
    inner: []const u8,
) ![]u8 {
    var end = inner.len;
    for (inner, 0..) |c, i| {
        if (c == '|' or c == '#' or c == '^') {
            end = i;
            break;
        }
    }
    var seg = inner[0..end];
    if (std.mem.lastIndexOfScalar(u8, seg, '/')) |s| {
        seg = seg[s + 1 ..];
    }
    seg = std.mem.trim(u8, seg, " \t\r\n");
    return try asciiLower(a, seg);
}

fn scanContent(
    content: []const u8,
    targets: *std.StringHashMap(void),
    arena: std.mem.Allocator,
) !bool {
    var has_outbound = false;
    var i: usize = 0;
    while (i + 1 < content.len) {
        if (content[i] == '[' and content[i + 1] == '[') {
            const start = i + 2;
            var j = start;
            while (j < content.len and content[j] != ']') {
                j += 1;
            }
            if (j + 1 < content.len and content[j + 1] == ']') {
                has_outbound = true;
                const inner = content[start..j];
                const norm = try normalizeTarget(arena, inner);
                const gop = try targets.getOrPut(norm);
                if (gop.found_existing) arena.free(norm);
                i = j + 2;
            } else {
                i = start;
            }
        } else {
            i += 1;
        }
    }
    return has_outbound;
}

fn printHelp(w: *Io.Writer) !void {
    try w.writeAll(
        \\Usage: _orphans [-r ROOT] [-v]
        \\
        \\Find true orphan .md notes — no outbound [[link]] in
        \\content AND no inbound link from any other note.
        \\
        \\  -r, --root DIR  Search root (default: palace/notes)
        \\  -v, --verbose   Show mtime + size
        \\  -h, --help      This help
        \\
    );
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const t_start = Io.Clock.now(.awake, io);

    var root: []const u8 = "palace/notes";
    var verbose = false;

    const args = try init.minimal.args.toSlice(arena);
    var ai: usize = 1;
    while (ai < args.len) : (ai += 1) {
        const a = args[ai];
        if (std.mem.eql(u8, a, "-r") or
            std.mem.eql(u8, a, "--root"))
        {
            ai += 1;
            if (ai >= args.len) std.process.exit(1);
            root = args[ai];
        } else if (std.mem.eql(u8, a, "-v") or
            std.mem.eql(u8, a, "--verbose"))
        {
            verbose = true;
        } else if (std.mem.eql(u8, a, "-h") or
            std.mem.eql(u8, a, "--help"))
        {
            var buf: [4096]u8 = undefined;
            var sw = File.stdout().writer(io, &buf);
            try printHelp(&sw.interface);
            try sw.interface.flush();
            return;
        } else {
            std.process.exit(1);
        }
    }

    var dir = Dir.cwd().openDir(
        io,
        root,
        .{ .iterate = true },
    ) catch |err| {
        var ebuf: [256]u8 = undefined;
        var ew = File.stderr().writer(io, &ebuf);
        try ew.interface.print(
            "Error: cannot open {s}: {}\n",
            .{ root, err },
        );
        try ew.interface.flush();
        std.process.exit(1);
    };
    defer dir.close(io);

    var targets = std.StringHashMap(void).init(gpa);
    defer targets.deinit();

    var files: std.ArrayList(FileInfo) = .empty;
    defer files.deinit(gpa);

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".md")) continue;

        const path_dup = try arena.dupe(u8, entry.path);
        const content = dir.readFileAlloc(
            io,
            entry.path,
            arena,
            .unlimited,
        ) catch continue;

        const has_outbound = try scanContent(content, &targets, arena);

        const base = entry.basename[0 .. entry.basename.len - 3];
        const base_lower = try asciiLower(arena, base);

        var size: u64 = 0;
        var mtime_ns: i96 = 0;
        if (verbose) {
            const st = dir.statFile(io, entry.path, .{}) catch null;
            if (st) |s| {
                size = s.size;
                mtime_ns = s.mtime.nanoseconds;
            }
        }

        try files.append(gpa, .{
            .path = path_dup,
            .basename_lower = base_lower,
            .has_outbound = has_outbound,
            .size = size,
            .mtime_ns = mtime_ns,
        });
    }

    var orphans: std.ArrayList(FileInfo) = .empty;
    defer orphans.deinit(gpa);
    var no_out: usize = 0;
    for (files.items) |f| {
        if (!f.has_outbound) no_out += 1;
        if (f.has_outbound) continue;
        if (targets.contains(f.basename_lower)) continue;
        try orphans.append(gpa, f);
    }

    const Lt = struct {
        fn lt(_: void, a: FileInfo, b: FileInfo) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    };
    std.mem.sort(FileInfo, orphans.items, {}, Lt.lt);

    var buf: [4096]u8 = undefined;
    var sw = File.stdout().writer(io, &buf);
    const w = &sw.interface;

    const root_clean = std.mem.trimEnd(u8, root, "/");

    try w.print(
        "\n  True orphans:  {d} / {d}" ++
            "  (no outbound and no inbound)\n",
        .{ orphans.items.len, files.items.len },
    );
    try w.print(
        "    no outbound : {d}" ++
            "   distinct inbound targets : {d}\n\n",
        .{ no_out, targets.count() },
    );

    for (orphans.items) |f| {
        if (verbose) {
            const secs_i64: i64 = @intCast(
                @divTrunc(f.mtime_ns, std.time.ns_per_s),
            );
            const secs: u64 = if (secs_i64 < 0) 0 else @intCast(secs_i64);
            const es = std.time.epoch.EpochSeconds{ .secs = secs };
            const ed = es.getEpochDay();
            const yd = ed.calculateYearDay();
            const md = yd.calculateMonthDay();
            try w.print(
                "  {d:0>4}-{d:0>2}-{d:0>2}" ++
                    "   {d: >6} B   {s}/{s}\n",
                .{
                    yd.year,
                    md.month.numeric(),
                    @as(u32, md.day_index) + 1,
                    f.size,
                    root_clean,
                    f.path,
                },
            );
        } else {
            try w.print("  {s}/{s}\n", .{ root_clean, f.path });
        }
    }

    const t_end = Io.Clock.now(.awake, io);
    const elapsed_ns: i128 = t_end.nanoseconds - t_start.nanoseconds;
    const elapsed_ms: i64 = @intCast(
        @divTrunc(elapsed_ns, std.time.ns_per_ms),
    );
    try w.writeAll("\n  ── runtime ───────────────────────\n");
    try w.writeAll("  backend : zig\n");
    try w.print("  elapsed : {d} ms\n", .{elapsed_ms});

    try w.flush();
}
