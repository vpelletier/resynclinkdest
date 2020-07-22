Re-hardlink directories created using ``rsync --link-dest``.

``rsync --link-dest``
=====================

This is a nice way to make backups which are trivial to restore (cp -a) and use
little disk space. Low-tech enough that I trust it when I often have new files
rather than modified large files.

The problem
===========

Sometimes, because of a user mistake or a bug, you get a new full backup
happening. As a result, a lot of disk space is suddenly allocated for a backup
where little changed. This program is a shot at curing this situation after it
happened.

The algorithm
=============

Let's take the following simple backup content::

  /some/place/2017-01-01/home/foo/bar
  /some/place/2017-01-01/home/foo/boo
  /some/place/2017-01-02/home/foo/bar
  /some/place/2017-01-02/home/foo/baz
  /some/place/2017-01-03/home/foo/bar
  /some/place/2017-01-03/home/foo/baz
  /some/place/2017-01-03/home/foo/boo

It can be seen as a sparse 2d grid where cells in each row are strongly
related (they are more likely to be the same file than accross rows):

+----------------+-------+----------------+----------------+---------------+
| Relative path↓ | Head→ | ``2017-01-01`` | ``2017-01-02`` | ``2017-01-03``|
+================+=======+================+================+===============+
|``/home/foo/bar``       | inode 1                         | inode 3       |
+------------------------+----------------+----------------+---------------+
|``/home/foo/baz``       | (n/a)          | inode 2                        |
+------------------------+----------------+----------------+---------------+
|``/home/foo/boo``       | inode 4        | (n/a)          | inode 5       |
+------------------------+----------------+----------------+---------------+

This tool takes the ``heads`` as arguments (ex: one folder per day).
It resurses through the first head, and, for each non-directory path found,
iterates over the heads on its right, building mapping between inodes and the
heads each inode is in:

.. code:: python

  # relative_path = "/home/foo/bar"
  {
    1: ["2017-01-01", "2017-01-02"],
    3: ["2017-03-03"],
  }

Then, each inode is compared to the others (by picking an arbitrary file in the
list), and each inode identical to a given one gets unlinked and relinked to
that inode.

Optionally (enabled by default), the code then remembers the (relative) path it
just analysed, so that it does not analyse it again when iterating over next
head. This is very efficient, but makes memory usage proportional to the number
of unique relative paths and their length. In my experience, with pypy, this is
under 200MB for over 300k unique relative paths.

Then it goes to the next relative path in current head. Then it moves on to the
next head to process files which did not yet exist in current head.

As a result, execution time is dominated by the number of unique relative paths
instead of the total number of files. For the example above, it will read these
files, in this order, this number of times::

  /some/place/2017-01-01/home/foo/bar
  /some/place/2017-01-03/home/foo/bar
  /some/place/2017-01-01/home/foo/boo
  /some/place/2017-01-03/home/foo/boo
  /some/place/2017-01-02/home/foo/baz

Assuming inodes 1 and 2 are identical, and 4 and 5 are identical, optimal
``rsync --link-dest`` (so without users & code issues) would have produced:

+----------------+-------+----------------+----------------+---------------+
| Relative path↓ | Head→ | ``2017-01-01`` | ``2017-01-02`` | ``2017-01-03``|
+================+=======+================+================+===============+
|``/home/foo/bar``       | inode 1                                         |
+------------------------+----------------+----------------+---------------+
|``/home/foo/baz``       | (n/a)          | inode 2                        |
+------------------------+----------------+----------------+---------------+
|``/home/foo/boo``       | inode 4        | (n/a)          | inode 5       |
+------------------------+----------------+----------------+---------------+

And this script will produce:

+----------------+-------+----------------+----------------+---------------+
| Relative path↓ | Head→ | ``2017-01-01`` | ``2017-01-02`` | ``2017-01-03``|
+================+=======+================+================+===============+
|``/home/foo/bar``       | inode 1                                         |
+------------------------+----------------+----------------+---------------+
|``/home/foo/baz``       | (n/a)          | inode 2                        |
+------------------------+----------------+----------------+---------------+
|``/home/foo/boo``       | inode 4        | (n/a)          | inode 4       |
+------------------------+----------------+----------------+---------------+

An advantage of this method compared to other hard-linkers is that it freezes
space regularly while running by unlinking all homonym duplicates at once.

A disadvantage of this method compared to other hard-linkers is that it will not
link together identical files if their name differs. But neither would
``rsync --link-dest``, so it would not be our backup tool of choice.
