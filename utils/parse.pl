#!/usr/bin/perl
#
#-------------------------------------------------------------------
#
# Input File Parsing Utilities: Used to query specific variables
# from .ini style configuration files.
#
# $Id$
#-------------------------------------------------------------------

use Config::IniFiles;

BEGIN {

    my $osf_init_global_config    = 0;
    my $osf_init_local_config     = 0; 
    my $osf_init_os_local_config  = 0; 
    my $osf_init_sync_permissions = 0;
    my $osf_init_sync_kickstarts  = 0;

    my %osf_file_perms = ();

    sub query_global_config_host {

	begin_routine();

	my $host   = shift;
	my $domain = shift;
	my $logr   = get_logger();
	my $found  = 0;

	#$logr->level($DEBUG);

	INFO("   --> Looking for DNS domainname match...($domain)\n");

	foreach(@Clusters) {

	    my $loc_cluster = $_;

	    if ( ! $global_cfg->SectionExists($loc_cluster) ) {
		DEBUG("No Input section found for cluster $loc_cluster\n");
	    } else {
		DEBUG("   --> Scanning $loc_cluster \n");

		if( $global_cfg->exists($loc_cluster,"domainname") ) {
		    my $loc_domain = $global_cfg->val($loc_cluster,"domainname");

		    if($loc_domain =~ m/$domain/ ) {

			DEBUG("      --> Found a matching domain ($loc_domain)\n");
			INFO ("   --> Domain found: Looking for host match...($host)\n");

			my @params = $global_cfg->Parameters($loc_cluster);
			my $num_params = @params;

			foreach(@params) {

			    # Skip the domainname entry

			    if ( $_ eq "domainname" ) { next; }

			    # Look for a matching hostname (exact match first)

			    my $loc_name = $global_cfg->val($loc_cluster,$_);
			    DEBUG("      --> Read $_ = $loc_name\n");
			    if("$host" eq "$loc_name") {
				DEBUG("      --> Found exact match\n");
				$node_cluster = $loc_cluster;
				$node_type    = $_;
				$found        = 1;
				last;
			    }
			}

			foreach(@params) {
			    
			    # Skip the domainname entry

			    if ( $_ eq "domainname" ) { next; }

			    my $loc_name = $global_cfg->val($loc_cluster,$_);
			    DEBUG("      --> Read for regex $_ = $loc_name\n");

			    # Look for a matching hostname (regex match second)

			    if ($host =~ m/\b$loc_name/ ) {
				DEBUG("      --> Found regex match\n");
				$node_cluster = $loc_cluster;
				$node_type    = $_;
				$found        = 1;
				last;
			    }
			}
		    }
		} else {
		    MYERROR("No domainname setting defined for cluster $loc_cluster\n");
		}
	    }
	    
	}

	if( $found == 0 ) {
	    MYERROR("Unable to determine node type for this host/domainname ($host/$domain)",
		    "Please verify global configuration settings and local domainname configuration.\n");
	} else {
	    
	    INFO("   --> Node type determination successful\n");
	    INFO("\n");
	    INFO("   Cluster:Node_Type   = $node_cluster:$node_type\n");
	    INFO("\n");
	}

	return ($node_cluster,$node_type);
	end_routine();
    }

    #---------------------------------------------
    # Init parsing of Global configuration file
    #---------------------------------------------

    sub init_config_file_parsing {
	use File::Basename;

	begin_routine();

	my $infile    = shift;
	my $logr      = get_logger();
	my $shortname = fileparse($infile);

	INFO("   --> Initializing input config_parsing ($shortname)\n");
	
	verify_file_exists($infile);
	
	$global_cfg = new Config::IniFiles( -file => "$infile" );

	#--------------------------------
	# Global cluster name definitions
	#--------------------------------

	my $section="Cluster-Names";

	if ( $global_cfg->SectionExists($section ) ) {
	    INFO("   --> Reading global cluster names\n");

	    @Clusters = split(' ',$global_cfg->val($section,"clusters"));
	    DEBUG(" clusters = @Clusters\n");

	    $num_clusters = @Clusters;
	    if($num_clusters <= 0 ) {
		INFO("   --> No cluster names defined to manage - set clusters variable appropriately\n\n");
		INFO("Exiting.\n\n");
		exit(0);
	    }
	    INFO ("   --> $num_clusters clusters defined:\n");
	    foreach(@Clusters) { INFO("       --> ".$_."\n"); }
	    
	} else {
	    MYERROR("Corrupt configuration: [$section] section not found");
	}
	
	end_routine();
    };

    #---------------------------------------------
    # Init parsing of Cluster-specific input file
    #---------------------------------------------

    sub init_local_config_file_parsing {
	use File::Basename;

	begin_routine();

	if ( $osf_init_local_config == 0 ) {

	    my $infile    = shift;
	    my $logr      = get_logger();
	    my $shortname = fileparse($infile);
	    
	    INFO("   --> Initializing input config_parsing ($shortname)\n");
	    
	    verify_file_exists($infile);
	    
	    $local_cfg = new Config::IniFiles( -file => "$infile", 
					       -allowcontinue => 1,
		                               -nomultiline   => 1);
	    $osf_init_local_config = 1;
	}
	
	end_routine();
    };

    #----------------------------------------------------------------
    # Init parsing of Cluster-specific OS package configuration file
    #----------------------------------------------------------------

    sub init_local_os_config_file_parsing {
	use File::Basename;

	begin_routine();

	if ( $osf_init_os_local_config == 0 ) {

	    my $infile    = shift;
	    my $logr      = get_logger();
	    my $shortname = fileparse($infile);
	    
	    INFO("   --> Initializing OS config_parsing ($shortname)\n");
	    
	    verify_file_exists($infile);
	    
	    $local_os_cfg = new Config::IniFiles( -file => "$infile", 
						  -allowcontinue => 1,
						  -nomultiline   => 1);
	    $osf_init_os_local_config = 1;
	}
	
	end_routine();
    };

    sub query_global_config_os_sync_date {

	begin_routine();

	my $cluster = shift;
	my $host    = shift;
	
	my $logr    = get_logger();
	my $found   = 0;

	INFO("--> Looking for OS Sync Date...($cluster->$host)\n");

	if ( ! $global_cfg->SectionExists("$cluster/os_sync_dates") ) {
	    MYERROR("No Input section found for cluster $cluster/os_sync_dates\n");
	}

	if (defined ($prod_date =  $global_cfg->val("$cluster/os_sync_dates",$host)) ) {
	    DEBUG("-> Read date = $prod_date");
	} else {
	    MYERROR("No sync_date found for host $host");
	}

	return($prod_date);
    }

    sub query_cluster_config_const_sync_files {

	begin_routine();

	my $cluster       = shift;
	my $host          = shift;
		          
	my $logr          = get_logger();
	my @sync_files    = ();
	my @sync_partials = ();

	INFO("   --> Looking for defined files to sync...($cluster->$host)\n");

	if ( ! $local_cfg->SectionExists("ConfigFiles") ) {
	    MYERROR("No Input section found for cluster $cluster [ConfigFiles]\n");
	}

	my @defined_files = $local_cfg->Parameters("ConfigFiles");

	my $num_files = @defined_files;

	INFO("   --> \# of files defined = $num_files\n");

	foreach(@defined_files) {
	    DEBUG("   --> Read value for $_\n");
	    if (defined ($myval = $local_cfg->val("ConfigFiles",$_)) ) {
		DEBUG("   --> Value = $myval\n");
		if ( "$myval" eq "yes" ) {
		    INFO("   --> Sync defined for $_\n");
		    push(@sync_files,$_);
		}
	    } else {
		MYERROR("ConfigFile defined with no value ($_)");
	    }
	}

	end_routine();

	return(@sync_files);
    }

    sub query_cluster_config_os_packages {

	begin_routine();

	my $cluster       = shift;
#	my $host          = shift;
	my $node_type     = shift;
		          
	my $logr          = get_logger();
	my @rpms_defined  = ();
	my %os_rpms       = ();

	INFO("   --> Looking for OS packages to sync...($cluster->$node_type)\n");

	if ( ! $local_os_cfg->SectionExists("OS Packages") ) {
	    MYERROR("No Input section found for cluster $cluster [OS Packages]\n");
	}

#	my @defined_files = $local_cfg->Parameters("OS Packages");
#	my $num_files = @defined_files;
#	INFO("   --> \# of files defined = $num_files\n");

	if($local_os_cfg->exists("OS Packages",$node_type)) {
	    INFO("   --> OS packages defined for node type = $node_type\n");
	    @rpms_defined = $local_os_cfg->val("OS Packages",$node_type);

	    foreach $rpm (@rpms_defined) {
		DEBUG("       --> Read $rpm from config\n");
	    }

	}

	end_routine();

	return(@rpms_defined);
    }


    sub query_cluster_config_partial_sync_files {

	begin_routine();

	my $cluster       = shift;
	my $host          = shift;
		          
	my $logr          = get_logger();
	my @sync_partials = ();

	INFO("   --> Looking for defined files to perform partial sync...($cluster->$host)\n");

	if ( ! $local_cfg->SectionExists("ConfigFiles") ) {
	    MYERROR("No Input section found for cluster $cluster [ConfigFiles]\n");
	}

	my @defined_files = $local_cfg->Parameters("ConfigFiles");

	my $num_files = @defined_files;

	INFO("   --> \# of files defined = $num_files\n");

	foreach(@defined_files) {
	    DEBUG("   --> Read value for $_\n");
	    if (defined ($myval = $local_cfg->val("ConfigFiles",$_)) ) {
		DEBUG("   --> Value = $myval\n");
		if ( "$myval" eq "partial" ) {
		    INFO("   --> Partial sync defined for $_\n");
		    push(@sync_partials,$_);
		}
	    } else {
		MYERROR("ConfigFile defined with no value ($_)");
	    }
	}

	end_routine();

	return(@sync_partials);
    }

    sub query_cluster_config_softlink_sync_files {

	begin_routine();

	my $cluster        = shift;
	my $host           = shift;
		          
	my $logr           = get_logger();
#	my @sync_softlinks = ();
	my %sync_softlinks = ();

	INFO("   --> Looking for defined soft links to sync...($cluster->$host)\n");

	if ( ! $local_cfg->SectionExists("SoftLinks") ) {
	    WARN("No Input section found for cluster $cluster [SoftLinks]\n");
	}

	my @defined_files = $local_cfg->Parameters("SoftLinks");

	my $num_files = @defined_files;

	INFO("   --> \# of soft links defined = $num_files\n");

	foreach(@defined_files) {
	    DEBUG("   --> Read value for $_\n");
	    if (defined ($myval = $local_cfg->val("SoftLinks",$_)) ) {
		DEBUG("   --> Value = $myval\n");
		$sync_softlinks{$_} = $myval;
#		push(@sync_softlinks,$_);
	    }
	}

	end_routine();
	return(%sync_softlinks);
    }

    sub query_cluster_config_host_network_definitions {

	begin_routine();

	my $cluster       = shift;
	my $host          = shift;
		          
	my $logr          = get_logger();
	my %interfaces    = ();

	INFO("   --> Looking for host interface network definitions...($cluster->$host)\n");

	if ( ! $local_cfg->SectionExists("HostInterfaces") ) {
	    MYERROR("No Input section found for cluster $cluster [HostInterfaces]\n");
	}

	my @defined_hosts = $local_cfg->Parameters("HostInterfaces");

	my $num_hosts = @defined_hosts;

	INFO("   --> \# of hosts defined = $num_hosts\n");

	foreach(@defined_hosts) {
	    DEBUG("   --> Read value for $_\n");
	    if (defined (@myvalues = $local_cfg->val("HostInterfaces",$_)) ) {
		print "size of array = ", @myvalues."\n";
#		push(@interfaces,$_);
###		push(@interfaces,@myvalues);
		$interfaces{$_} = @myvalues[0];
#		DEBUG("   --> Value = $myval\n");
#		if ( "$myval" eq "yes" ) {
#		    INFO("   --> Sync defined for $_\n");
#		    push(@sync_files,$_);
#		}
		
	    } else {
		MYERROR("HostInterfaces defined with no value ($_)");
	    }
	}

	end_routine();

	return(%interfaces);
    }

    sub query_cluster_config_services {

	begin_routine();

	my $cluster = shift;
	my $host    = shift;
	my $logr    = get_logger();

	my %inputs  = ();

	INFO("   --> Looking for defined files to sync...($cluster->$host)\n");

	if ( ! $local_cfg->SectionExists("Services") ) {
	    MYERROR("No Input section found for cluster $cluster [Services]\n");
	}

	my @defined_services = ();
	my $section = ();

	if( $host eq "LosF-GLOBAL-NODE-TYPE" ) {
	    $section = "Services";

	    if ( ! $local_cfg->SectionExists($section) ) {
		MYERROR("No Input section found for cluster $cluster [Services]\n");
	    }

	    @defined_services = $local_cfg->Parameters($section);
	} else {

	    $section = "Services/$host";

	    if ( ! $local_cfg->SectionExists($section) ) {
		return(%inputs);
	    }

	    @defined_services = $local_cfg->Parameters($section);
	}

	my $num_entries = @defined_services;

	INFO("   --> \# of services defined = $num_entries\n");

	foreach(@defined_services) {
	    DEBUG("   --> Read value for $_\n");
	    if (defined ($myval = $local_cfg->val($section,$_)) ) {
		DEBUG("   --> Value = $myval\n");
		$inputs{$_} = $myval;
	    } else {
		MYERROR("Services defined with no value ($_)");
	    }
	}

	end_routine();

	return(%inputs);
    }

    sub query_cluster_config_sync_permissions {

	begin_routine();

	if($osf_init_sync_permissions == 0) {

	    my $cluster = shift;
	    my $host    = shift;
	
	    my $logr    = get_logger();
	    
	    %osf_file_perms  = ();

	    INFO("   --> Looking for specific permissions to sync...($cluster->$host)\n");
	    
	    if ( ! $local_cfg->SectionExists("Permissions") ) {
		MYERROR("No Input section found for cluster $cluster [Permissions]\n");
	    }
	    
	    my @perms = $local_cfg->Parameters("Permissions");
	    
	    my $num_entries = @perms;
	    
	    INFO("   --> \# of file permissions to sync = $num_entries\n");
	    
	    foreach(@perms) {
		DEBUG("   --> Read value for $_\n");
		if (defined ($myval = $local_cfg->val("Permissions",$_)) ) {
		    DEBUG("   --> Value = $myval\n");
		    $osf_file_perms{$_} = $myval;
		} else {
		    MYERROR("Permissions defined with no value ($_)");
		}
	    }
	    $osf_init_sync_permissions=1;
	}# end on first entry

	end_routine();
	return(%osf_file_perms);
    }

    sub query_cluster_rpm_dir {

	begin_routine();

	my $cluster = shift;
	my $type    = shift;

	my $logr    = get_logger();
	my $found   = 0;

	INFO("--> Looking for top-level rpm dir...($cluster)\n");

	if (defined ($rpm_topdir = $global_cfg->val("$cluster","rpm_build_dir_$type")) ) {
	    DEBUG("--> Read node specific topdir = $rpm_topdir\n");
	} elsif (defined ($rpm_topdir = $global_cfg->val("$cluster","rpm_build_dir")) ) {
	    DEBUG("--> Read topdir = $rpm_topdir\n");
	} else {
	    MYERROR("No rpm_build_dir defined for cluster $cluster");
	}

	return($rpm_topdir);
    }

    sub query_cluster_config_kickstarts {

	begin_routine();

	my $cluster   = shift;
	my $host_type = shift;
	
	my $logr    = get_logger();
	
	my $kickstart    = "";

	DEBUG("   --> Looking for defined kickstart file...($cluster->$host_type)\n");
	    
	if ( ! $local_cfg->SectionExists("Kickstarts") ) {
	    MYERROR("No Input section found for cluster $cluster [Kickstarts]\n");
	} 
	
	if ( defined ($myval = $local_cfg->val("Kickstarts",$host_type)) ) {
	    DEBUG("   --> Read kickstart   = $myval\n");
	    $kickstart = $myval;
	} else {
	    MYERROR("Kickstart file not defined for node type $host_type - plesae update config.\n");
	}
	
	$osf_init_sync_kickstarts=1;

	end_routine();
	return($kickstart);
    }

    sub query_cluster_config_profiles {

	begin_routine();

	my $cluster   = shift;
	my $host_type = shift;
	
	my $logr      = get_logger();

	my $profile    = "";

	DEBUG("   --> Looking for defined OS imaging profile...($cluster->$host_type)\n");
	    
	if ( ! $local_cfg->SectionExists("Profiles") ) {
	    MYERROR("No Input section found for cluster $cluster [Profiles]\n");
	} 
	
	if ( defined ($myval = $local_cfg->val("Profiles",$host_type)) ) {
	    DEBUG("   --> Read profile   = $myval\n");
	    $profile = $myval;
	} else {
	    MYERROR("OS profile not defined for node type $host_type - plesae update config.\n");
	}
	
	end_routine();
	return($profile);
    }

    sub query_cluster_config_name_servers {

	begin_routine();

	my $cluster   = shift;
	my $host_type = shift;

	my $logr      = get_logger();

	my $value     = "";
	my $section   = "Name-Servers";

	DEBUG("   --> Looking for defined name-server profile...($cluster->$host_type)\n");
	    
	if ( ! $local_cfg->SectionExists("$section") ) {
	    MYERROR("No Input section found for cluster $cluster [$section]\n");
	} 
	
	if ( defined ($myval = $local_cfg->val("$section",$host_type)) ) {
	    DEBUG("   --> Read name-server   = $myval\n");
	    $value = $myval;
	} else {
	    MYERROR("Name server not defined for node type $host_type - plesae update config.\n");
	}
	
	end_routine();
	return($value);
    }

    sub query_cluster_config_name_servers_search {

	begin_routine();

	my $cluster   = shift;
	my $host_type = shift;

	my $logr      = get_logger();

	my $value     = "";
	my $section   = "Name-Servers-Search";

	DEBUG("   --> Looking for defined name-server search profile...($cluster->$host_type)\n");
	    
	if ( ! $local_cfg->SectionExists("$section") ) {
	    MYERROR("No Input section found for cluster $cluster [$section]\n");
	} 
	
	if ( defined ($myval = $local_cfg->val("$section",$host_type)) ) {
	    DEBUG("   --> Read name-server search  = $myval\n");
	    $value = $myval;
	} else {
	    MYERROR("Name server search not defined for node type $host_type - plesae update config.\n");
	}
	
	end_routine();
	return($value);
    }

    sub query_cluster_config_kernel_boot_options {

	begin_routine();

	my $cluster   = shift;
	my $host_type = shift;

	my $logr      = get_logger();

	my $value     = "";
	my $section   = "Kernel-Boot-Options";

	DEBUG("   --> Looking for defined kernel boot options...($cluster->$host_type)\n");
	    
	if ( ! $local_cfg->SectionExists("$section") ) {
	    DEBUG("No Input section found for cluster $cluster [$section]\n");
	    return($value);
	} 
	
	if ( defined ($myval = $local_cfg->val("$section",$host_type)) ) {
	    DEBUG("   --> Read kernel boot option  = $myval\n");
	    $value = $myval;
	} else {
	    DEBUG("No kernel boot options provided for node type $host_type - plesae update config.\n");
	}
	
	end_routine();
	return($value);
    }

}

1;
