# Bloated Monitoring Tools

Here's a collection of programs written in Zig for the purposes of monitoring things.

All code has been released into the public domain. Enjoy!

They are designed to avoid allocating stuff at runtime. They are truly lightweight.

But because we live in a world where Electron is called what it is, I guess I need to come up with an equally true name for this and thus call it Bloated.

## Building

This currently runs in Zig 0.9.1 because that's what Void Linux has in its repositories right now, but the moment this breaks on the latest Zig release, I'm going to switch over to that.

```
zig build -Drelease-safe
```

is the recommended way to build the code. The results will be in `zig-out/bin/`.

There are also run commands provided. Information is provided under `zig build --help`. For example, to run `ramlog`, you can run this:

```
zig build run-ramlog -Drelease-safe
```

## Programs provided

### `ramlog`

**Supported OSes:** Linux, Windows

Monitors the amount of total RAM and free RAM available and records the result in bytes to `ramlog.log` in the current directory.

Currently logs every 5 seconds. Each log line is 71 bytes. Will go through about ~1.2 MB a day, so be aware of this! (I probably need to make this stuff rotate logs.)
