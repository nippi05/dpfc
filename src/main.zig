const std = @import("std");
const cli = @import("zig-cli");

const Config = struct {
    path: []const u8,
    ignore_hidden: bool,
    recursive: bool,
    use_abs_path: bool,
};

var global_config = Config{
    .path = ".",
    .ignore_hidden = false,
    .recursive = true,
    .use_abs_path = false,
};

pub fn main() !void {
    var r = try cli.AppRunner.init(std.heap.page_allocator);

    const app = cli.App{
        .command = cli.Command{
            .name = "dpfc",
            .description = .{
                .one_line = "DuPlicate File Checker",
                .detailed =
                \\Check for duplicate files in a given directory
                \\With options to skip hidden files, search only
                \\in one folder or recursively and outputting 
                \\relative or abs path.
                ,
            },
            .options = &.{
                // Define an Option for the "host" command-line argument.
                .{
                    .long_name = "path",
                    .short_alias = 'p',
                    .help = "path to folder to search (default=.)",
                    .value_ref = r.mkRef(&global_config.path),
                },

                .{
                    .long_name = "ignore-hidden",
                    .short_alias = 'i',
                    .help = "ignore hidden files starting with dot. (default=false)",
                    .value_ref = r.mkRef(&global_config.ignore_hidden),
                },

                .{
                    .long_name = "recursive",
                    .short_alias = 'r',
                    .help = "check folders recursively (default=true)",
                    .value_ref = r.mkRef(&global_config.recursive),
                },

                .{
                    .long_name = "absolute-path",
                    .short_alias = 'a',
                    .help = "ouput absolute path instead of relative path (default=false)",
                    .value_ref = r.mkRef(&global_config.use_abs_path),
                },
            },
            .target = cli.CommandTarget{
                .action = cli.CommandAction{ .exec = start_point },
            },
        },
    };
    return r.run(&app);
}

fn start_point() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    try dpfc(allocator, std.io.getStdOut(), global_config);
}

fn dpfc(allocator: std.mem.Allocator, output_file: std.fs.File, config: Config) !void {
    if (!config.recursive or config.use_abs_path) {
        unreachable; // Unimplemented
    }

    const stdout_file = output_file.writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const cwd = std.fs.cwd();
    const opened_dir = try std.fs.Dir.openDir(
        cwd,
        config.path,
        .{ .iterate = true },
    );

    // TODO(Not that important): Validate that an arrayhashmap is fastest here
    var file_hashes = std.AutoHashMap(u64, []u8)
        .init(allocator);
    defer file_hashes.deinit();

    var walker = try std.fs.Dir.walk(opened_dir, allocator);
    defer walker.deinit();

    // Arena allocator because everything should be freed at the same time anyways.
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    while (try walker.next()) |entry| {
        if (entry.kind == .directory or (config.ignore_hidden and entry.basename[0] == '.')) {
            continue;
        }
        const persistent_path = try arena.alloc(u8, entry.path.len);
        @memcpy(persistent_path, entry.path);

        const current_hash = try get_hash(&entry);

        if (try file_hashes.fetchPut(current_hash, persistent_path)) |prev| {
            try stdout.print("{s} and {s} are duplicates\n", .{
                prev.value,
                entry.path,
            });
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
