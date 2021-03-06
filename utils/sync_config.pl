#!/usr/bin/env perl
#-----------------------------------------------------------------------bl-
#--------------------------------------------------------------------------
# 
# LosF - a Linux operating system Framework for HPC clusters
#
# Copyright (C) 2007-2014 Karl W. Schulz <losf@koomie.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the Version 2 GNU General
# Public License as published by the Free Software Foundation.
#
# These programs are distributed in the hope that they will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc. 51 Franklin Street, Fifth Floor, 
# Boston, MA  02110-1301  USA
#
#-----------------------------------------------------------------------el-
# Wrapper to sync all config files/services.
#--------------------------------------------------------------------------

use strict;
use LosF_paths;

use File::Basename;
use File::Compare;
use File::Copy;
use File::Temp qw(tempfile);

use lib "$losf_log4perl_dir";
use lib "$losf_ini4perl_dir";
use lib "$losf_utils_dir";

use LosF_node_types;
use LosF_utils;

require "$losf_utils_dir/utils.pl";
require "$losf_utils_dir/parse.pl";
require "$losf_utils_dir/header.pl";
require "$losf_utils_dir/sync_config_utils.pl";

# Only one LosF instance at a time
losf_get_lock();

parse_and_sync_const_files();
parse_and_sync_softlinks();
parse_and_sync_services();
parse_and_sync_permissions();

# Done with lock

our $LOSF_FH_lock; close($LOSF_FH_lock);

1;

