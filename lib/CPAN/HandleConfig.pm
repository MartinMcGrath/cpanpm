package CPAN::HandleConfig;
use strict;
use vars qw(%can %keys $dot_cpan $VERSION);

$VERSION = sprintf "%.2f", substr(q$Rev$,4)/100;

%can = (
  'commit' => "Commit changes to disk",
  'defaults' => "Reload defaults from disk",
  'init'   => "Interactive setting of all options",
);

%keys = map { $_ => undef } qw(
    build_cache build_dir bzip2
    cache_metadata commandnumber_in_prompt cpan_home curl
    dontload_hash
    ftp ftp_proxy
    getcwd gpg gzip
    histfile histsize http_proxy
    inactivity_timeout index_expire inhibit_startup_message
    keep_source_where
    lynx
    make make_arg make_install_arg make_install_make_command makepl_arg
    mbuild_arg mbuild_install_arg mbuild_install_build_command mbuildpl_arg
    ncftp ncftpget no_proxy pager
    prefer_installer prerequisites_policy
    scan_cache shell show_upload_date
    tar term_is_latin
    unzip urllist
    wait_list wget
);

# returns true on successful action
sub edit {
    my($self,@args) = @_;
    return unless @args;
    CPAN->debug("self[$self]args[".join(" | ",@args)."]");
    my($o,$str,$func,$args,$key_exists);
    $o = shift @args;
    $DB::single = 1;
    if($can{$o}) {
	$self->$o(args => \@args);
	return 1;
    } else {
        CPAN->debug("o[$o]") if $CPAN::DEBUG;
        unless (exists $keys{$o}) {
            $CPAN::Frontend->mywarn("Warning: unknown configuration variable '$o'\n");
        }
	if ($o =~ /list$/) {
	    $func = shift @args;
	    $func ||= "";
            CPAN->debug("func[$func]") if $CPAN::DEBUG;
            my $changed;
	    # Let's avoid eval, it's easier to comprehend without.
	    if ($func eq "push") {
		push @{$CPAN::Config->{$o}}, @args;
                $changed = 1;
	    } elsif ($func eq "pop") {
		pop @{$CPAN::Config->{$o}};
                $changed = 1;
	    } elsif ($func eq "shift") {
		shift @{$CPAN::Config->{$o}};
                $changed = 1;
	    } elsif ($func eq "unshift") {
		unshift @{$CPAN::Config->{$o}}, @args;
                $changed = 1;
	    } elsif ($func eq "splice") {
		splice @{$CPAN::Config->{$o}}, @args;
                $changed = 1;
	    } elsif (@args) {
		$CPAN::Config->{$o} = [@args];
                $changed = 1;
	    } else {
                $self->prettyprint($o);
	    }
            if ($o eq "urllist" && $changed) {
                # reset the cached values
                undef $CPAN::FTP::Thesite;
                undef $CPAN::FTP::Themethod;
            }
            return $changed;
	} else {
	    $CPAN::Config->{$o} = $args[0] if defined $args[0];
	    $self->prettyprint($o);
	}
    }
}

sub prettyprint {
  my($self,$k) = @_;
  my $v = $CPAN::Config->{$k};
  if (ref $v) {
    my(@report);
    if (ref $v eq "ARRAY") {
      @report = map {"\t[$_]\n"} @$v;
    } else {
      @report = map { sprintf("\t%-18s => %s\n",
                              map { "[$_]" } $_,
                              defined $v->{$_} ? $v->{$_} : "UNDEFINED"
                             )} keys %$v;
    }
    $CPAN::Frontend->myprint(
                             join(
                                  "",
                                  sprintf(
                                          "    %-18s\n",
                                          $k
                                         ),
                                  @report
                                 )
                            );
  } elsif (defined $v) {
    $CPAN::Frontend->myprint(sprintf "    %-18s [%s]\n", $k, $v);
  } else {
    $CPAN::Frontend->myprint(sprintf "    %-18s [%s]\n", $k, "UNDEFINED");
  }
}

sub commit {
    my($self,$configpm) = @_;
    unless (defined $configpm){
	$configpm ||= $INC{"CPAN/MyConfig.pm"};
	$configpm ||= $INC{"CPAN/Config.pm"};
	$configpm || Carp::confess(q{
CPAN::Config::commit called without an argument.
Please specify a filename where to save the configuration or try
"o conf init" to have an interactive course through configing.
});
    }
    my($mode);
    if (-f $configpm) {
	$mode = (stat $configpm)[2];
	if ($mode && ! -w _) {
	    Carp::confess("$configpm is not writable");
	}
    }

    my $msg;
    $msg = <<EOF unless $configpm =~ /MyConfig/;

# This is CPAN.pm's systemwide configuration file. This file provides
# defaults for users, and the values can be changed in a per-user
# configuration file. The user-config file is being looked for as
# ~/.cpan/CPAN/MyConfig.pm.

EOF
    $msg ||= "\n";
    my($fh) = FileHandle->new;
    rename $configpm, "$configpm~" if -f $configpm;
    open $fh, ">$configpm" or
        $CPAN::Frontend->mydie("Couldn't open >$configpm: $!");
    $fh->print(qq[$msg\$CPAN::Config = \{\n]);
    foreach (sort keys %$CPAN::Config) {
	$fh->print(
		   "  '$_' => ",
		   ExtUtils::MakeMaker::neatvalue($CPAN::Config->{$_}),
		   ",\n"
		  );
    }

    $fh->print("};\n1;\n__END__\n");
    close $fh;

    #$mode = 0444 | ( $mode & 0111 ? 0111 : 0 );
    #chmod $mode, $configpm;
###why was that so?    $self->defaults;
    $CPAN::Frontend->myprint("commit: wrote $configpm\n");
    1;
}

*default = \&defaults;
sub defaults {
    my($self) = @_;
    $self->unload;
    $self->load;
    1;
}

sub init {
    my($self,@args) = @_;
    undef $CPAN::Config->{'inhibit_startup_message'}; # lazy trick to
                                                      # have the least
                                                      # important
                                                      # variable
                                                      # undefined
    $self->load(@args);
    1;
}

# This is a piece of repeated code that is abstracted here for
# maintainability.  RMB
#
sub _configpmtest {
    my($configpmdir, $configpmtest) = @_; 
    if (-w $configpmtest) {
        return $configpmtest;
    } elsif (-w $configpmdir) {
        #_#_# following code dumped core on me with 5.003_11, a.k.
        my $configpm_bak = "$configpmtest.bak";
        unlink $configpm_bak if -f $configpm_bak;
        if( -f $configpmtest ) {
            if( rename $configpmtest, $configpm_bak ) {
				$CPAN::Frontend->mywarn(<<END);
Old configuration file $configpmtest
    moved to $configpm_bak
END
	    }
	}
	my $fh = FileHandle->new;
	if ($fh->open(">$configpmtest")) {
	    $fh->print("1;\n");
	    return $configpmtest;
	} else {
	    # Should never happen
	    Carp::confess("Cannot open >$configpmtest");
	}
    } else { return }
}

sub load {
    my($self, %args) = @_;
	$CPAN::Be_Silent++ if $args{be_silent};

    my(@miss);
    use Carp;
    unless ($INC{"CPAN/MyConfig.pm"}) { # this guy has settled his needs already
      eval {require CPAN::Config;}; # not everybody has one
    }
    unless ($dot_cpan++){
      unshift @INC, File::Spec->catdir($ENV{HOME},".cpan");
      eval {require CPAN::MyConfig;}; # override system wide settings
      shift @INC;
    }
    return unless @miss = $self->missing_config_data;

    require CPAN::FirstTime;
    my($configpm,$fh,$redo,$theycalled);
    $redo ||= "";
    $theycalled++ if @miss==1 && $miss[0] eq 'inhibit_startup_message';
    if (defined $INC{"CPAN/Config.pm"} && -w $INC{"CPAN/Config.pm"}) {
	$configpm = $INC{"CPAN/Config.pm"};
	$redo++;
    } elsif (defined $INC{"CPAN/MyConfig.pm"} && -w $INC{"CPAN/MyConfig.pm"}) {
	$configpm = $INC{"CPAN/MyConfig.pm"};
	$redo++;
    } else {
	my($path_to_cpan) = File::Basename::dirname($INC{"CPAN.pm"});
	my($configpmdir) = File::Spec->catdir($path_to_cpan,"CPAN");
	my($configpmtest) = File::Spec->catfile($configpmdir,"Config.pm");
	if (-d $configpmdir or File::Path::mkpath($configpmdir)) {
	    $configpm = _configpmtest($configpmdir,$configpmtest); 
	}
	unless ($configpm) {
	    $configpmdir = File::Spec->catdir($ENV{HOME},".cpan","CPAN");
	    File::Path::mkpath($configpmdir);
	    $configpmtest = File::Spec->catfile($configpmdir,"MyConfig.pm");
	    $configpm = _configpmtest($configpmdir,$configpmtest); 
	    unless ($configpm) {
			my $text = qq{WARNING: CPAN.pm is unable to } .
			  qq{create a configuration file.}; 
			output($text, 'confess');
	    }
	}
    }
    local($") = ", ";
    $CPAN::Frontend->myprint(<<END) if $redo && ! $theycalled;
Sorry, we have to rerun the configuration dialog for CPAN.pm due to
the following indispensable but missing parameters:

@miss
END
    $CPAN::Frontend->myprint(qq{
$configpm initialized.
});

    sleep 2;
    CPAN::FirstTime::init($configpm, %args);
}

sub missing_config_data {
    my(@miss);
    for (
         "build_cache",
         "build_dir",
         "cache_metadata",
         "cpan_home",
         "ftp_proxy",
         "gzip",
         "http_proxy",
         "index_expire",
         "inhibit_startup_message",
         "keep_source_where",
         "make",
         "make_arg",
         "make_install_arg",
         "makepl_arg",
         "mbuild_arg",
         "mbuild_install_arg",
         "mbuild_install_build_command",
         "mbuildpl_arg",
         "no_proxy",
         "pager",
         "prerequisites_policy",
         "scan_cache",
         "tar",
         "unzip",
         "urllist",
        ) {
	push @miss, $_ unless defined $CPAN::Config->{$_};
    }
    return @miss;
}

sub unload {
    delete $INC{'CPAN/MyConfig.pm'};
    delete $INC{'CPAN/Config.pm'};
}

sub help {
    $CPAN::Frontend->myprint(q[
Known options:
  defaults  reload default config values from disk
  commit    commit session changes to disk
  init      go through a dialog to set all parameters

You may edit key values in the follow fashion (the "o" is a literal
letter o):

  o conf build_cache 15

  o conf build_dir "/foo/bar"

  o conf urllist shift

  o conf urllist unshift ftp://ftp.foo.bar/

]);
    undef; #don't reprint CPAN::Config
}

sub cpl {
    my($word,$line,$pos) = @_;
    $word ||= "";
    CPAN->debug("word[$word] line[$line] pos[$pos]") if $CPAN::DEBUG;
    my(@words) = split " ", substr($line,0,$pos+1);
    if (
	defined($words[2])
	and
	(
	 $words[2] =~ /list$/ && @words == 3
	 ||
	 $words[2] =~ /list$/ && @words == 4 && length($word)
	)
       ) {
	return grep /^\Q$word\E/, qw(splice shift unshift pop push);
    } elsif (@words >= 4) {
	return ();
    }
    my %seen;
    my(@o_conf) =  sort grep { !$seen{$_}++ }
        keys %can,
            keys %$CPAN::Config,
                keys %keys;
    return grep /^\Q$word\E/, @o_conf;
}


package ####::###### #hide from indexer
    CPAN::Config;
# note: J. Nick Koston wrote me that they are using
# CPAN::Config->commit although undocumented. I suggested
# CPAN::Shell->o("conf","commit") even when ugly it is at least
# documented

# that's why I added the CPAN::Config class with autoload and
# deprecated warning

use strict;
use vars qw($AUTOLOAD $VERSION);
$VERSION = sprintf "%.2f", substr(q$Rev$,4)/100;

# formerly CPAN::HandleConfig was known as CPAN::Config
sub AUTOLOAD {
  my($l) = $AUTOLOAD;
  $CPAN::Frontend->mywarn("Dispatching deprecated method '$l' to CPAN::HandleConfig");
  $l =~ s/.*:://;
  CPAN::HandleConfig->$l(@_);
}

1;

__END__
# Local Variables:
# mode: cperl
# cperl-indent-level: 2
# End:
