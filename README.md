This repository consists of self-contained tools for use primarily in or with
Microsoft SQL Server (though some tools can be adapted to other databases) and
are aimed at a SQL Server database developer or administrator. (The tools,
though otherwise self-contained, possibly have a dependency on the scripts in
the Common folder.)

The tools are organized in folders, and documentation may be found within the
file containing the relevant code.

The tools are designed to be backward-compatible with SQL Server 2008, because
it is still in wide use. However, since the next version (SQL Server 2012)
introduced many new features (as well as fixed many bugs), it is sometimes too
big a handicap to restrict oneself to SQL Server 2008-compatible code.

In those cases, either the code has an in-built fork based on the version -- so
that it is still basically usable in SQL Server 2008 while being more efficient
on a later version -- or there are two completely separate versions.

All code in this repository is released under the MIT license (see LICENSE for
the text).