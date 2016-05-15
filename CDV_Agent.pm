package CDV_Agent;

use base qw(Exporter);
use strict;
use warnings;
use Params::Validate qw(validate :types); # Argument Type Checking
use NEXT;
use Getopt::Long;


our @EXPORT = qw(
         Start_Session
            Read_VSIF
            Elaborate_VSIF
            Run_PreSession_Script
               Dump_Coverage_Model
            Start_Runs
               Run_PreRun_Script
               Run_Script
               Run_PostSimulation_Script
               Run_Scan_Script
               Run_PostRun_Script
            Run_PostSession_Script
         Track_Session
         Stop_Session
            Stop_Test
         Analyze_Session
            Load_Session
               Read_VSOF
               Load_Coverage_Model
               Load_Coverage_Data
               Merge_VScope_Covergae_Models
               Read_vPlan
               Bind_vPlan_to_Coverage_Model
                  Read_Coverage_Mapping_File
            Present_Coverage
               Export_vPlan_to_HTML
               Present_HDL_Coverage
               Present_e_Coverage
               Present_Coverage_Holes
               Chart_Coverage_vs_Time
               Correlate_Coverage # Construct Correlation Matrix
                  Rank_Tests
                  Rank_Runs
            Analyze_Failures
               Analyze_Session_Failures
               Analyze_Run_Failures
         Rerun_Session
            Rerun_Failures
         );


our @EXPORT_OK = qw();
our $VERSION   = 1.00;

# Class Variables
my $CDV_Agents_created = 0;
my $vsif_reader        = VSIF_Reader->new();


# Constructor
sub new {
   my ($caller, %args) = @_;
   my $class = ref($caller) || $caller;
   my $this = {
                _vsif_reader     => {}, # A reference to an empty hash representing a VSIF_Reader object
                _session_tracker => {}, # A reference to an empty hash representing a Session_Tracker object
   };
   $this = bless $this, $class;
   $this->EVERY::LAST::_init(%args); # Initialize the whole inheritance hierarchy (parents first)
   $CDV_Agents_created++; # This is a "Class Variables". Don't use $caller-> to set its value.
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
sub get_CDV_Agents_created {
   # This is a "Class Variables". Don't use $this-> to get its value.
#  my ($this) = @_;
   return $CDV_Agents_created;
}


my $current_dir = File::Spec->curdir();
use threads;

sub Start_Session {
   my ($this, $session_vsof_path) = @_;
#  my $thr = threads->create("$this->{_session_tracker}->track_session", $session_vsof_path);
   my $thr = threads->create(\&$this->{_session_tracker}->track_session, $session_vsof_path)
#  $thr->join(); ###### Don't join the tracker thread. We should continue execution
   
   # write the ALL_RUNS_COMPLETED sentinel for the session tracker to 
}



sub run_thread {
   my ($this, $session_vsof_path) = @_;
   system('');
   return;
}



1;






__END__



