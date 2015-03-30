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
# LosF Regression testing driver.
#--------------------------------------------------------------------------

use strict;

use Test::More;
use Test::More tests => 88;
use File::Basename;
use File::Temp qw(tempfile);
use File::Compare;
use Cwd 'abs_path';
use LosF_test_utils;
use Sys::Hostname;
use Config::IniFiles;

print "---------------------\n";
print "LosF Regression Tests\n";
print "---------------------\n";

my $losf_dir=dirname(dirname(abs_path($0)));
my $redirect = "1> /dev/null";
my $returnCode;
#my $redirect="";

# local hostname

my @hostTmp     = split(/\./,hostname);
my $hostname    = shift(@hostTmp);

sub verify_no_changes_required {
    system("$losf_dir/update -q $redirect" ); $returnCode = $? >> 8;
    ok( $returnCode == 0 ,"update correctly detects no changes required");
}

sub verify_change_required {
    system("$losf_dir/update -q $redirect" ); $returnCode = $? >> 8;
    ok( $returnCode == 1 ,"update correctly detected change required");
}

#------------------------------------------------------

print "\nChecking install manifest:\n";

my @BINS=("losf","update","node_types","koomie_cf",
       "initconfig","sync_config_files","update_hosts");

foreach my $bin (@BINS) {
    test_binary_existence("$losf_dir/$bin");
}

#------------------------------------------------------
print "\nChecking versioning consistency:\n";
my $config_ac="$losf_dir/configure.ac";

ok(-s "$losf_dir/VERSION","version file present");
ok(-s "$losf_dir/configure.ac","configure.ac file present");

my $loc_version=`cat $losf_dir/VERSION`; chomp($loc_version);

open(IN,"$losf_dir/configure.ac") || die "Cannot open configure.ac\n";
ok ( (grep{/\[$loc_version\]/} <IN>) ,"version file matches configure.ac");
close(IN);

my $version_update=`$losf_dir/update -v | grep Version`;
ok ($version_update == "LosF: Version $loc_version","\"update -v\" matches manifest");

my $version_losf=`$losf_dir/losf -v | grep Version`;
ok ($version_update == "LosF: Version $loc_version","\"losf -v\" matches manifest");

my $version_losf=`$losf_dir/losf --version | grep Version`;
ok ($version_update == "LosF: Version $loc_version","\"losf --version\" matches manifest");

#------------------------------------------------------

print "\nInitializing test config ";
my $tmpdir = File::Temp::tempdir(CLEANUP => 0) || die("Unable to create temporary directory");
print "--> tmpdir = $tmpdir\n";

$ENV{'LOSF_CONFIG_DIR'} = "$tmpdir";

ok(system("$losf_dir/initconfig test $redirect") == 0,"initconfig runs");

ok(-s "$tmpdir/config.machines","config.machines exists");
ok(-s "$tmpdir/config.test","config.test exists");
ok(-s "$tmpdir/ips.test","ips.test exists");
ok(-d "$tmpdir/const_files/test/master","const_files/test/master exists");
ok(-s "$tmpdir/os-packages/test/packages.config","os-packages/test/packages.config exists");
ok(-s "$tmpdir/custom-packages/test/packages.config","custom-packages/test/packages.config exists");

# node_type tests
ok(system("$losf_dir/node_types 1> $tmpdir/.result" ) == 0,"node_types runs");

my $igot=(`cat $tmpdir/.result`); 

my $ref_output = <<"END_OUTPUT";
[LosF] Node type:       test -> master
[LosF] Config dir:      $tmpdir
END_OUTPUT

ok("$igot" eq "$ref_output","node_types output ok");

# node_type with argument tests
ok(system("$losf_dir/node_types master 1> $tmpdir/.result" ) == 0,"node_types (w/ argument) runs");

$igot=(`cat $tmpdir/.result`); 
chomp($igot); 

ok("$igot" eq $hostname,"node_types (w/ argument) output ok");

# update tests

ok(system("$losf_dir/update -q  1> $tmpdir/.result" ) == 0,"update runs");

$igot=(`cat $tmpdir/.result`); 
chomp($igot);			# remove newline
$igot =~ s/\e\[\d+m//g;		# remove any colors

my $expect = "OK: [RPMs: OS     0/0  Custom     0/0] [Files:    0/0] [Links:   0/0] [Services:   0/0] [Perms:   0/0] -> master";

ok("$igot" eq "$expect","update output ok");
ok(system("$losf_dir/rpm_topdir -q 1> $tmpdir/.result" ) == 0,"rpm_topdir runs");

open(IN,"<$tmpdir/.result")     || die "Cannot open $tmpdir/.result\n";

my $line = <IN>; chomp($line);
ok($line =~ m/^\[LosF\] Node type:       test -> master$/,"rpm_topdir -> correct node type");

$line = <IN>; chomp($line);
ok($line =~ m/^\[LosF\] Config dir:      $tmpdir$/,"rpm_topdir -> correct config dir");

$line = <IN>; chomp($line);
ok($line =~ m/^\[LosF\] RPM topdir:      $tmpdir\/test\/rpms$/,"rpm_topdir -> correct RPM topdir ");

# -----------------------------------------------------------------------------------------

print "\nChecking permissions update capability using input file $tmpdir/config.test\n";

my $fileMode;

my $local_cfg = new Config::IniFiles( -file => "$tmpdir/config.test",
				   -allowcontinue => 1,
				   -nomultiline   => 1);

ok($local_cfg->SectionExists("Permissions"),"[Permissions] section exists");

my $tmpdir2 = File::Temp::tempdir(CLEANUP => 0) || die("Unable to create temporary directory");
my $testdir = "$tmpdir2/a_test_dir/";
ok(! -d $testdir,"$testdir does not exist previously");
ok($local_cfg->newval("Permissions",$testdir,"750"),"Setting dir perms to 750");
ok($local_cfg->RewriteConfig,"Rewriting config file");
verify_change_required();

ok( -d $testdir,"a_test_dir created");
$fileMode = sprintf("%o",(stat($testdir))[2] &07777);
ok($fileMode eq "750","a_test_dir has correct 750 permissions"); verify_no_changes_required();

ok($local_cfg->setval("Permissions",$testdir,"700"),"Setting dir perms to 700");
ok($local_cfg->RewriteConfig,"Rewriting config file");
verify_change_required();

$fileMode = sprintf("%o",(stat($testdir))[2] &07777);
ok($fileMode eq "700","a_test_dir has correct 700 permissions"); verify_no_changes_required();

print "\nChecking permissions override capability for specific node-type\n";
ok($local_cfg->newval("Permissions/master",$testdir,"600"),"Setting dir perms to 600");
ok($local_cfg->RewriteConfig,"Rewriting config file");
verify_change_required();
$fileMode = sprintf("%o",(stat($testdir))[2] &07777);
ok($fileMode eq "600","a_test_dir has correct 600 permissions"); verify_no_changes_required();

print "\nChecking removal of global permissions setting\n";
ok($local_cfg->delval("Permissions",$testdir),"Removing global permissions setting");
ok($local_cfg->RewriteConfig,"Rewriting config file");
system("chmod 700 $testdir");
verify_change_required();
$fileMode = sprintf("%o",(stat($testdir))[2] &07777);
ok($fileMode eq "600","a_test_dir still has correct 600 permissions"); verify_no_changes_required();

print "\nChecking use of sync_config_files to update permissions within chroot environment\n";

my $global_cfg = new Config::IniFiles( -file => "$tmpdir/config.machines",-allowcontinue => 1,-nomultiline   => 1);

$local_cfg->delval("Permissions/master",$testdir);
$local_cfg->newval("Permissions/master","$tmpdir2/images/",755);
$local_cfg->RewriteConfig;

ok($local_cfg->newval("Provisioning","mode","Warewulf"),"enable chroot Warewulf env");
ok($local_cfg->newval("Warewulf","compute","$tmpdir2/images"),"define chroot dir");
ok($local_cfg->RewriteConfig,"Rewriting config file");
ok($global_cfg->newval("test","compute","c[1-4]"),"define compute node type regex");
ok($global_cfg->RewriteConfig,"Rewriting config file");

system("$losf_dir/update -q 1> $tmpdir/.result");
$igot=(`cat $tmpdir/.result`);

$ref_output = << "EOF";
   --> UPDATING: Desired directory $tmpdir2/images/ does not exist...creating
UPDATED: [RPMs: OS     0/0  Custom     0/0] [Files:    0/0] [Links:   0/0] [Services:   0/0] [Perms:   1/1] -> master
OK: [RPMs: OS     0/0  Custom     0/0] [Files:    0/0] [Links:   0/0] [Services:   0/0] [Perms:   0/0] -> compute
EOF
ok("$igot" eq "$ref_output","update applied to master node type only");
ok(-d "$tmpdir2/images","images/ directory created");
ok(! -e "$tmpdir2/images/$tmpdir2/images","images/ directory not present in compute chroot path");

$local_cfg->newval("Permissions/compute","b_test_dir/","755");
$local_cfg->RewriteConfig;
system("$losf_dir/update -q 1> $tmpdir/.result");
$igot=(`cat $tmpdir/.result`);
$ref_output = << "EOF";
OK: [RPMs: OS     0/0  Custom     0/0] [Files:    0/0] [Links:   0/0] [Services:   0/0] [Perms:   0/1] -> master
   --> UPDATING: Desired directory $tmpdir2/images/b_test_dir/ does not exist...creating
UPDATED: [RPMs: OS     0/0  Custom     0/0] [Files:    0/0] [Links:   0/0] [Services:   0/0] [Perms:   1/1] -> compute
EOF
ok("$igot" eq "$ref_output","update applied to compute node type only");
ok(-d "$tmpdir2/images/b_test_dir","$tmpdir2/images/b_test_dir/ directory created");
$fileMode = sprintf("%o",(stat("$tmpdir2/images/b_test_dir"))[2] &07777);
ok($fileMode eq "755","b_test_dir has correct 755 permissions"); verify_no_changes_required();

#----------------------------------------
print "\nChecking losf addrpm\n";
#----------------------------------------

system("rpm -q foo $redirect"); $returnCode =$? >> 8;
ok($returnCode == 1,"custom rpm foo is not installed");
system("../losf -y addrpm foo-1.0-1.x86_64.rpm $redirect"); $returnCode =$? >> 8;
ok($returnCode == 0,"losf addrpm foo-1.0-1.x86_64.rpm ran ok");
ok(-s "$tmpdir/test/rpms/x86_64/foo-1.0-1.x86_64.rpm","rpm file correctly cached in rpm_topdir");

my $custom_cfg = new Config::IniFiles( -file => "$tmpdir/custom-packages/test/packages.config",
				       -allowcontinue => 1,-nomultiline   => 1);
ok($custom_cfg->SectionExists("Custom Packages"),"[Custom Packages] section exists");
my $value = $custom_cfg->val("Custom Packages","master");
ok($value eq "foo-1.0-1.x86_64 name=foo version=1.0 release=1 arch=x86_64 181fdd67f04def176cf486a156476f25 NODEPS IGNORESIZE",
    "packages.config file contains correct entry for package foo");
verify_change_required();
system("rpm -q foo 1> $tmpdir/.result");
$igot=(`cat $tmpdir/.result`);chomp($igot);
ok($igot eq "foo-1.0-1.x86_64","foo-1.0-1.x86_64 is installed after update");
system("rpm -V foo"); $returnCode =$? >> 8;
ok($returnCode == 0,"foo rpm verifies");

# Verify we can't re-add same rpm with the same name
system("../losf -y addrpm duplicate/foo-1.0-1.x86_64.rpm $redirect"); $returnCode =$? >> 8;
ok($returnCode == 1,"repeat try of losf addrpm duplicate/foo-1.0-1.x86_64.rpm failed as expected");

# make sure no change made to foo setting
$custom_cfg->ReadConfig;
my $value = $custom_cfg->val("Custom Packages","master");
ok($value eq "foo-1.0-1.x86_64 name=foo version=1.0 release=1 arch=x86_64 181fdd67f04def176cf486a156476f25 NODEPS IGNORESIZE",
    "packages.config file contains correct entry for package foo");

# Verify we can't add a previously unregistered rpm when the same filename is present in cache_dir (Issue #59)
system("rpm -e foo");
ok($custom_cfg->delval("Custom Packages","master"),"remove previous config for package foo");
ok($custom_cfg->RewriteConfig,"Rewriting config file");
verify_no_changes_required();
system("../losf -y addrpm duplicate_rpm/foo-1.0-1.x86_64.rpm $redirect"); $returnCode =$? >> 8;
ok($returnCode == 1,"losf addrpm failed when cached rpm already present");
verify_no_changes_required();
# make sure the config file was not updated
my $value = $custom_cfg->val("Custom Packages","master");
ok("$value" eq "","erroneous addrpm request did not update config");

# test upgrade of custom rpm

system("rm $tmpdir/test/rpms/x86_64/*.rpm");
system("../losf -y addrpm foo-1.0-1.x86_64.rpm $redirect"); $returnCode =$? >> 8;
system("../update $redirect");
system("rpm -q foo 1> $tmpdir/.result");
$igot=(`cat $tmpdir/.result`);chomp($igot);
ok($igot eq "foo-1.0-1.x86_64","reinstall foo-1.0-1.x86_64");
system("../losf -y addrpm ./foo-1.0-2.x86_64.rpm $redirect"); $returnCode =$? >> 8;
ok($returnCode == 1,"addrpm correctly fails without upgrade request");
verify_no_changes_required();
system("../losf -y addrpm --upgrade foo-1.0-2.x86_64.rpm $redirect"); $returnCode =$? >> 8;
ok($returnCode == 0,"addrpm --upgrade foo-1.0-2.x86_64.rpm ok");
verify_change_required;
system("rpm -q foo 1> $tmpdir/.result");
$igot=(`cat $tmpdir/.result`);chomp($igot);
ok($igot eq "foo-1.0-2.x86_64","foo-1.0-2.x86_64 is installed after update");
system("rpm -V foo"); $returnCode =$? >> 8;
ok($returnCode == 0,"foo-1.0-2.x86_64 rpm verifies");

system("rpm -e foo");

close(IN);

done_testing();


