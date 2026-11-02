#!/usr/bin/env python3
"""Create isolated feature and upstream-integration worktrees."""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def git(*args, cwd=ROOT, capture=False):
    return subprocess.run(["git", *args], cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["feature", "sync"])
    parser.add_argument("name", nargs="?")
    args = parser.parse_args()
    if args.command == "feature":
        if not args.name or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", args.name):
            parser.error("Use a short lowercase feature name, for example cloud-status")
        branch = "feature/" + args.name
    else:
        if args.name:
            parser.error("sync does not take a name")
        git("fetch", "upstream", "--prune")
        upstream = git("rev-parse", "upstream/main", capture=True).strip()
        if subprocess.run(["git", "merge-base", "--is-ancestor", upstream, "main"], cwd=ROOT).returncode == 0:
            print("main already includes upstream/main.")
            return
        branch = "sync/files-" + upstream[:10]
    primary = Path(git("worktree", "list", "--porcelain", capture=True).splitlines()[0].removeprefix("worktree "))
    location = primary.parent / (primary.name + "-worktrees") / branch.replace("/", "-")
    location.parent.mkdir(parents=True, exist_ok=True)
    git("worktree", "add", "--no-track", "-b", branch, str(location), "main")
    if args.command == "sync":
        try:
            git("merge", "--no-ff", "--no-edit", upstream, cwd=location)
        except subprocess.CalledProcessError:
            print("Resolve the merge in", location, "or run git merge --abort there. Your main checkout is unchanged.")
            raise SystemExit(1)
    print("Worktree:", location)
    print("Branch:", branch)
    print("Build/test with swift build or swift test in src/Files.Mac.")
    print("After review and testing, fast-forward main to this branch. Package only from the primary checkout.")

if __name__ == "__main__":
    main()
