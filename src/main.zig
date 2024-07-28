const std = @import("std");
const cli = @import("zig-cli");

var config = struct {
    path: []const u8 = ".",
    ignore_hidden: bool = false,
    recursive: bool = false,
}{};

pub fn main() !void {
    var r = try cli.AppRunner.init(std.heap.page_allocator);

    const app = cli.App{
        .command = cli.Command{
            .name = "dpfc",
            .options = &.{
                // Define an Option for the "host" command-line argument.
                .{
                    .long_name = "path",
                    .short_alias = 'p',
                    .help = "path to folder to search (default=.)",
                    .value_ref = r.mkRef(&config.path),
                },

                .{
                    .long_name = "ignore-hidden",
                    .short_alias = 'i',
                    .help = "whether to ignore hidden files starting with dot(.). (default=false)",
                    .value_ref = r.mkRef(&config.ignore_hidden),
                },

                .{
                    .long_name = "recursive",
                    .short_alias = 'r',
                    .help = "whether to check folders recursively (default=false)",
                    .value_ref = r.mkRef(&config.recursive),
                },
            },
            .target = cli.CommandTarget{
                .action = cli.CommandAction{ .exec = run_dpfc },
            },
        },
    };
    return r.run(&app);
}

fn run_dpfc() !void {
    const c = &config;
    std.log.debug("path={s}, recursive={}, hidden={}", .{ c.path, c.recursive, c.ignore_hidden });
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}
