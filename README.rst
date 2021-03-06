==========
desiBackup
==========

|Actions Status|

.. |Actions Status| image:: https://github.com/desihub/desiBackup/workflows/CI/badge.svg
    :target: https://github.com/desihub/desiBackup/actions
    :alt: GitHub Actions CI Status

Introduction
------------

This product contains wrapper scripts on the `HPSSPy`_ package.

.. _`HPSSPy`: https://github.com/weaverba137/hpsspy

Configuring desiBackup
----------------------

desiBackup configuration is provided by the file ``etc/desi.json``.
This file is fully described in the
`HPSSPy configuration document <http://hpsspy.readthedocs.io/en/latest/configuration.html>`_.
Please be sure to read that document before editing the configuration file.
If you need additional help with the configuration, please contact the
DESI Data Systems mailing list.

Using desiBackup
----------------

This package provides the command-line script ``desiBackup.sh`` that
wrappers the `HPSSPy`_ command ``missing_from_hpss``.  The backup applies to
and is intended for entire top-level directory trees.  For example, to perform
a backup of ``spectro/redux/oak1``, one first makes sure that the configuration
is set up to properly map to an HPSS file (see above), then run::

    desiBackup.sh spectro

For additional detail or debugging you can add the ``-v`` option.  The
backup can be *tested* without damaging anything by using the ``-t`` option.

Testing desiBackup
------------------

Currently, desiBackup is tested by ensuring that the file ``etc/desi.json`` is
valid.  Specifically this command is run::

    python -c 'import json; j = open("etc/desi.json"); data = json.load(j); j.close()'

If the file is valid, this command will produce no output.  Invalid files will
raise an exception.

Change Log
----------

0.2.2 (unreleased)
~~~~~~~~~~~~~~~~~~

* Migrated to GitHub Actions for testing.
* Rename top-level ``release/`` to ``public/``; other minor configuration
  changes (PR `#23`_).
* Update configuration for ``mocks/lya_forest/london``, other minor changes
  to other top-level directories (PR `#20`_).
* Update to new /global/cfs filesystem.
* Other miscellaneous updates (PR `#21`_).

.. _`#20`: https://github.com/desihub/desiBackup/pull/20
.. _`#21`: https://github.com/desihub/desiBackup/pull/21
.. _`#23`: https://github.com/desihub/desiBackup/pull/23

0.2.1 (2019-08-20)
~~~~~~~~~~~~~~~~~~

* Allow status comments to be concatenated.
* Add configuration for ``cmx/`` directory (PR `#17`_).
* Additional configuration for ``datachallenge/`` directory (PR `#18`_).
* Backups of 'london' mocks, ``mocks/lya_forest/london/``,
  support for `HPSSPy`_ version 0.5.1 (PR `#19`_).

.. _`#19`: https://github.com/desihub/desiBackup/pull/19
.. _`#18`: https://github.com/desihub/desiBackup/pull/18
.. _`#17`: https://github.com/desihub/desiBackup/pull/17


0.2.0 (2019-05-20)
~~~~~~~~~~~~~~~~~~

This is primarily a reference tag.

* Compatibility with `HPSSPy`_ version 0.5.0 (PR `#11`_).
* Add configuration or at least placeholders for most of the DESI data tree,
  and add monitoring script (PR `#8`_).
* Added Travis test.

.. _`#11`: https://github.com/desihub/desiBackup/pull/11
.. _`#8`: https://github.com/desihub/desiBackup/pull/8

0.1.0 (2017-01-23)
~~~~~~~~~~~~~~~~~~

* Initial reference tag.  Should be used with `HPSSPy`_ version 0.3.0.

License
-------

desiBackup is free software licensed under a 3-clause BSD-style license. For details see
the ``LICENSE.rst`` file.
