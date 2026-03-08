package TypeConvertor;
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw(MAX_ULONG MAX_LONG MAX_UINT MAX_INT);

use constant MAX_ULONG => 2**64;
use constant MAX_LONG => 2**63 - 1;
use constant MAX_UINT => 2**32;
use constant MAX_INT => 2**31 - 1;

1;