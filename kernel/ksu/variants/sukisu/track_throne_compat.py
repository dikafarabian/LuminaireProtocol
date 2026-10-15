import pathlib
import sys

FLAG = "TRACK_THRONE_FORCE_SYNCHRONOUS"
FULL_SCAN = "false"


def defined_elsewhere(source_dir, observer):
    return any(
        FLAG in candidate.read_text(errors="ignore")
        for candidate in source_dir.rglob("*.[ch]")
        if candidate != observer
    )


def main():
    observer = pathlib.Path(sys.argv[1])
    content = observer.read_text()
    if FLAG not in content:
        print("pkg_observer.c has no unresolved track_throne flag, skipping.")
        sys.exit(0)
    if defined_elsewhere(observer.parent.parent, observer):
        print("track_throne flag provided by the source tree, skipping.")
        sys.exit(0)
    observer.write_text(content.replace(FLAG, FULL_SCAN))
    print("pkg_observer.c patched successfully.")


if __name__ == "__main__":
    main()
