#!/usr/bin/perl

use POSIX;
require "getopts.pl";

do Getopts("r:i:m:t:h:w:c:");

$timeout = 5*60;
$n = @ARGV;
if ($n == 0) {
    print <<EOF

Usage: koomie_cf -r <1,2,...n>,<2-5> [OPTIONS] command

where "command" is a command to spawn in parallel across one or more
cluster hosts using ssh. Results of the commands from each host are
written to stdout and are prepended by the executing hostname. If a
host is currently unavailable, it will be skipped. If a host fails to
execute the command before the timeout window completes, the requested
command will be terminated.

OPTIONS:
  --help                  generate help message and exit
  -r <1,2,..n>|<2-5>      operate on a subset list of racks (e.g. -r 101-105); this option
                          can also accept a special rack types (e.g. -r login)
  -c <rack>-<chassis>     operate on a specific rack/chassis combination (.e.g. -c 101-1)
  -m <max_ssh>            maximum number of commands to run in parallel (default = 288)
  -t <timout>             timeout period for command completion in seconds (default = 5 minutes)
  -w <wait>               wait interval (in seconds) between subsequent command spawns (default = 0)

EOF
;
    exit(0);
}

if ($opt_t) {
     $timeout = $opt_t;
}

# if ($opt_h) {
#     @list = split(/,/,$opt_h);
#     foreach $host (@list) {
# 	if ($host =~ /c(\d\d*)[-](\d)(\d\d)/) {
# 	    $c{$1 . "_" . $2} = 1;
# 	    $h{$1 . "_" . $2 . $3} = 1;
# 	} elsif ($host =~ /compute[-](\d\d*)[-](\d)(\d\d)/) {
# 	    $c{$1 . "_" . $2} = 1;
# 	    $h{$1 . "_" . $2 . $3} = 1;
# 	} elsif ($host =~ /oss(\d+?)\b/) {
# 	    print "found valid oss $1\n";
# 	    $oss_nodes{$1} = 1;
# 	} else {
# 	}
#     }
# }



$max_ssh = 288;

if ($opt_m) { $max_ssh = $opt_m; }

#------------------------------------------------
# Koomie'fied version of building up host lists:
#------------------------------------------------

# Chassis Options

if ($opt_c ne "")
{
    if($opt_c =~ m/^(\d\d\d-\d)$/ ) {
	$racks_desired = $1;
    }

}

# Rack Options

if ( $opt_r ne "" ) {

    # are we looking for a rack?

    if ($opt_r =~ m/^(\d\d\d)$/ ) {
	$racks_desired = $1;
    }

    # are we looking for a range of racks?

    if ( $opt_r ne "" ) {
	if ($opt_r =~ m/^(\d\d\d)-(\d\d\d)$/ ) {
	    $rack_begin = $1;
	    $rack_end   = $2;
	    
	    print "rack_begin = $rack_begin\n";
	    print "rack_end   = $rack_end\n";

	    if($rack_end < $rack_begin) {
		die ("Ending rack number is less than beginning rack number ($rack_begin,$rack_end)");
	    }

	    $racks_desired = $rack_begin;
	    
	    for($count=$rack_begin+1;$count<=$rack_end;$count++) {
		$racks_desired = "$count|$racks_desired";
	    }
	}
    }

    # Are we looking for a special type of rack (eg. oss)?

    if ( $opt_r == "oss" ) {
	$racks_desired = oss;
    }

    if ( $opt_r == "login" ) {
	$racks_desired = login;
    }

    print "rack_desired = $racks_desired\n";
#   exit(1);

}

# Scan the host list and mark desired hosts.

open(input, "/etc/hosts");
while(<input>) {

    if (/\bc(\d\d\d)[-](\d)(\d\d)\b/) {
	$myhost    = "c$1-$2"."$3"; # full hostname        (e.g. 301-105)
	$myrack    = $1;	    # rack number          (e.g. 301)
	$myblade   = $2.$3;	    # chassis/host number  (e.g. 105)
	$mychassis = "$1-$2";	    # chassis number       (e.g. 301-1)

#	print "Checking on host $myhost\n";

	if ( $opt_r ne "" ) {
	    if ( $myrack =~ /$racks_desired/ ) {
		$hosts{$myhost} = $myrack*10000 + $myblade;
	    }
	} elsif ( $opt_c ne "" ) {
	    
	    if ( $mychassis =~ /$racks_desired/ ) {
		$hosts{$myhost} = $myrack*10000 + $myblade;
	    }		

	}
    } elsif ( /\boss(\d+?)\b/ && $opt_r eq "oss" ) {
	$rank   = $1;
	$myhost = "oss$rank";

#	print "Checking on oss host $myhost\n";
	$hosts{$myhost} = $rank;

    } elsif ( /\blogin(\d+?)\b/ && $opt_r eq "login" ) {
	$rank   = $1;
	$myhost = "login$rank";
	$hosts{$myhost} = $rank;
    } 

}

@hosts = sort {$hosts{$a} <=> $hosts{$b}} keys%hosts;

$n = 0;
foreach $host (@hosts) {
    $error = "/tmp/zz" . $$ . $host . "_e";
    $output = "/tmp/zz" . $$ . $host . "_o";
    if (!($pid = fork)) {
    	system "ping -w 10 -c 1 $host >/dev/null";
       	if ($?) {
   	    system "echo  down >$error";
	    exit(0);
       	}
	close(STDOUT);
        open(STDOUT, ">$output");
	close(STDERR);
        open(STDERR, ">$error");
	exec  "ssh","-n",$host,@ARGV;
	exit(0);
    }
    if ($opt_w) {  sleep($opt_w);}
    $n++;
    $pid{$pid} = time;
    $pidh{$pid} = $host;
    $pido{$pid} = $output;
    $pide{$pid} = $error;
    do wait_for_it(0);
}

do wait_for_it(1);


sub wait_for_it {
    local($flag) = @_[0];
    while (1) {
	#
        # Process ssh childern output
        #
        while (($pid = POSIX::waitpid( -1, &POSIX::WNOHANG)) > 0) {
	    open(input, $pide{$pid});
	    while (<input>) {
		print "$pidh{$pid} $_";
	    }
	    open(input, $pido{$pid});
	    while (<input>) {
		print "$pidh{$pid} $_";
	    }
	    close(input);
	    unlink($pide{$pid});
	    unlink($pido{$pid});
	    $pid{$pid} = 0;
	    $n--;
	}
        if  ($n) {
            $now = time;
            foreach $pid (keys%pid) {
                if ($pid{$pid} > 0 && ($now - $pid{$pid}) > $timeout) {
                     print "kill $pid $pidh{$pid}\n";
                     kill 9, $pid;
                }
            }
        }
	if ($flag) {
	    if ($n <= 0) { return;}
	} else {
	    if ($n < $max_ssh) { return;}
	}
	sleep(1);
    }
}
