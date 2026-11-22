"""Exercise VoidGit against a disposable Git remote. Pass the compiled wrapper library."""
import ctypes
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def simulator_fixture(directory):
    remote = Path(tempfile.mkdtemp(prefix="void-git-origin-", dir=directory))
    shutil.copytree("ios/TSXProject", remote, dirs_exist_ok=True)
    git(remote, "init", "-q", "-b", "main")
    git(remote, "config", "user.name", "Void Test")
    git(remote, "config", "user.email", "void@example.invalid")
    git(remote, "add", "-A")
    git(remote, "commit", "-qm", "initial TSX project")
    first = git(remote, "rev-parse", "HEAD")
    manifest = remote / "app/manifest.json"
    manifest.write_text(json.dumps({**json.loads(manifest.read_bytes()), "version": "2.0.0"}))
    git(remote, "commit", "-qam", "new version")
    git(remote, "branch", "update")
    manifest.write_text("{")
    git(remote, "commit", "-qam", "invalid manifest")
    git(remote, "branch", "invalid")
    git(remote, "update-ref", "refs/heads/main", first)
    return remote.name


class Checkout:
    def __init__(self, library):
        self.lib = ctypes.CDLL(str(library))
        for name, inputs in [("VoidGitClone", 2), ("VoidGitFetch", 2), ("VoidGitCheckout", 4)]:
            outputs = 1 if name == "VoidGitCheckout" else 2
            getattr(self.lib, name).argtypes = [ctypes.c_char_p] * (inputs + outputs) + [ctypes.c_size_t]

    def call(self, name, *inputs, error=None):
        message = ctypes.create_string_buffer(1024)
        commit = ctypes.create_string_buffer(65)
        outputs = [] if name == "VoidGitCheckout" else [commit]
        code = getattr(self.lib, name)(*map(os.fsencode, inputs), *outputs, message, len(message))
        if error:
            assert code < 0 and error in message.value.decode(), (code, message.value)
        else:
            assert code == 0, message.value.decode()
        return commit.value.decode()


def exercise(root, wrapper):
    remote, live, private = (root / name for name in ["remote", "worktree", "private"])
    remote.mkdir()
    private.mkdir()
    git(remote, "init", "-q", "-b", "development")
    git(remote, "config", "user.name", "Void Test")
    git(remote, "config", "user.email", "void@example.invalid")
    (remote / "app").mkdir()
    entry = Path("app/index.html")
    manifest = Path("app/manifest.json")
    (remote / entry).write_text("first page")
    (remote / manifest).write_text('{"version":"1"}')
    (remote / ".gitignore").write_text("ignored.txt\n")

    def commit(message):
        git(remote, "add", "-A")
        git(remote, "commit", "-qm", message)
        return git(remote, "rev-parse", "HEAD")

    first = commit("first")
    assert wrapper.call("VoidGitClone", remote.as_uri(), live) == first
    database = private / ".git"
    shutil.move(live / ".git", database)
    assert wrapper.call("VoidGitFetch", database, first) == first
    (remote / manifest).write_text('{"version":"2"}')
    second = commit("second")
    assert wrapper.call("VoidGitFetch", database, first) == second

    (live / entry).write_text("local edit")
    (live / "notes.txt").write_text("user data")
    stage = root / "candidate"
    shutil.copytree(live, stage)
    wrapper.call("VoidGitCheckout", database, stage, first, second)
    assert (stage / manifest).read_text() == '{"version":"2"}'
    assert (stage / entry).read_text() == "local edit"
    assert (stage / "notes.txt").read_text() == "user data"
    assert (live / manifest).read_text() == '{"version":"1"}'

    (remote / entry).write_text("remote edit")
    third = commit("third")
    assert wrapper.call("VoidGitFetch", database, second) == third
    wrapper.call("VoidGitCheckout", database, stage, second, third, error="冲突")
    assert (stage / entry).read_text() == "local edit"
    (stage / entry).write_text("first page")
    wrapper.call("VoidGitCheckout", database, stage, second, third)
    assert (stage / entry).read_text() == "remote edit"

    # Incoming files must also respect untracked and ignored local files.
    (remote / "notes.txt").write_text("remote notes")
    (remote / "ignored.txt").write_text("remote ignored")
    git(remote, "add", "-f", "ignored.txt")
    fourth = commit("adds files")
    assert wrapper.call("VoidGitFetch", database, third) == fourth
    (stage / "ignored.txt").write_text("private data")
    wrapper.call("VoidGitCheckout", database, stage, third, fourth, error="冲突")
    assert (stage / "notes.txt").read_text() == "user data"
    (stage / "notes.txt").unlink()
    wrapper.call("VoidGitCheckout", database, stage, third, fourth, error="冲突")
    assert (stage / "ignored.txt").read_text() == "private data"

    git(remote, "checkout", "-qb", "other", first)
    (remote / entry).write_text("different history")
    commit("rewritten")
    git(remote, "branch", "-f", "development", "HEAD")
    wrapper.call("VoidGitFetch", database, third, error="历史已改写")
    git(remote, "branch", "-D", "development")
    wrapper.call("VoidGitFetch", database, third, error="找不到")


if __name__ == "__main__":
    if sys.argv[1] == "--simulator-fixture":
        print(simulator_fixture(sys.argv[2]))
    else:
        with tempfile.TemporaryDirectory() as directory:
            exercise(Path(directory), Checkout(sys.argv[1]))
        print("Git clone, fetch, safe checkout, retry and divergent or missing branch checks passed.")
