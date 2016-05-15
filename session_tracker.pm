package Session_Tracker;

use base qw(Exporter);
use strict;
use warnings;
use NEXT;
# Class Variables
my $Session_Trackers_created = 0;

our @EXPORT    = qw( Track_Session_Thread );
our @EXPORT_OK = qw( );
our $VERSION   = 1.00;

use constant SUMMARY_HEADER =>
"
-----------------------------------------------------------------------------\n
---------------------------------- SUMMARY ----------------------------------\n
-----------------------------------------------------------------------------\n
|    RUN ID       |      STATUS  |              CAUSE OF FAILURE             \n
-----------------------------------------------------------------------------\n
";

use constant SUMMARY_FOOTER =>
"-----------------------------------------------------------------------------";


# Constructor
sub new {
   my ($caller, %args) = @_;
   my %defaults = {
                     session_path => "$ENV{REGRESSION_AREA}",
                     session_name => 'default_session',
                  };
   %args = (%defaults, %args);
   my $class = ref($caller) || $caller;
   my $this = { _session_path => $args{session_path},
                _session_name => $args{session_name}, };
   $this = bless $this, $class;
   $this->EVERY::LAST::_init(%args); # Initialize the whole inheritance hierarchy (parents first)
   $Session_Trackers_created++; # This is a "Class Variables". Don't use $caller-> to set its value.
   return $this;
}


sub _init {
   my ($this, %args) = @_;
   # Class-specific initialization.
   return $this;
}


# Destructor
sub DESTROY {
   my ($this) = @_;
   $this->EVERY::_destroy; # the child classes destructors are called prior to their parents.
   return;
}


sub _destroy {
   my ($this) = @_;
   # All the real clean-up occurs here.
   return;
}



# Get Accessors
sub get_Session_Trackers_created {
   # This is a "Class Variable". Don't use $this-> to get its value.
#  my ($this) = @_;
   return $Session_Trackers_created;
}


sub open_to_read {
   my ($file_path) = @_;
   my $fh;
   if ( -e $file_path && -r $file_path) {
      open(my $fh, '<', $file_path) or die "Cannot open $file_path:\n$!\n"
   }
   else {
      die "The file $file_path doesn't exist or is not readable:\n$!\n"
   }
   return $fh;
}



sub Track_Session_Thread {
   my ($this) = @_;
   my $session_vsof_path = $this->{_session_path} . '/' . $this->{_session_name} . '.vsof';
   my $session_ended = 0;
   # Call refresh_session_data once at the beginning of the tracking thread
   $this->refresh_session_data($session_vsof_path);
   # Wait for user trigger
   while(<>) {
      chomp $_;
      if (m/^R$/i) {
         $session_ended = $this->refresh_session_data($session_vsof_path);
         if ($session_ended == 0) {
            last; # Break out of the loop
         }
      }
      elsif (m/^Q$/i) {
         last; # Break out of the loop
      }
      else {
         print "To refresh, type R and press ENTER\n";
      }
   }
   return;
}



sub refresh_session_data {
   my ($this) = @_;
   $this->compose_VSOF();
   my $session_summary = @{ $this->query_VSOF('SUMMARY') }[0];
   print "$session_summary\n";
   return;
}


sub compose_VSOF {
   my ($this) = @_;
   my $jobs_directory    = "$this->{_session_path}" . '/jobs';
   my $session_vsof_path = "$this->{_session_path}" . '/' . "$this->{_session_name}" . '.vsof';
   open(my $session_vsof_fh, '>', $session_vsof_path) or die "Cannot create $session_vsof_path:\n$!\n";
   opendir( my $jobs_dh, $jobs_directory ) or die "Failed to open $jobs_directory: $!\n";
   ############################################################################
   # Write the session parameters.                                            #
   ############################################################################
   my $session_params_path = $this->{_session_path} . '/session_params.txt';
   my $session_params_fh   = open_to_read($session_params_path);
   local undef $/;
   my $session_params = <$session_params_fh>;
   $/ = "\n";
   close $session_params_fh;
   print {$session_vsof_fh} "SESSION {\n"; # Start the session
   print {$session_vsof_fh} "$session_params\n";
   ############################################################################
   # Iterate over all runs in the current jobs directory.                     #
   ############################################################################
   foreach my $current_dir ( readdir($jobs_dh) ) {
      if ((not -d $current_dir) || ($current_dir !~ m/^run_\d+/)) { # Skip files and any non-run directory.
         next;
      }
      else {
         # Update the local VSOF file.
         my $current_run_dir_path = "$jobs_directory" . '/' . "$current_dir";
         my $local_vsof_path = $current_run_dir_path . '/local_vsof.txt';
         $this->update_local_VSOF($current_run_dir_path, 'ALL');
         my $local_vsof_fh = open_to_read($local_vsof_path);
         local undef $/;
         my $local_vsof_contents = <$local_vsof_fh>;
         close $local_vsof_fh;
         print {$session_vsof_fh} "\n$local_vsof_contents\n";
      };
   }
   print {$session_vsof_fh} "};\n"; # Close the session
   close $session_vsof_fh;
   closedir($jobs_dh);
   ############################################################################
   # Prepare the summary section.                                             #
   # - How many tests are currently running and which ones.                   #
   # - How many failed and which ones and what for.                           #
   # - Whether all runs completed (update the $session_ended flag)            #
   ############################################################################
   $this->append_VSOF_summary();
   return;
}


sub append_VSOF_summary {
   my ($this) = @_;
   my $jobs_directory    = "$this->{_session_path}" . '/jobs';
   my $session_vsof_path = "$this->{_session_path}" . '/' . "$this->{_session_name}" . '.vsof';
   my $session_vsof_fh   = open_to_read($session_vsof_path);
   local undef $/;
   my $session_vsof = <$session_vsof_fh>;
   $/ = "\n";
   close $session_vsof_fh;
   open($session_vsof_fh, '>>', $session_vsof_path) or die "Cannot append to $session_vsof_path:\n$!\n";
   print {$session_vsof_fh} '\n';
   print {$session_vsof_fh} "SUMMARY_HEADER";
   my $current_run;
   my $current_failure;
   my $total_failures = 0;
   while ($session_vsof =~ s/\s+(RUN\s*\{.*?\}\s*\;)\s+/\t/s) {
      $current_run = $1;
      if ($current_run =~ m/\s+run_id\s*\:\s*(\d+)\s*\;\s*/s) {
         print {$session_vsof_fh} "|    $1";
      }
      else {
         die "A run without ID is found in $session_vsof_path:\n$!\n";
      }
      if ($current_run !~ m/\s+(failure\s*\{.*?\}\s*\;)\s+/s) {
         if ($current_run !~ m/\s+run_complete\s*\:\s*yes\s*\;\s*/s) {
            print {$session_vsof_fh} "       |   PASSED   |\n";
         }
         else {
            print {$session_vsof_fh} "       |   RUNNING  |\n";
         }
      }
      else {
         $current_failure = $1;
         print {$session_vsof_fh} "       |   FAILED   |";
         $total_failures += 1;
         if ($current_failure =~ m/\s+description\s*\:\s*(.*?)\;\s+/s) { # Description of the first failure encountered.
            print {$session_vsof_fh} "$1\n";
         }
         else {
            print {$session_vsof_fh} "No available description.\n";
         }
      }
   }
   print {$session_vsof_fh} "-----------------------------------------------------------------------------\n";
   print {$session_vsof_fh} "| Total Failures: $total_failures                                            \n";
   print {$session_vsof_fh} "-----------------------------------------------------------------------------\n";
   close $session_vsof_fh;
   return;
}



sub update_local_VSOF {
   my ($this, $run_dir_path, $agent) = @_;
   my $local_vsof_path = $run_dir_path . '/local_vsof.txt';
   open(my $local_vsof_fh, '>', $local_vsof_path ) or die "Cannot create $local_vsof_path:\n$!\n";
   opendir( my $run_dh, $run_dir_path ) or die "Failed to open directory $run_dir_path:\n$!\n";
   ############################################################################
   # Write the run parameters.                                                #
   ############################################################################
   my $run_params_path = $run_dir_path . '/run_params.txt';
   my $run_params_fh   = open_to_read($run_params_path);
   local undef $/;
   my $run_params = <$run_params_fh>;
   $/ = "\n";
   close $run_params_fh;
   print {$local_vsof_fh} "RUN {\n"; # Start the run container
   print {$local_vsof_fh} "$run_params\n";
   ############################################################################
   # Iterate over all LOG files in the run directory.                         #
   ############################################################################
   foreach my $file ( readdir($run_dh) ) {
      if ((not -f $file) || ($file !~ m/log/)) { # Skip directories and any non-log file.
         next;
      }
      else { # Extract information from the local log file
         if (($agent = 'IUS') || ($agent = 'ALL')) {
            # Identify if the file is an IUS log file
            # Open the file and filter it.
            # Write the filtered data in nested-text format.
            # Close the log file.
         }
         if (($agent = 'IES') || ($agent = 'ALL')) {
            # Identify if the file is an IES log file
            # Open the file and filter it.
            # Write the filtered data in nested-text format.
            # Close the log file.
         }
         if (($agent = 'IFV') || ($agent = 'ALL')) {
            # Identify if the file is an IFV log file
            # Open the file and filter it.
            # Write the filtered data in nested-text format.
            # Close the log file.
         }
         if (($agent = 'OVM') || ($agent = 'ALL')) {
            # Identify if the file is an OVM log file
            # Open the file and filter it.
            # Write the filtered data in nested-text format.
            # Close the log file.
         }
      }
   }
   print {$local_vsof_fh} "};\n"; # Close the run container
   close $local_vsof_fh;
   closedir($run_dh);
   ############################################################################
   # The local_vsof.txt doesn't contain a summary section.                    #
   ############################################################################
   return;
}



sub query_VSOF {
   my ($this, $query, @args) = @_;
   my $matches_ref = [ qw( ) ];
   my $session_vsof_path = $this->{_session_path} . '/' . $this->{_session_name} . '.vsof';
   my $fh = open_to_read($session_vsof_path);
   # Extract information from the VSOF File:
   # - How many tests are currently running and which ones.
   # - How many failed and which ones and what for.
   # - Whether all runs completed (update the $session_ended flag)
   undef $/;
   my $vosf_file = <$fh>; # Read whole file
   close $fh;
   my $current_run;
   if ($query == 'SUMMARY') {
      $vosf_file =~ m/\s+(SUMMARY_HEADER.*?SUMMARY_FOOTER)\s+/xs
      push @{ $matches_ref }, $1;
   }
   else {
      while ($vosf_file =~ s/\s+(RUN\s*\{.*?\}\s*\;)\s+/\t/s) {
         $current_run = $1;
         if ($query == 'TESTCASE') {
            my $query_test = $args[0];
            if ($current_run =~ m/\s+testcase\s*\:\s*{$query_test}\s*\;\s*/s) {
               push @{ $matches_ref }, $current_run;
            }
         }
         elsif ($query == 'FAILURES') {
            if ($current_run =~ m/\s+(failure\s+\{.*?\}\;\s+)/s) {
               push @{ $matches_ref }, $current_run;
            }
         }
         elsif ($query == 'SV_SEEDS') { # IUS SV Seeds
            if ($current_run =~ m/\s+(sv_seed\s+\:[-+]?\d+\;\s+)/s) {
               push @{ $matches_ref }, $current_run;
            }
         }
         elsif ($query == 'SEEDS') { # IES Seeds
            if ($current_run =~ m/\s+(seed\s+\:[-+]?\d+\;\s+)/s) {
               push @{ $matches_ref }, $current_run;
            }
         }
         elsif ($query == 'RUN_COMPLETE') {
            if ($current_run =~ m/\s+run_complete\s*\:\s*yes\s*\;\s*/s) {
               push @{ $matches_ref }, $current_run;
            }
         }
      }
   }
   return $matches_ref;
}





1;






__END__



