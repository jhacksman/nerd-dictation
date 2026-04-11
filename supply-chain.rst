############
Supply Chain
############

This document is the result of a security audit of the nerd-dictation tree
done on the ``claude/security-audit-Kk9NJ`` branch. It explains what we do
and do not trust when you install and run nerd-dictation, and what concrete
mitigations live in this fork.

Scope
=====

nerd-dictation is a single-file Python program (``./nerd-dictation``) that:

- Spawns external binaries (``xdotool``, ``ydotool``, ``wtype``, ``dotool``,
  ``parec``, ``sox``, ``pw-cat``) via ``subprocess`` with argument lists
  (never ``shell=True``).
- Loads the ``vosk`` Python package, which in turn loads a compiled
  Kaldi-based C/C++ library via ``cffi``.
- Loads a VOSK speech model from disk.
- Executes a user configuration file as Python (``~/.config/nerd-dictation/
  nerd-dictation.py``) via ``importlib`` if one exists.

The script itself does **no network I/O** (no ``urllib``, no ``requests``,
no ``socket``) and no dynamic code evaluation of dictated text. See the
audit response on the ``claude/security-audit-Kk9NJ`` branch for the
function-level review.


Threat inventory
================

.. list-table::
   :header-rows: 1
   :widths: 20 20 40 20

   * - Component
     - Source
     - How it reaches the running process
     - Mitigation in this fork
   * - ``vosk``
     - pypi.org
     - Python import of a package that also loads native C/C++
     - Hash-pinned in ``vendor/requirements.txt``, wheel committed under
       ``vendor/wheels/``, installed offline via ``vendor/install-offline.sh``
   * - ``cffi``, ``pycparser``
     - pypi.org
     - Transitive of vosk (cffi is the FFI layer for the Kaldi native lib)
     - Hash-pinned, committed, installed offline
   * - ``srt``, ``requests``, ``charset-normalizer``, ``idna``, ``urllib3``,
       ``certifi``, ``tqdm``, ``websockets``
     - pypi.org
     - Transitive of vosk. **vosk's __init__.py eagerly imports srt,
       requests, tqdm, and websockets at module load**, even though
       nerd-dictation never uses any of them. You cannot ``import vosk``
       without these being installed.
     - Hash-pinned, committed, installed offline. We cannot remove them
       without patching vosk.
   * - srt (build path)
     - pypi.org (sdist only)
     - Would run ``setup.py`` at install time
     - We rebuild srt into a wheel in a disposable venv with a pinned
       toolchain and ``SOURCE_DATE_EPOCH``/``PYTHONHASHSEED`` set, so the
       wheel is bit-reproducible; install time runs no Python from srt.
   * - VOSK speech model
     - alphacephei.com (HTTPS)
     - File read by Kaldi; not code, but a poisoned model could make
       recognition type attacker-chosen text into whatever window is
       focused.
     - ``vendor/fetch-model.sh`` downloads over HTTPS with ``curl --fail
       --proto =https --tlsv1.2`` and verifies SHA256 against
       ``vendor/models.sha256`` before unpacking.
   * - ``xdotool`` / ``ydotool`` / ``wtype`` / ``dotool`` / ``parec`` /
       ``sox`` / ``pw-cat``
     - Distro package manager
     - External binaries invoked by name, resolved via ``$PATH``
     - **Not vendored.** Trust comes from distro package signing. Keep
       ``$PATH`` sane and install these from your distro, not random
       binaries off the internet.
   * - Python interpreter, stdlib, glibc, kernel
     - Distro package manager
     - Everything
     - **Not vendored.** Out of scope; use a trusted distro.
   * - ``~/.config/nerd-dictation/nerd-dictation.py``
     - Local filesystem
     - ``importlib`` loads and executes it as a module
     - Documented behavior. Keep ``chmod 700 ~/.config/nerd-dictation``
       and track your config in version control so surprise edits are
       visible.
   * - ``examples/language_tool_auto_grammar/nerd-dictation.py``
     - This repo (but imports ``requests`` and POSTs dictated text to
       ``api.languagetoolplus.com``)
     - Only if explicitly selected as user config via ``--config``
     - See ``examples/language_tool_auto_grammar/SECURITY.rst`` for the
       explicit warning and the local-server mitigation.
   * - This git repo
     - github.com/ideasman42/nerd-dictation (upstream), jhacksman fork
     - ``git clone``
     - Pin the upstream commit you trust. As of writing the audit,
       upstream HEAD was ``41f372789c640e01bb6650339a78312661530843``.


Attack scenarios and why we care
================================

1. **PyPI account takeover on any of the 11 Python packages.** An attacker
   who publishes a malicious release of, say, ``charset-normalizer`` could
   get RCE on every fresh ``pip install vosk``. The hash-pinning under
   ``vendor/requirements.txt`` and the ``--no-index --require-hashes``
   invocation inside ``install-offline.sh`` make this class of attack
   impossible from this repo alone — pip will not install any file whose
   SHA256 does not match the pinned value, and will not reach out to PyPI
   at all during a normal install. To upgrade, a maintainer has to run
   ``fetch-wheels.sh``, which re-downloads everything from PyPI with strict
   hash checking, and then commit the new wheels.

2. **MitM or DNS hijack against alphacephei.com during model download.**
   ``fetch-model.sh`` uses curl with ``--proto =https --tlsv1.2`` (refuses
   non-TLS redirects, floors TLS version) and verifies the downloaded zip
   against a SHA256 pinned in ``vendor/models.sha256`` before unpacking.
   A poisoned model would fail the hash check and the script would abort
   without unpacking.

3. **Dependency confusion / typosquat pulling a package you did not
   intend.** ``--no-index`` in ``install-offline.sh`` means pip never
   consults any index; only the local wheel directory is searched. No
   package that isn't already in ``vendor/wheels/`` can be installed.

4. **Source tarball running setup.py at install time.** The only sdist in
   the tree is ``srt``. We pre-build it into a wheel so ``setup.py`` is
   never executed on the user's machine during install. The rebuild is
   also deterministic, so a reviewer can verify that our wheel is what the
   published sdist builds to.

5. **Upstream nerd-dictation getting a malicious commit.** This fork pins
   to a specific upstream commit. Rebase-aware reviewers should diff
   against that commit when pulling future changes.

6. **Malicious swap of a system binary (``xdotool`` etc.).** Out of scope
   of vendoring. If your distro is compromised, vendoring Python wheels
   doesn't save you. Verify the provenance of any tool you install and
   prefer packages signed by your distro.


Deliberately not fixed
======================

- **vosk eagerly imports requests / websockets / tqdm / srt.** This is
  wasted attack surface — nerd-dictation never uses any of these libraries
  — but removing the imports requires patching vosk upstream. We chose not
  to carry a forked vosk in this fork. If you need a smaller surface,
  upstream a PR to ``alphacep/vosk-api`` to move those imports into the
  helpers that actually use them.

- **The system tools** (``xdotool`` etc.) are resolved via ``$PATH`` and
  not pinned to an absolute path. Pinning to an absolute path would harden
  against ``$PATH`` hijacks but break portability across distros. Users
  who want that can ``alias`` or wrap the binaries.

- **The user config file** at ``~/.config/nerd-dictation/nerd-dictation.py``
  is intentionally arbitrary Python — that's the feature. Don't put
  anything in that directory you wouldn't run with ``python3``.


Verifying the vendor tree
=========================

You can re-verify the entire vendored dependency tree at any time:

.. code-block:: sh

   # Re-downloads from PyPI, rebuilds srt reproducibly, checks every hash.
   # Non-zero exit and a big MISMATCH message on any tampering.
   ./vendor/fetch-wheels.sh

   # Independent sha256sum of the committed wheels against requirements.txt
   # without talking to PyPI at all:
   grep -E 'sha256:' vendor/requirements.txt | while read -r h; do
       echo "$h"
   done
