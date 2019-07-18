==========
desiBackup
==========

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

.. image:: https://img.shields.io/travis/desihub/desiBackup.svg
    :target: https://travis-ci.org/desihub/desiBackup
    :alt: Travis Build Status

Currently, desiBackup is tested by ensuring that the file ``etc/desi.json`` is
valid.  Specifically this command is run::

    python -c 'import json; j = open("etc/desi.json"); data = json.load(j); j.close()'

If the file is valid, this command will produce no output.  Invalid files will
raise an exception.

Change Log
----------

0.2.1 (unreleased)
~~~~~~~~~~~~~~~~~~

* Allow status comments to be concatenated.
* Add configuration for ``cmx/`` directory.
* Additional configuration for ``datachallenge/`` directory.

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
