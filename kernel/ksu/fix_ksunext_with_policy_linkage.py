import sys

TARGETS = [
    (
        "static int security_context_to_sid_with_policy(struct selinux_policy *policy, "
        "const char *scontext, u32 scontext_len,",
        "int security_context_to_sid_with_policy(struct selinux_policy *policy, "
        "const char *scontext, u32 scontext_len,",
    ),
    (
        "static int security_sid_to_context_with_policy(struct selinux_policy *policy, "
        "u32 sid, char **scontext,",
        "int security_sid_to_context_with_policy(struct selinux_policy *policy, "
        "u32 sid, char **scontext,",
    ),
    (
        "static void security_compute_av_user_with_policy(struct selinux_policy *policy, "
        "u32 ssid, u32 tsid, u16 tclass,",
        "void security_compute_av_user_with_policy(struct selinux_policy *policy, "
        "u32 ssid, u32 tsid, u16 tclass,",
    ),
]


def main():
    path = sys.argv[1]
    with open(path) as f:
        content = f.read()

    present = [old for old, _ in TARGETS if old in content]

    if not present:
        print(
            "selinux_hide.c: no `static` with_policy forward-declarations found "
            "(already fixed, or fork source changed upstream) — skipping."
        )
        sys.exit(0)

    for old, new in TARGETS:
        if old in content:
            content = content.replace(old, new, 1)

    with open(path, "w") as f:
        f.write(content)

    print("Fixed static/extern linkage mismatch for security_*_with_policy in selinux_hide.c ✅")


if __name__ == "__main__":
    main()
