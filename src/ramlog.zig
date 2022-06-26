// SPDX-License-Identifier: CC0-1.0
// Made by GreaseMonkey, 2022.

// pub const log_level = .info;

pub const log_file_name = "ramlog.log";

const std = @import("std");
const builtin = @import("builtin");
const write_to_log_file = @import("log_to_file.zig").write_to_log_file;

const log = std.log;

// vvv Linux-specific
const meminfo_buffer_size = 256;
var meminfo_buffer: [meminfo_buffer_size]u8 = undefined;
var meminfo_buffer_fill: usize = 0;
var meminfo: struct {
    MemTotal: usize = 0,
    MemAvailable: usize = 0,
} = .{};
const meminfo_typeinfo = @typeInfo(@TypeOf(meminfo)).Struct;
// ^^^ Linux-specific

var ram_total: usize = 0;
var ram_allocatable: usize = 0;

pub fn main() anyerror!void {
    log.info("Starting", .{});

    write_to_log_file("Monitoring started", .{});
    while (true) {
        fetch_ram_usage();
        write_to_log_file("RAM allocatable: {d:15}/{d:15}", .{ ram_allocatable, ram_total });

        // Poll again
        std.time.sleep(5 * std.time.ns_per_s);
    }
}

fn fetch_ram_usage() void {
    log.debug("Fetching memory usage", .{});

    if (builtin.os.tag == .linux) {
        // Linux version
        // Attempt to open meminfo
        var fp = std.fs.openFileAbsolute("/proc/meminfo", .{
            .read = true,
            .write = false,
        }) catch |err| {
            log.err("Could not open meminfo: {s}", .{err});
            return;
        };
        defer fp.close();

        // Read lines
        while (true) {
            // Do a read
            const old_sz = meminfo_buffer_fill;
            if (meminfo_buffer_fill >= meminfo_buffer_size) {
                log.err("Read buffer for meminfo is full", .{});
                return;
            }
            const sz_delta = fp.read(meminfo_buffer[meminfo_buffer_fill..]) catch |err| {
                log.err("Read from meminfo failed: {s}", .{err});
                return;
            };

            // Did we read anything?
            if (sz_delta == 0) {
                // No - we've hit EOF
                if (meminfo_buffer_fill != 0) {
                    log.err("Read from meminfo hit premature EOF", .{});
                    return;
                }

                // HAPPY EXIT CONDITION
                ram_total = meminfo.MemTotal *% 1024;
                ram_allocatable = meminfo.MemAvailable *% 1024;
                return;
            }
            meminfo_buffer_fill += sz_delta;

            // Scan for newlines
            var i: usize = old_sz;
            while (i < meminfo_buffer_fill) {
                if (meminfo_buffer[i] == '\n') {
                    // Parse line
                    {
                        const line = meminfo_buffer[0..i];
                        parse_meminfo_line(line) catch |err| {
                            log.err("meminfo parse error for line [{s}]: {s}", .{ line, err });
                        };
                    }

                    // Copy backwards
                    i += 1;
                    if (i < meminfo_buffer_fill) {
                        std.mem.copy(u8, &meminfo_buffer, meminfo_buffer[i..meminfo_buffer_fill]);
                    }
                    meminfo_buffer_fill -= i;
                    i = 0;
                } else {
                    i += 1;
                }
            }
        }

        //
    } else if (builtin.os.tag == .windows) {
        // Windows version
        const PERFORMANCE_INFORMATION = std.os.windows.PERFORMANCE_INFORMATION;
        var pi: PERFORMANCE_INFORMATION = undefined;
        pi.cb = @sizeOf(@TypeOf(pi));
        const did_gpi = std.os.windows.psapi.GetPerformanceInfo(&pi, @sizeOf(@TypeOf(pi)));
        if (did_gpi != std.os.windows.TRUE) {
            log.err("GetPerformanceInfo failed", .{});
            return;
        }

        ram_total = pi.PhysicalTotal *% pi.PageSize;
        ram_allocatable = pi.PhysicalAvailable *% pi.PageSize;

        //
    } else {
        @compileError("unsupported OS");
    }
}

// For Linux only... or FreeBSD w/ linprocfs mounted --GM
fn parse_meminfo_line(line: []const u8) !void {
    // Extract the name
    var i: usize = 0;
    var token_start: usize = 0;
    var name_opt: ?[]const u8 = null;
    var value: u64 = 0;
    var state: enum {
        read_name,
        read_value,
    } = .read_name;

    while (i < line.len) : (i += 1) {
        const c = line[i];
        switch (state) {
            .read_name => {
                if (c == ':') {
                    name_opt = line[token_start..i];
                    token_start = i + 1;
                    state = .read_value;
                }
            },

            .read_value => {
                if (c >= '0' and c <= '9') {
                    if (value >= @divFloor((1 << 64), 10)) {
                        return error.IntOverflow;
                    }
                    value = (value * 10) + (c - '0');
                }
            },
        }
    }

    if (name_opt) |name| {
        // meminfo
        inline for (meminfo_typeinfo.fields) |f| {
            if (std.mem.eql(u8, name, f.name)) {
                const old_value = @field(meminfo, f.name);
                const new_value = value;
                @field(meminfo, f.name) = value;
                if (old_value != new_value) {
                    log.debug("{s}: {} -> {}", .{ f.name, old_value, new_value });
                }
            }
        }
        // log.debug("Line: [{s}] = {}", .{ name, value });
    }
}
