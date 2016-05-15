package Testcase_Writer;

use base qw(Exporter);
use strict;
use warnings;
use File::Copy;
use File::Spec;
use NEXT;


our @EXPORT = qw( Set_Jobs_Path
                  Can_Rerun
                  Compactify_Test_Suite # To get the most unique testcases
                  Rank_Testcases        # To get the most valuable testcases
                  Rank_Runs             # To get the most valuable seeds
                );
our @EXPORT_OK = qw();
our $VERSION   = 1.00;

# Class Variables
my $Coverage_Agents_created = 0;


# Constructor
sub new {
   my ($caller, %args) = @_;
   my $class = ref($caller) || $caller;
   my $this = {
                _session_path => $args{session_path} || '', # The path to the session directory containing information about runs to be dispatched
   };
   $this = bless $this, $class;
   $this->EVERY::LAST::_init(%args); # Initialize the whole inheritance hierarchy (parents first)
   $Coverage_Agents_created++; # This is a "Class Variables". Don't use $caller-> to set its value.
   return $this;
}



sub _init {
   my ($this, %args) = @_;
   # Class-specific initialisation.
   return $this;
}


# Destructor
sub DESTROY {
   my ($this) = @_;
   $this->EVERY::_destroy; # the child classes’ destructors are called prior to their parents.
   return;
}


sub _destroy {
   my ($this) = @_;
   # All the real clean-up occurs here.
   return;
}



# Get Accessors
sub Get_Coverage_Agents_created {
   # This is a "Class Variables". Don't use $this-> to get its value.
#  my ($this) = @_;
   return $Coverage_Agents_created;
}



sub Set_Jobs_Path {
   my ($this, $jobs_path) = @_;
   $this->{_jobs_path} = $jobs_path;
   # Reset all internal data structures
   return;
}



sub Dispatch_Jobs {
   my ($this) = @_;
   my $run_params_fname = 'run_params.txt';
   if ( (not $this->{_idle}) or (not $this->{_jobs_path}) ) {
      return 0;
   }
   else {
      my $jobs_path = $this->{_jobs_path};
      if ((not -d $jobs_path) or (not -e $jobs_path)) {
         die "The passed job path $jobs_path either doesn't refer to a directory or doesn't exist\n";
      }
      opendir(my $jobs_dh, $jobs_path ) or die "Failed to open  $jobs_path:\n$!\n";
      chdir  (   $jobs_dh             ) or die "Failed to enter $jobs_path:\n$!\n";
      foreach my $current_dir ( readdir($jobs_dh) ) {
         if ((not -d $current_dir) || ($current_dir !~ m/^run_(\d+)$/)) { # Skip files and any non-run directory.
            next;
         }
         else {
            # Read the local run_params file.
            opendir(my $run_dh, $current_dir ) or die "Failed to open  $current_dir:\n$!\n";
            chdir(     $run_dh )               or die "Failed to enter $current_dir:\n$!\n";
            open(my $run_params_fh, '<', $run_params_fname) or
                   die "Cannot create $current_dir\/$run_params_fname:\n$!\n";
            local undef $/;
            my $run_params = <$run_params_fh>;
            while ($run_params !~ m/^\s*$/s) { # Read dispatcher-related run parameters
               if ($run_params =~ s/\s*auto_rerun_covscope\s*:\s*()\s*\;\s*/\t/s) {
               }
               elsif ($run_params =~ s/\s*timeout\s*\:\s*(\d+)\s*\;\s*/\t/) {
               }
            }
            close $run_params_fh;
            close $run_dh;
         };
      }
      close $jobs_dh;
      return 1;
   }
}

















1;


__END__



