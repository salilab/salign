package salign::constants;

use Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw( MAX_POST_SIZE BUFFER_SIZE MAX_DIR_SIZE );
use strict;

use constant MAX_POST_SIZE => 1073741824; # 1GB maximum upload size
use constant BUFFER_SIZE => 16384; # Buffer size 16Kb

# Never let write directory grow larger than 1 GB
use constant MAX_DIR_SIZE => 1073741824;

1;
