# Uruzi

A cool graphics project I made to toy around with zig. It takes an image and
makes particles jump around to trace out & recreate that image. Looks cool.

## Compilation & Installation

To compile you, you need to have the following installed.

- zig 0.16.0 (yes, that's it.)

> [!NOTE]
> I suggest installing zig via [ZVM](https://www.zvm.app/).

Then build using:

```bash
# For debug mode:
$ zig build

# For the fastest possible mode (preferred):
$ zig build -Doptimize=ReleaseFast
```

> [!NOTE]
> You may get some LLD error/warning but they aren't actually errors. They are
> totally benign. Not sure why they happen but probably just a linking bug.

This will create an executable in the `zig-out/bin/` directory.

Alternatively, you can also run it directly by adding the word `run` after `zig
build` i.e.,

```bash
zig build run -Doptimize=ReleaseFast
```

## Usage

Although this compiles to an executable which you can run directly, you can
also pass the image path, and things alike, directly through the CLI. Check out
the `src/cli.zig` file.

## TODO

- Make everything unmanaged (the current code is ugly.)
- Make it fancier.
- Actually read all the TODOs and finish them.

## Meaning behind the project name

Uruzi means "river" in Kinyarwanda—the national language of Rwanda. I actually
wanted a word similar to "fluid" or "flow" but this was the uruzi was the first
word I came across and yeah.

By the way, uruzi is an evolved form of [kesh](https://github.com/ShubhamVG/kesh.git).
