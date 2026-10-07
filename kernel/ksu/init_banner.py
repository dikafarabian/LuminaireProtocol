import os
import sys

BANNER_PREFIX = '    pr_info("welcome to KernelSU version '
FUNCTION_HEAD = "int __init kernelsu_init(void)\n{\n"


def stash_path(path):
    return path + ".banner"


def strip(path):
    with open(path) as f:
        lines = f.readlines()
    kept = [line for line in lines if not line.startswith(BANNER_PREFIX)]
    removed = [line for line in lines if line.startswith(BANNER_PREFIX)]
    if not removed:
        print("init.c banner not present, skipping.")
        return
    with open(stash_path(path), "w") as f:
        f.writelines(removed)
    with open(path, "w") as f:
        f.writelines(kept)
    print("init.c banner stashed.")


def restore(path):
    stash = stash_path(path)
    if not os.path.exists(stash):
        print("init.c banner not stashed, skipping.")
        return
    with open(stash) as f:
        banner = f.read()
    with open(path) as f:
        content = f.read()
    if FUNCTION_HEAD not in content:
        print("ERROR: kernelsu_init anchor not found!", file=sys.stderr)
        sys.exit(1)
    content = content.replace(FUNCTION_HEAD, FUNCTION_HEAD + banner, 1)
    with open(path, "w") as f:
        f.write(content)
    os.remove(stash)
    print("init.c banner restored.")


def main():
    mode, path = sys.argv[1], sys.argv[2]
    if mode == "strip":
        strip(path)
    elif mode == "restore":
        restore(path)
    else:
        print("ERROR: unknown mode " + mode, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
