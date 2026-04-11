######
Vendor
######

This directory contains a hash-pinned, offline-installable copy of
nerd-dictation's Python dependency tree, so that running nerd-dictation does
not require trusting PyPI at install time and does not fetch anything from the
network after the initial refresh.

**Why this exists:** see ``supply-chain.rst`` in the repo root.


Layout
======

=========================   ======================================================
File                        Purpose
=========================   ======================================================
``requirements.txt``        Hash-pinned pip requirements (SHA256 per package).
``wheels/``                 Committed binary wheels / locally-built wheels.
``models.sha256``           Pinned SHA256 hashes for known VOSK speech models.
``install-offline.sh``      Install everything into a venv from ``wheels/``,
                            hash-verified, with ``pip --no-index``.
``fetch-wheels.sh``         Refresh ``wheels/`` from PyPI, rebuild srt
                            reproducibly, and re-verify every hash. Only
                            needed when intentionally bumping a pinned version.
``fetch-model.sh``          Download a VOSK model from alphacephei.com and
                            verify it against ``models.sha256`` before
                            unpacking.
=========================   ======================================================


Normal (offline) install
========================

This is what a user running nerd-dictation from this repo should do:

.. code-block:: sh

   # One-time: install the pinned Python deps into a venv.
   ./vendor/install-offline.sh

   # One-time: fetch a hash-verified VOSK model.
   ./vendor/fetch-model.sh

   # Run nerd-dictation using the venv.
   source venv/bin/activate
   ./nerd-dictation begin

``install-offline.sh`` runs ``pip install --no-index --require-hashes`` against
``vendor/wheels/``. ``--no-index`` means pip will refuse to contact any package
index; ``--require-hashes`` means every file pip installs must match the
SHA256 in ``requirements.txt``. If either check fails, the install aborts.


Refreshing the vendored wheels
==============================

Only do this when you *want* to upgrade a pinned version (for example, a new
``vosk`` release). The refresh:

.. code-block:: sh

   # Downloads every pinned package from PyPI, rebuilds srt reproducibly,
   # and re-verifies every SHA256 in requirements.txt. Fails loudly on any
   # mismatch.
   ./vendor/fetch-wheels.sh

If you bumped a version in ``requirements.txt``, the independent hash check
at the end of ``fetch-wheels.sh`` will fail until you update the ``--hash=``
value to the real hash of the new file. **Do not blindly paste the new hash**
— review the diff, read the changelog for the package you bumped, and only
commit the new wheels once you have convinced yourself the upstream change is
intended and safe.

``fetch-wheels.sh`` treats ``srt`` specially because PyPI only ships it as an
sdist. The script:

1. Downloads ``srt-3.5.3.tar.gz`` from PyPI.
2. Verifies its SHA256 against the upstream hash pinned inside the script
   (``SRT_SDIST_SHA256``). **This is the trust anchor for srt.**
3. Builds a wheel from that exact sdist in a disposable venv that has a
   pinned build toolchain (``pip==24.2``, ``setuptools==75.1.0``,
   ``wheel==0.44.0``), with ``SOURCE_DATE_EPOCH=1577836800`` and
   ``PYTHONHASHSEED=0`` exported. Under those conditions the build is
   bit-reproducible.
4. Verifies the resulting wheel against the hash pinned in
   ``requirements.txt``.

If any of the three tool versions, the env vars, or the sdist change, the
rebuilt wheel hash will change and the script will refuse to overwrite the
committed wheel.


VOSK model
==========

Models are NOT committed to git (40 MB – 2 GB depending on which one). They
are fetched lazily and verified against ``models.sha256`` before being
unpacked.

.. code-block:: sh

   ./vendor/fetch-model.sh                                   # default small en-US
   ./vendor/fetch-model.sh vosk-model-small-en-us-0.15.zip   # explicit
   VOSK_MIRROR=https://your.local.mirror/vosk ./vendor/fetch-model.sh

To add another model: download it once, ``sha256sum`` it, append the line to
``vendor/models.sha256`` along with a comment, and commit.


What is NOT vendored
====================

These are intentionally out of scope because they would require vendoring
the entire OS:

- The Python interpreter itself.
- System audio tools: ``parec``, ``sox``, ``pw-cat``.
- System input-simulation tools: ``xdotool``, ``ydotool``, ``wtype``,
  ``dotool``.
- libc, the kernel, etc.

Trust for these comes from your distribution's package signing. If that
threat model isn't acceptable (for example, you want a reproducible
end-to-end build), the right next step is a Nix or Guix expression that
pins those too — outside the scope of this vendor directory.


Platform coverage
=================

The wheels currently committed target **CPython 3.11 on linux x86_64**
(manylinux). If you need to run on a different Python version or
architecture (aarch64, armv7, Windows, etc.), extend ``requirements.txt``
with the corresponding platform wheels and re-run ``fetch-wheels.sh``. The
hashes of the other vosk platform wheels as published on PyPI at the time
this directory was created:

::

    vosk-0.3.45-py3-none-linux_armv7l.whl
        4221f83287eefe5abbe54fc6f1da5774e9e3ffcbbdca1705a466b341093b072e
    vosk-0.3.45-py3-none-manylinux2014_aarch64.whl
        54efb47dd890e544e9e20f0316413acec7f8680d04ec095c6140ab4e70262704
    vosk-0.3.45-py3-none-manylinux_2_12_x86_64.manylinux2010_x86_64.whl
        25e025093c4399d7278f543568ed8cc5460ac3a4bf48c23673ace1e25d26619f
    vosk-0.3.45-py3-none-win_amd64.whl
        6994ddc68556c7e5730c3b6f6bad13320e3519b13ce3ed2aa25a86724e7c10ac
