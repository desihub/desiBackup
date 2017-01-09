==========
desiBackup
==========

Introduction
------------

This product contains wrapper scripts on the `hpsspy`_ package.

.. _`hpsspy`: https://github.com/weaverba137/hpsspy

Configuring desiBackup
----------------------

desiBackup configuration is provided by the file `etc/desi.json`.  Except for
``config``, each top-level keyword in the file corresponds to a top-level
directory in the DESI data tree at NERSC.  For example the "spectro" keyword
corresponds to ``/global/project/projectdirs/desi/spectro``.

Within each section, the keywords correspond to subdirectories of the top-level
directory.  The "exclude" keyword indicates files that should be ignored.
Empty keywords are also ignored.

Within a subdirectory, the configuration consists of a mapping of files
on disk to files on HPSS.  The files on disk are represented by a regular
expression.  For example in the directory "spectro", with subdirectory "redux",
``redux/sjb/dogwood/.*$`` means every file and directory in
``/global/project/projectdirs/desi/spectro/redux/sjb/dogwood``.  It gets
mapped to the file ``redux/sjb/dogwood.tar``, which is an HTAR file.
A slightly more complicated example: In the directory "datachallenge", with
subdirectory "dc2", ``dc2/([^/]+\\.txt)`` maps to ``dc2/\\1``, which means that
any top-level ``.txt`` file gets copied directly to HPSS.

Using desiBackup
----------------

This package provides the command-line script ``desiBackup.sh`` that
wrappers the `hpsspy`_ command ``missing_from_hpss``.  The backup applies to
and is intended for entire top-level directory trees.  For example, to perform
a backup of ``spectro/redux/oak1``, one first makes sure that the configuration
is set up to properly map to an HPSS file (see above), then run::

    desiBackup.sh spectro

For additional detail or debugging you can add the ``-v`` option.

License
-------

See the ``LICENSE.rst`` file.
