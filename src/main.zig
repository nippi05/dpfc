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
                .action = cli.CommandAction{ .exec = runDpfc },
            },
        },
    };
    return r.run(&app);
}

fn runDpfc() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const cwd = std.fs.cwd();
    const opened_dir = try std.fs.Dir.openDir(cwd, config.path, .{ .iterate = true });

    // TODO(Not that important): Validate that an arrayhashmap is fastest here
    var file_sums = std.AutoHashMap(u64, []u8).init(allocator);
    defer file_sums.deinit();
    var walker = try std.fs.Dir.walk(opened_dir, allocator);
    defer walker.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    while (try walker.next()) |entry| {
        if (entry.kind == .directory) {
            continue;
        }
        const memory = try arena.alloc(u8, entry.path.len);
        @memcpy(memory, entry.path);

        const file_sum = try get_hash(&entry);

        if (try file_sums.fetchPut(file_sum, memory)) |prev| {
            try stdout.print("{s} and {s} are duplicates\n", .{ prev.value, entry.path });
        }
    }

    try bw.flush(); // don't forget to flush!
}

fn get_hash(entry: *const std.fs.Dir.Walker.Entry) !u64 {
    var file = try entry.dir.openFile(entry.basename, .{});
    var br = std.io.bufferedReader(file.reader());
    var reader = br.reader();
    var buffer: [4096]u8 = undefined; // TODO check if 4096 is optimal (or close to it)
    var hasher = std.hash.XxHash64.init(0); // TODO make this either 64 or 32 bit version
    while (try reader.read(&buffer) != 0) { // When returning 0 it has read the whole file
        hasher.update(&buffer);
    }
    return hasher.final();
}
