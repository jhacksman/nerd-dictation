############################################
Security note: ``language_tool_auto_grammar``
############################################

This example config is the **only** piece of the nerd-dictation tree that
makes outbound network requests.

``nerd-dictation.py`` in this directory, if loaded via ``--config``, will send
every transcribed sentence you dictate to
``https://api.languagetoolplus.com/v2/check`` using the third-party
``requests`` library.

**Implications**

- Your dictation text — which by assumption may include anything you would
  type on your keyboard — leaves your machine in cleartext-to-the-TLS-peer
  over HTTPS to languagetoolplus.com.
- You add ``requests`` and its transitive tree (``urllib3``, ``certifi``,
  ``charset-normalizer``, ``idna``) to the set of packages that need to be
  trusted at install time. The hash-pinned vendor tree under ``vendor/``
  already pins these because vosk drags them in anyway, but you are now
  *actually exercising* them in a way the rest of nerd-dictation does not.
- LanguageTool's public API has rate limits and its own privacy policy.
  Read it before using this example with anything sensitive.

**If you want grammar correction without the network exposure**

LanguageTool is open source and can be run locally as a server. Point this
example at ``http://localhost:8010/v2/check`` (or wherever you run it) and
no dictation data will leave your machine.

**If you don't want this example at all**

You can safely delete this directory. Nothing else in the repo imports from
it. The default/audit build of nerd-dictation does not load any example
config unless you explicitly pass ``--config``.
