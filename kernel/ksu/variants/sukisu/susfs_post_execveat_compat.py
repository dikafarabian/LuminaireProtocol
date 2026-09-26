import sys


def main():
    path = sys.argv[1]
    with open(path) as f:
        content = f.read()
    if "ksu_handle_post_execveat_sucompat" in content:
        print("sucompat.c already patched, skipping.")
        sys.exit(0)
    anchor_target = (
        '    pr_info("ksu_handle_stat: su->sh!\\n");\n'
        '    memcpy((void *)((*filename)->name), sh_path, sizeof(sh_path));\n'
        "    return 0;\n"
        "}\n"
        "\n"
        "#else"
    )
    anchor_inject = (
        '    pr_info("ksu_handle_stat: su->sh!\\n");\n'
        '    memcpy((void *)((*filename)->name), sh_path, sizeof(sh_path));\n'
        "    return 0;\n"
        "}\n"
        "\n"
        "int ksu_handle_post_execveat_sucompat(int *__never_use_fd, struct filename **__never_use_filename_ptr,\n"
        "                 void *__never_use_argv, void *__never_use_envp,\n"
        "                 int *__never_use_flags, int *__never_use_retval)\n"
        "{\n"
        "    return 0;\n"
        "}\n"
        "\n"
        "#else"
    )
    if anchor_target not in content:
        print("ERROR: ksu_handle_stat anchor not found!", file=sys.stderr)
        sys.exit(1)
    content = content.replace(anchor_target, anchor_inject, 1)
    with open(path, "w") as f:
        f.write(content)
    print("sucompat.c patched successfully.")


if __name__ == "__main__":
    main()
