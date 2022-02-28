// SPDX-License-Identifier: CC0-1.0
// Made by GreaseMonkey, 2022.

const log_goes_to_stdout = false;

const root = @import("root");
const log_file_name = root.log_file_name;

const std = @import("std");
const log = std.log;

var log_file: ?std.fs.File = null;
var log_writer: ?std.fs.File.Writer = null;

// Calendar month stuff
const day_month_table_entry = struct {
    day: u16,
    month: u16,
};
const days_per_leap_year = 366;
fn calc_day_month(day_offs: u64) day_month_table_entry {
    var day: u64 = day_offs;
    var month: u16 = 0;
    var month_len: u16 = 31;
    while (day >= month_len) {
        day -= month_len;
        month += 1;
        month_len = switch (month) {
            0, 2, 4, 6, 7, 9, 11 => 31,
            1 => 29,
            3, 5, 8, 10 => 30,
            else => unreachable,
        };
    }
    return .{ .day = @intCast(u16, day), .month = month };
}

// Calendar year stuff
const day_year_table_entry = struct {
    day: u16,
    year: u16,
    leap: bool,
};
const days_per_cycle = 146097;
fn calc_day_year(day_offs: u64) day_year_table_entry {
    var day: u64 = day_offs;
    var year: u16 = 0;
    var leap: bool = true;
    var year_len: u16 = (if (leap) 366 else 365);
    while (day >= year_len) {
        day -= year_len;
        year += 1;
        leap = (year == 0 or (year % 4 == 0 and year % 100 != 0));
        year_len = (if (leap) 366 else 365);
    }
    return .{ .day = @intCast(u16, day), .year = year, .leap = leap };
}

pub fn write_to_log_file(comptime msg: []const u8, args: anytype) void {
    // Open log file if necessary
    if (log_file) |_| {
        // All good, do nothing
    } else {
        // There should not be an active writer
        if (log_writer) |_| {
            unreachable;
        }

        if (log_goes_to_stdout) {
            log.notice("Opening log to stdout", .{});
            log_file = std.io.getStdOut();
            log_writer = log_file.?.writer();
            log.notice("Log to stdout opened", .{});
        } else {
            log.notice("Opening log file", .{});
            var fp = std.fs.cwd().createFile(log_file_name, .{
                .read = false,
                .truncate = false,
            }) catch |err| {
                log.err("Log file failed to open, dumping log message here: {}", .{err});
                log.err(msg, args);
                return;
            };
            fp.seekFromEnd(0) catch |err| {
                log.err("Log file failed to seek to end, dumping log message here: {}", .{err});
                log.err(msg, args);
                fp.close();
                return;
            };
            log_file = fp;
            log_writer = log_file.?.writer();
            log.notice("Log file opened", .{});
        }
    }

    // Dump into output first
    log.info(msg, args);

    // Now write to the log
    if (log_writer) |writer| {
        write_log_line(writer, msg, args) catch |err| {
            log.err("Failed to write to log: {}", .{err});
            return;
        };
    } else {
        unreachable;
    }
}

fn write_log_line(writer: anytype, comptime msg: []const u8, args: anytype) !void {
    // timestamp has an epoch of 1970-01-01. We will relocate this to 2000-01-01.
    const time: i64 = std.time.timestamp() - (10957 * 86400);

    // Split into 400-year cycles.
    const cycles: i64 = @divFloor(time, 86400 * (365 * 400 + 97));
    const cycoffs: u64 = @intCast(u64, @mod(time, 86400 * (365 * 400 + 97)));

    // Split into days and seconds.
    const days: u64 = cycoffs / 86400;
    const seconds: u64 = cycoffs % 86400;

    // The time part should be fairly easy.
    const time_hour = seconds / 60 / 60;
    const time_minute = (seconds / 60) % 60;
    const time_second = seconds % 60;

    // Now we need to calculate the year.
    const day_year_split = calc_day_year(days);
    const preyear: u64 = day_year_split.year;
    const preday: u64 = day_year_split.day;
    const leap: bool = day_year_split.leap;
    const date_year: u64 = @bitCast(u64, ((cycles + 5) *% 400) +% @intCast(i64, preyear));

    // And then we need to calculate the month.
    const month_preday: u64 = if (leap or preday < (31 + 28)) preday else preday + 1;
    const day_month_split = calc_day_month(month_preday);
    const date_month: u64 = day_month_split.month + 1;
    const date_day: u64 = day_month_split.day + 1;

    // Now that we have our date, actually print the thing!
    try std.fmt.format(writer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z: ", .{
        date_year,
        date_month,
        date_day,
        time_hour,
        time_minute,
        time_second,
    });
    try std.fmt.format(writer, msg, args);
    try std.fmt.format(writer, "\n", .{});
}
