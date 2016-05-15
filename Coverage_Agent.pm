package Coverage_Agent;

use base qw(Exporter);
use strict;
use warnings;
use File::Copy;
use File::Spec;
use NEXT;


our @EXPORT = qw( Set_Session_Reader
                  Set_vPlan_Reader
                  Can_Rerun
                  Compactify_Test_Suite # To get the most unique testcases
                  Rank_Testcases        # To get the most valuable testcases
                  Rank_Runs             # To get the most valuable seeds
                  Get_Coverage_Agents_created
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
                _session_path     => $args{session_path} || '', # The path to the session directory containing information about runs to be dispatched
                _vPlan_Reader     => $args{vPlan_Reader},       # A reference to a vPlan Reader object.
                _CDV_Dispatcher   => $args{CDV_Dispatcher},     # A reference to a CDV_Dispatcher object.
                _vsif_Reader      => undef,                     # The path to the VSIF reader object.
                _num_of_cov_rpts  => 0,                         # The number of requested coverage reports.
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



sub Set_Session_Reader {
   my ($this, $vsif_reader) = @_;
   if (ref($vsif_reader)) {
      $this->{_vsif_Reader } = $vsif_reader;
      $this->{_session_path} = $this->{_vsif_Reader}->get_session_path();
      # Reset all internal data structures
      return 1;
   }
   else {
      return 0;
   }
}


sub Set_vPlan_Reader {
   my ($this, $vplan_reader) = @_;
   if (ref($vplan_reader)) {
      $this->{_vPlan_Reader } = $vplan_reader;
      # Reset all internal data structures
      return 1;
   }
   else {
      return 0;
   }
}


sub Set_CDV_Dispatcher {
   my ($this, $CDV_Dispatcher) = @_;
   if (ref(CDV_Dispatcher)) {
      $this->{_CDV_Dispatcher } = $CDV_Dispatcher;
      # Reset all internal data structures
      return 1;
   }
   else {
      return 0;
   }
}


#------------------------------------------------------------------------------------
# Instance names in any of the ICCR commands must be hierarchical paths that begin
# with the module name of the design top rather than the module name of the testbench
#------------------------------------------------------------------------------------

sub Report_Coverage {
   my ($this, %args) = @_;
   my $num = ++$this->{_num_of_cov_rpts};
   my $merged_test_name  = "all_$num";
   my $iccr_comfile_path = $this->{_session_path} . "/iccr_com_$num.ccf";
   my $tests_path        = $this->{_session_path} . '/tests.txt';
   #---------------------------------------------------------------------------------
   # Write the tests file containing a list of all UCD databases
   #---------------------------------------------------------------------------------
   $this->Write_Tests_File();
   #---------------------------------------------------------------------------------
   # Write ICCR command File
   #---------------------------------------------------------------------------------
   open(my $tests_fh, '<', $tests_path) or die "Cannot read $tests_path:\n$!\n";
   my $primary_test_path = chomp <$tests_fh>;
   close $tests_fh;
   if ($primary_test_path =~ m{(.+/cov_work/\w+)/\w+}) {
      my $merged_test_path = qq{$1/$merged_test_name};
   }
   else {
      die "The primary test path $primary_test_path doesn't end in /cov_work/design.";
   }
   open(my $iccr_comfile_fh, '>', $iccr_comfile_path) or die "Cannot create $iccr_comfile_path:\n$!\n";
   #---------------------------------------------------------------------------------
   # Merge coverage data for the given modules/instances
   #---------------------------------------------------------------------------------
   print $iccr_comfile_fh "set_dut_modules *\n";
   print $iccr_comfile_fh "set_merge -union\n";
   print $iccr_comfile_fh "merge $coverages -testfile $tests_path -output $merged_test_name\n";
   #---------------------------------------------------------------------------------
   # Load merged coverage tests
   #---------------------------------------------------------------------------------
   print $iccr_comfile_fh "load_test $merged_test_path\n";
   #---------------------------------------------------------------------------------
   # Generate Summary Report
   #---------------------------------------------------------------------------------
   if ($args{modules}) {
      print $iccr_comfile_fh "report_summary -module -betsafd $args{modules}\n";
   }
   else ($args{instances}) {
      print $iccr_comfile_fh "report_summary -instance -betsafd $args{instances}\n";
   }
   close $iccr_comfile_fh;
   #---------------------------------------------------------------------------------
   # Dispatch the reporting job
   #---------------------------------------------------------------------------------
   $this->{_CDV_Dispatcher}->Dispatch_CovReport_Job($iccr_comfile_path, $num);
   #---------------------------------------------------------------------------------
   # Read iccr.log and see if an error occurred to determine the return value.
   #----------------------------- Self Coverage -------------------------------------
   #-------------------- Block Coverage
   # B    = Block
   # BR   = Branch
   # STMT = Statement
   #-------------------- Expression Coverage
   # E    = Expression
   #-------------------- Toggle Coverage
   # TF   = Toggle Full Transition
   # T^   = Toggle rise transition
   # Tv   = Toggle fall transition
   #-------------------- FSM Coverage
   # S    = FSM State
   # TR   = FSM Transition
   #-------------------- Functional Coverage
   # F    = Control oriented
   # D    = Data oriented
   #-------------------------- Cumulative Coverage ----------------------------------
   # If "C" is added to the end of any of the above coverage types (e.g. BC, SC, ..),
   # this indicates cumulative coverage for that coverage type including subhierarchy.
   #---------------------------------------------------------------------------------
   my $iccr_log_path = $this->{_session_path} . "/iccr_$num.log";
   open(my $iccr_log_fh, '<', $iccr_log_path) or die "Cannot read $iccr_log_path:\n$!\n";
   my $summary_report_scope = 0;
   while (<$iccr_log_fh>) {
      if (m/Coverage Summary Report/i) {
         $summary_report_scope = 1;
         next;
      }
      if ( m/\s+BC\s*:\s*(\d+)%/i ) {
      }
      
   }
   close $iccr_log_fh;
   return;
}


#-----------------------------------------------------------------------------------
# The tests in <filename> should be listed one per line. You can include comments in
# <filename> using #.
#-----------------------------------------------------------------------------------
sub Write_Tests_File {
   my ($this) = @_;
   my $jobs_path = $this->{_session_path} . '/jobs';
   if ((not -d $jobs_path) or (not -e $jobs_path)) {
      die "The passed job path $jobs_path either doesn't refer to a directory or doesn't exist\n";
   }
   my $tests_path = $this->{_session_path} . '/tests.txt';
   open(my $tests_fh, '>', $tests_path) or
        die "Cannot create $this->{_session_path}\/$tests_path:\n$!\n";
   opendir(my $jobs_dh, $jobs_path ) or die "Failed to open  $jobs_path:\n$!\n";
   foreach my $current_dir ( readdir($jobs_dh) ) {
      if ((not -d $current_dir) || ($current_dir !~ m/^(run_\d+)$/)) { # Skip files and any non-run directory.
         next;
      }
      else {
         print $tests_fh qq{$jobs_path/$1/cov_work/design/test\n};
      };
   }
   close    $tests_fh;
   closedir $jobs_dh;
   return 1;
}





1;


__END__



