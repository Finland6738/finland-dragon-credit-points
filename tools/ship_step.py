"""Ship a finished step: one squashed commit, push, pull request, wait for CI, fast-forward main (ADR 0001).

The owner authorised this automation: a milestone step (or a fix) reaches main without waiting for a manual review,
but ONLY when the local checks and the required CI checks are green. On any failure the script stops and leaves the
pull request open, with the reason printed.

Why a fast-forward and not GitHub's squash merge: GitHub writes the squash commit itself and authors it with the
account's primary email, which is personal, and it refuses the noreply address as --author-email ("Invalid email
address"). So the script squashes the step locally into ONE commit authored and committed by the noreply identity,
lets CI check exactly that commit in the pull request, and then pushes the same commit to main as a fast-forward.
GitHub marks the pull request as merged because its head commit is now on main.

Usage, from the repository root, on the step branch (never on main):
  python -I -X utf8 tools/ship_step.py --title "M1-6: codec and transport" --body-file pr.md [--commit "message"]
  --commit "message"   commit every pending change first (git add -A) with this message
  --no-merge           stop after the pull request is open and CI is green
  --dry-run            print what would happen, change nothing

Steps:
  1. refuses to run on main or with a dirty tree (unless --commit);
  2. runs the local checks: tools/check_docs.py and, when it exists, Tests/run_tests.py;
  3. merges origin/main into the branch if main moved (a conflict stops the script);
  4. squashes the branch into one commit on top of origin/main, message = --title, noreply author and committer;
  5. pushes the branch (--force-with-lease: the squash rewrites it) and opens the pull request (or reuses it);
  6. waits for the CI checks of the pull request (gh pr checks --watch);
  7. fast-forwards main to the checked commit (git push origin <sha>:main), stopping if main moved meanwhile,
     deletes the branch, updates the local main and stops if the new main commit is not fully noreply.
     Worktree-safe: when main is checked out in another worktree (the owner's main checkout), the local main cannot be
     moved from here, so the script only runs `git fetch origin` and leaves this worktree detached at origin/main.
The wiki is published by the "Wiki sync" workflow after the push to main, not by this script.
"""
import argparse
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CO_AUTHOR = os.environ.get("FDCP_CO_AUTHOR", "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")
# Personal addresses never go in the history (CLAUDE.md, Privacy): the step commit is authored and committed by the
# noreply identity, whatever the local git configuration says.
NAME = "Finland6738"
EMAIL = "200480737+Finland6738@users.noreply.github.com"
IDENTITY = ["-c", f"user.name={NAME}", "-c", f"user.email={EMAIL}"]


def run(cmd, check=True, capture=True, dry=False):
    print("$ " + " ".join(cmd))
    if dry:
        return subprocess.CompletedProcess(cmd, 0, "", "")
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=capture, text=True)
    if check and proc.returncode != 0:
        sys.exit(f"Stopped: {' '.join(cmd)} failed\n{proc.stderr or proc.stdout}")
    return proc


def out(cmd):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True).stdout.strip()


def local_checks(dry):
    run([sys.executable, "-I", "-X", "utf8", "tools/check_docs.py"], capture=False, dry=dry)
    tests = os.path.join(ROOT, "Tests", "run_tests.py")
    if os.path.isfile(tests):
        # No -I here: lupa may live in the user's site-packages, which isolated mode ignores (CI installs it system-wide
        # and does use -I). The tests fetch the libraries themselves when they are missing.
        run([sys.executable, "-X", "utf8", tests], capture=False, dry=dry)


def squash(title, dry):
    """Leaves the branch as origin/main plus exactly one noreply commit with the same tree."""
    if not dry and out(["git", "rev-list", "--count", "origin/main..HEAD"]) in ("", "0"):
        sys.exit("Stopped: the branch has no change compared with origin/main.")
    run(["git", "reset", "--soft", "origin/main"], dry=dry)
    run(["git", *IDENTITY, "commit", "--author", f"{NAME} <{EMAIL}>", "-m", title + "\n\n" + CO_AUTHOR], dry=dry)


def open_pr(branch, title, body_file, dry):
    existing = out(["gh", "pr", "view", branch, "--json", "number,state", "--jq", "select(.state==\"OPEN\") | .number"])
    if existing:
        print(f"Reusing the open pull request #{existing}.")
        return existing
    if dry:
        print("(dry run) would open a pull request")
        return "0"
    run(["gh", "pr", "create", "--base", "main", "--head", branch, "--title", title, "--body-file", body_file])
    return out(["gh", "pr", "view", branch, "--json", "number", "--jq", ".number"])


def wait_for_checks(number):
    # checks need a few seconds to be registered after the push
    for _ in range(12):
        if out(["gh", "pr", "checks", number, "--json", "name", "--jq", "length"]) not in ("", "0"):
            break
        time.sleep(10)
    proc = subprocess.run(["gh", "pr", "checks", number, "--watch", "--fail-fast", "--interval", "15"], cwd=ROOT)
    if proc.returncode != 0:
        sys.exit(f"Stopped: the CI checks of pull request #{number} are not green. The pull request stays open.")


def fast_forward_main(branch, number, sha):
    run(["git", "fetch", "origin", "main"])
    if out(["git", "rev-parse", f"{sha}^"]) != out(["git", "rev-parse", "origin/main"]):
        sys.exit(f"Stopped: main moved while CI was running. Run the script again on {branch}: it merges main, "
                 f"squashes and waits for CI on the new commit. Pull request #{number} stays open.")
    run(["git", "push", "origin", f"{sha}:refs/heads/main"])
    for _ in range(6):   # GitHub needs a moment to notice that the head commit is on main
        if out(["gh", "pr", "view", number, "--json", "state", "--jq", ".state"]) == "MERGED":
            break
        time.sleep(5)
    run(["git", "push", "origin", "--delete", branch], check=False)
    update_local_main()
    run(["git", "branch", "-D", branch], check=False)
    emails = out(["git", "log", "-1", "--format=%ae %ce", "origin/main"]).split()
    if not emails or not all(e.endswith("@users.noreply.github.com") for e in emails):
        sys.exit(f"Stopped: the main commit of pull request #{number} is not authored and committed by a noreply "
                 "address. Tell the owner; do not ship anything else until it is fixed.")


def main_worktree():
    """The path of the worktree that has main checked out, or "" when no worktree has it."""
    path = ""
    for line in out(["git", "worktree", "list", "--porcelain"]).splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line.strip() == "branch refs/heads/main":
            return path
    return ""


def update_local_main():
    """Brings the local main up to date with origin/main without ever failing the ship.

    - main checked out here: pull --ff-only;
    - main checked out in another worktree (the owner's main checkout): git cannot move a branch that another worktree
      has checked out, and touching that checkout would disturb the owner, so only `git fetch origin` runs; the owner's
      checkout picks the commit up with its next pull;
    - main not checked out anywhere: fast-forward the local branch ref from origin (git fetch origin main:main).
    In the last two cases this worktree is left detached at origin/main, so the step branch can be deleted.
    """
    here = os.path.normcase(os.path.realpath(ROOT))
    owner = main_worktree()
    if owner and os.path.normcase(os.path.realpath(owner)) == here:
        run(["git", "pull", "--ff-only", "origin", "main"], check=False)
        return
    if owner:
        print(f"main is checked out in another worktree ({os.path.basename(owner)}): only fetching origin.")
        run(["git", "fetch", "origin"], check=False)
    else:
        if run(["git", "fetch", "origin", "main:main"], check=False).returncode != 0:
            run(["git", "fetch", "origin"], check=False)
    run(["git", "switch", "--detach", "origin/main"], check=False)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--title", required=True)
    ap.add_argument("--body-file", required=True)
    ap.add_argument("--commit")
    ap.add_argument("--no-merge", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    dry = a.dry_run

    branch = out(["git", "branch", "--show-current"])
    if branch in ("", "main"):
        sys.exit("Stopped: run this on a step branch (step/m1-1-..., fix/..., docs/...), never on main.")
    if not os.path.isfile(os.path.join(ROOT, a.body_file)) and not os.path.isfile(a.body_file):
        sys.exit(f"Stopped: {a.body_file} not found.")

    if out(["git", "status", "--porcelain"]):
        if not a.commit:
            sys.exit("Stopped: there are uncommitted changes. Commit them or pass --commit \"message\".")
        local_checks(dry)
        run(["git", "add", "-A"], dry=dry)
        run(["git", *IDENTITY, "commit", "-m", a.commit + "\n\n" + CO_AUTHOR], dry=dry)
    else:
        local_checks(dry)

    run(["git", "fetch", "origin", "main"], dry=dry)
    if out(["git", "rev-list", "--count", "HEAD..origin/main"]) not in ("", "0"):
        merge = run(["git", *IDENTITY, "merge", "--no-edit", "origin/main"], check=False, dry=dry)
        if merge.returncode != 0:
            run(["git", "merge", "--abort"], check=False, dry=dry)
            sys.exit("Stopped: merging origin/main gives conflicts. Resolve them by hand, run the checks, ship again.")
        local_checks(dry)
    squash(a.title, dry)

    run(["git", "push", "--force-with-lease", "-u", "origin", branch], dry=dry)
    number = open_pr(branch, a.title, a.body_file, dry)
    if dry:
        print("(dry run) would wait for CI and fast-forward main")
        return 0
    sha = out(["git", "rev-parse", "HEAD"])
    wait_for_checks(number)
    if a.no_merge:
        print(f"CI is green. Pull request #{number} left open (--no-merge).")
        return 0
    fast_forward_main(branch, number, sha)
    print(f"Shipped pull request #{number}: main is now {sha[:7]}. The wiki is published by the 'Wiki sync' workflow.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
