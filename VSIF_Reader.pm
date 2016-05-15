package VSIF_Reader;

use base qw(Exporter);
use strict;
use warnings;
use Params::Validate qw(validate :types); # Argument Type Checking
use Storable qw(dclone);
use File::Copy;
use File::Spec;
use NEXT;
###################################################################
# A test is represented by a hash (a set of attribute-value pairs).
# A test group is represented by an array of references to hashes,
# each of which represents a test.
# The first hash being referenced is the group-level attributes.
# or, more succinctly, the default test.
# All subsequent references refer to test hashes.
###################################################################
# Class Variables
my $VSIF_Readers_created = 0;


our @EXPORT = qw(
                  Read_VSIF
                  Elaborate_VSIF
                  get_VSIF_Readers_created
                  get_session_name
                  get_session_top_dir
                );

our @EXPORT_OK = qw();
our $VERSION   = 1.00;


# Constructor
sub new {
   my ($caller, %args) = @_;
   my $class = ref($caller) || $caller;
   my $this = {
                _session_dir_path => '',    # An empty path
                _session_section  => {},    # A reference to an empty hash
                _test_groups      => [],    # A reference to an empty array
                _tests            => [],    # A reference to an empty array
                _tests_cloned     => [],    # A reference to an empty array
                _vPlan_Reader     => $args{vPlan_Reader}, # A reference to a vPlan Reader Object
   };
   $this = bless $this, $class;
   $this->EVERY::LAST::_init(%args); # Initialize the whole inheritance hierarchy (parents first)
   $VSIF_Readers_created++; # This is a "Class Variable". Don't use $caller-> to set its value.
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
   $this->EVERY::_destroy; # the child classes destructors are called prior to their parents.
   return;
}


sub _destroy {
   my ($this) = @_;
   # All the real clean-up occurs here.
   return;
}

# Get Accessors
sub get_VSIF_Readers_created {
   # This is a "Class Variables". Don't use $this-> to get its value.
#  my ($this) = @_;
   return $VSIF_Readers_created;
}

sub get_session_name {
   my ($this) = @_;
   return ${ $this->{_session_section} }{name};
}

sub get_session_top_dir {
   my ($this) = @_;
   return ${ $this->{_session_section} }{top_dir};
}

sub get_next_test_continue {
   my ($this) = @_;
   my $remaining_tests = @{ $this->{_tests_cloned} }; # Size of the _tests_cloned array
   if ($remaining_tests == 0) {
      $this->{_tests_cloned} = dclone $this->{_tests};
   }
   return shift @{ $this->{_tests_cloned} };
}


sub get_next_test {
   my ($this) = @_;
   my $remaining_tests = @{ $this->{_tests_cloned} }; # Size of the _tests_cloned array
   if ($remaining_tests == 0) {
      return undef;
   }
   else {
      return shift @{ $this->{_tests_cloned} };
   }
}


sub reset_test_iterator {
   my ($this) = @_;
   $this->{_tests_cloned} = dclone $this->{_tests};
   return;
}



sub Read_VSIF {
   my ($this, $vsif_name, $ignore_session_section) = @_;
   @{ $this->{_test_groups}} = (); # Empty the array referred to by _test_groups
   @{ $this->{_tests      }} = (); # Empty the array referred to by _tests
   my $line_number = 0;
   my $lex_scope   = 'START';
   my $prev_scope  = 'START';
   my @current_test_group;
   my %current_test;
   copy($vsif_name, "${vsif_name}_backup") or die "Failed to backup $vsif_name:\n$!\n";
   if ( -e $vsif_name && -r $vsif_name) {
      open(my $fh, '<', $vsif_name) or die "Cannot open $vsif_name:\n$!\n";
   }
   else {
      die "The VSIF file doesn't exist or is not readable:\n$!\n";
   }
   ######################################################################################
   # Any lexical element is replaced by a tab character in order not join two separate
   # lexical elements together.
   # Because they don't affect parsing state, remove the following:
   # - Block (multi-line) comments started and ended on the same line,.
   #   Use non-greedy matching to disallow nested multi-block comments
   # - Single-line comments wherever they occur.
   # In a line, there can be at most one single-line comment
   # There can be many such comments on a line
   # Regardless of the current scope, once a multi-line comment starts (and ends on
   # another line), we enter the "COMMENT_SCOPE".
   # There must one and only one "session" section before any "group" or "test" section
   # in the VSIF.
   # A verif_scope attribute is attached to every vPlan spec to refer to the coverage module
   # corresponding to it in the design.
   # A verif_perspective session attribute is added to restrict coverage collection to one or
   # more sub-hierarchies of the design. These perspectives are extracted from the vPlan. If
   # this attribute is absent, the whole design represents the current verif_perspective.
   # A feature not present in Enterprise Manager is allowing for hierarchical VSIF files.
   # That's, a VSIF file can refer to (i.e. include) another VSIF file.
   # The top-level VSIF file can be considered the chip-level VSIF created by the chip or
   # verification lead, and the included VSIF files are those created by block designers or
   # verification engineers.
   # Only the session section of the top-level VSIF is read, overriding those of the 
   # included VSIF files.
   # More than one session section may exist, but the last one in the top file takes
   # precedence.
   ######################################################################################
   while <$fh> {
      $line_number = $line_number + 1;
            (s/\s*\/\/.*\n/\t/xm);          # Single-line comments
      while (s/\s*\/\*.*?\*\/\s*/\t/xm) {}; # Multi-line comments
      while ($_ ne q{}) {
         if (s/^\s*\/\*.*\n/\t/xm) {
            $prev_scope = $lex_scope;
            $lex_scope  = 'COMMENT_SCOPE';
            last; # Break out of the loop to get a new line
         }
         #-------------------------------------------------------------------------------------
         #--------------------------------------- START ---------------------------------------
         #-------------------------------------------------------------------------------------
         elsif ($lex_scope eq 'START') {
            if (s/^\s*session\s*\{/\t/xm) {
               $lex_scope = 'SESSION_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            elsif (s/^\s*include\s*(\w+)\s*\;\s*/\t/xm) {
               # Recursively read all included VSIF files and ignore their session sections
               $this->Read_VSIF($1, 1); # Ignore the session section of the passed VSIF
               $lex_scope = 'GLOBAL_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            else {
               die "Unrecognized or non-session construct at line: $line_number of file $vsif_name\n";
            }
         }
         #-------------------------------------------------------------------------------------
         #------------------------------------ GLOBAL_SCOPE -----------------------------------
         #-------------------------------------------------------------------------------------
         elsif ($lex_scope eq 'GLOBAL_SCOPE') {
            if (s/^\s*session\s*\{/\t/xm) {
               $lex_scope = 'SESSION_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            elsif (s/^\s*include\s*(\w+)\s*\;\s*/\t/xm) {
               # Recursively read all included VSIF files and ignore their session sections
               $this->Read_VSIF($1, 1); # Ignore the session section of the passed VSIF
               $lex_scope = 'GLOBAL_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            elsif (s/^\s*group\s*\{/\t/xm) {
               @current_test_group = (); # Empty @current_test_group
               $lex_scope          = 'GROUP_SCOPE';
            }
            elsif (s/^\s*test\s*\{/\t/xm) {
               %current_test = (); # Empty %current_test
               $lex_scope    = 'TEST_SCOPE';
            }
            else {
               die "Unrecognized (or unexpected) construct at line: $line_number of file $vsif_name\n";
            }
         }
         #-------------------------------------------------------------------------------------
         #------------------------------------ COMMENT_SCOPE ----------------------------------
         #-------------------------------------------------------------------------------------
         elsif ($lex_scope eq 'COMMENT_SCOPE') {
            if (s/^.*?\*\//\t/xm) { # The end of the current comment scope
               $lex_scope = $prev_scope; # Restore the scope before entering the comment scope
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            else {
               last; # Break out of the loop to get a new line
            }
         }
         #-------------------------------------------------------------------------------------
         #------------------------------------ SESSION_SCOPE ----------------------------------
         #-------------------------------------------------------------------------------------
         elsif ($lex_scope eq 'SESSION_SCOPE') {
            if (s/^\s*name\s*\:\s*(\w+)\s*\;\s*/\t/xm) { # Capture the session name
               if (not $ignore_session_section) { ${ $this->{_session_section} }{name} = $1; }
            }
            elsif (s/^\s*top_dir\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the session top_dir
               if (not $ignore_session_section) { ${ $this->{_session_section} }{top_dir} = $1; }
            }
            elsif (s/^\s*max_par_runs\s*\:\s*(\d+)\s*\;\s*/\t/xm) { # Capture the session max_par_runs
               if (not $ignore_session_section) { ${ $this->{_session_section} }{max_par_runs} = $1; }
            }
            elsif (s/^\s*pre_session_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the session pre_session_script
               if (not $ignore_session_section) { ${ $this->{_session_section} }{pre_session_script} = $1; }
            }
            elsif (s/^\s*post_session_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the session post_session_script
               if (not $ignore_session_section) { ${ $this->{_session_section} }{post_session_script} = $1; }
            }
            elsif (s/^\s*hostname\s*\:\s*(.+)\s*\;\s*/\t/xm) { # Capture the session hostname
               if (not $ignore_session_section) { ${ $this->{_session_section} }{hostname} = $1; }
            }
            elsif (s/^\s*verif_perspective\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the session verif_perspective
               if (not $ignore_session_section) { ${ $this->{_session_section} }{verif_perspective} = $1; }
            }
            elsif (s/^\s*\}\s*\;\s*/\t/xm) { # Session section is closed
               $lex_scope = 'GLOBAL_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            else {
               die "Unrecognized session attribute at line: $line_number of file $vsif_name\n";
            }
         }
         #-------------------------------------------------------------------------------------
         #------------------------------------ GROUP_SCOPE ------------------------------------
         #-------------------------------------------------------------------------------------
         elsif ($lex_scope eq 'GROUP_SCOPE') {
            if (s/^\s*pre_run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the group pre_run script
               $current_test_group[0]->{pre_run_script} = $1;
            }
            elsif (s/^\s*run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the group run script
               $current_test_group[0]->{run_script} = $1;
            }
            elsif (s/^\s*run_script_options\s*\:\s*([\w\/\.$-]+)\s*\;\s*/\t/xm) { # Capture the group run script options
               $current_test_group[0]->{run_script_options} = $1;
            }
            elsif (s/^\s*post_sim_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the group post_simulate script
               $current_test_group[0]->{post_sim_script} = $1;
            }
            elsif (s/^\s*scan_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the group scan script
               $current_test_group[0]->{scan_script} = $1;
            }
            elsif (s/^\s*post_run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the group post_run script
               $current_test_group[0]->{post_run_script} = $1;
            }
            elsif (s/^\s*auto_rerun_covscope\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm)     { # Capture the group auto-rerun coverage scope
               if ($current_test_group[0]->{count}) {
                  die "A test group cannot contain both auto-rerun coverage scope and count attributes at line: $line_number of file $vsif_name\n";
               }
               else
               {
                  $current_test_group[0]->{auto_rerun_covscope} = $1;
               }
            }
            elsif (s/^\s*count\s*\:\s*(\d+)\s*\;\s*/\t/xm) { # Capture the group count
               if ($current_test_group[0]->{auto_rerun_covscope}) {
                  die "A test group cannot contain both auto-rerun coverage scope and count attributes at line: $line_number of file $vsif_name\n";
               }
               else
               {
                  $current_test_group[0]->{count} = $1;
               }
            }
            elsif (s/^\s*timeout\s*\:\s*(\d+)\s*\;\s*/\t/xm)     { # Capture the group timeout (in minutes)
               $current_test_group[0]->{timeout} = $1;
            }
            elsif (s/^\s*pre_commands\s*\:\s*(.*)\s*\;\s*/\t/xm) { # Capture the group pre-commands
               $current_test_group[0]->{pre_commands} = $1;
            }
            elsif (s/^\s*test_command\s*\:\s*(.*)\s*\;\s*/\t/xm) { # Capture the group test command
               $current_test_group[0]->{test_command} = $1;
            }
            elsif (s/^\s*hostname\s*\:\s*(.+)\s*\;\s*/\t/xm) { # Capture the group hostname
               $current_test_group[0]->{hostname} = $1;
            }
            elsif (s/^\s*test\s*\{\s*/\t/xm) {
               %current_test = (); # Empty %current_test
               $lex_scope    = 'NESTED_TEST_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            elsif (s/^\s*\}\s*\;\s*/\t/xm) { # The closing parenthesis-semicolon pair of the test group
               # Push a reference to the current test group onto the list of test groups
######         push @{ $this->{_test_groups}}, \copy_test_group(@current_test_group);
               push @{ $this->{_test_groups}}, dclone \@current_test_group;
               # Flatten the current test group and push it on the @tests array.
               my %current_default_test = %{ shift @current_test_group }; # Remove the first (group-level) hash
               foreach my $test (@current_test_group) {
                  my %total_test = (%current_default_test, %{ $test }); # Merge the test with the defaults
                  if ($test->{count}) {
                     # If the %current_default_test contains a "count" attribute, it should have been overridden by the above merge.
                     # Therefore, it's enough to only check for the auto_rerun_covscope attribute.
                     delete $total_test{auto_rerun_covscope}; # If it exists, this must have come from %current_default_test
                  }
                  elsif ($test->{auto_rerun_covscope})
                  {
                     # If the %current_default_test contains a "auto_rerun_covscope" attribute, it should have been overridden by the above merge.
                     # Therefore, it's enough to only check for the count attribute.
                     delete $total_test{count}; # If it exists, this must have come from %current_default_test
                  }
                  push @{ $this->{_tests}}, dclone \%total_test;
               }
               $lex_scope = 'GLOBAL_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            elsif (m/^\s*$/xm) { # If all remaining characters (if any) are white-space characters
               last; # Break out of the loop to get a new line
            }
            else {
               die "Unrecognized group attribute or non-test member at line: $line_number of file $vsif_name\n";
            }
         }
         #-------------------------------------------------------------------------------------
         #--------------------------------- NESTED_TEST_SCOPE ---------------------------------
         #-------------------------------------------------------------------------------------
         elsif ($lex_scope eq 'NESTED_TEST_SCOPE') {
            if (s/^\s*testsuite\s*\:\s*([\w]+)\s*\;\s*/\t/xm) { # Capture the test suite
               $current_test{testsuite} = $1;
            }
            elsif (s/^\s*testcase\s*\:\s*([\w]+)\s*\;\s*/\t/xm) { # Capture the testcase
               $current_test{testcase} = $1;
            }
            elsif (s/^\s*pre_run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test pre_run script
               $current_test{pre_run_script} = $1;
            }
            elsif (s/^\s*run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test run script
               $current_test{run_script} = $1;
            }
            elsif (s/^\s*run_script_options\s*\:\s*([\w\/\.-]+)\s*\;\s*/\t/xm) { # Capture the test run script options
               $current_test{run_script_options} = $1;
            }
            elsif (s/^\s*post_sim_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test post_simulate script
               $current_test{post_sim_script} = $1;
            }
            elsif (s/^\s*scan_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test scan script
               $current_test{scan_script} = $1;
            }
            elsif (s/^\s*post_run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test post_run script
               $current_test{post_run_script} = $1;
            }
            elsif (s/^\s*auto_rerun_covscope\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test auto-rerun coverage scope
               if ($current_test{count}) {
                  die "A test cannot contain both auto-rerun coverage scope and count attributes at line: $line_number of file $vsif_name\n";
               }
               else
               {
                  $current_test{auto_rerun_covscope} = $1;
               }
            }
            elsif (s/^\s*timeout\s*\:\s*(\d+)\s*\;\s*/\t/xm)     { # Capture the test timeout (in minutes)
               $current_test{timeout} = $1;
            }
            elsif (s/^\s*pre_commands\s*\:\s*(.*)\s*\;\s*/\t/xm) { # Capture the test pre-commands
               $current_test{pre_commands} = $1;
            }
            elsif (s/^\s*test_command\s*\:\s*(.*)\s*\;\s*/\t/xm) { # Capture the test's test command
               $current_test{test_command} = $1;
            }
            elsif (s/^\s*run_mode\s*\:\s*(batch_debug|batch)\s*\;\s*/\t/xm) { # Capture the test run_mode
               $current_test{run_mode} = $1;
            }
            elsif (s/^\s*sv_seed\s*\:\s*(\d+)\s*\;\s*/\t/xm) { # Capture the test sv_seed
               $current_test{sv_seed} = $1;
            }
            elsif (s/^\s*count\s*\:\s*(\d+)\s*\;\s*/\t/xm) { # Capture the test count
               if ($current_test{auto_rerun_covscope}) {
                  die "A test cannot contain both auto-rerun coverage scope and count attributes at line: $line_number of file $vsif_name\n";
               }
               else
               {
                  $current_test{count} = $1;
               }
            }
            elsif (s/^\s*hostname\s*\:\s*(.+)\s*\;\s*/\t/xm) { # Capture the test hostname
               $current_test{hostname} = $1;
            }
            elsif (s/^\s*\}\s*\;\s*/\t/xm) { # The closing parenthesis-semicolon pair of the test
               # Push a reference to the current test onto the list of test in the current test group
######         push @current_test_group, \copy_test(%current_test);
               push @current_test_group, dclone \%current_test;
               $lex_scope = 'GROUP_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            elsif (m/^\s*$/xm) { # If all remaining characters (if any) are white-space characters
               last; # Break out of the loop to get a new line
            }
            else {
               die "Unrecognized group attribute or non-test member at line: $line_number of file $vsif_name\n";
            }
         }
         #-------------------------------------------------------------------------------------
         #------------------------------------ TEST_SCOPE -------------------------------------
         #-------------------------------------------------------------------------------------
         elsif ($lex_scope eq 'TEST_SCOPE') {
            if (s/^\s*testsuite\s*\:\s*([\w]+)\s*\;\s*/\t/xm) { # Capture the test suite
               $current_test{testsuite} = $1;
            }
            elsif (s/^\s*testcase\s*\:\s*([\w]+)\s*\;\s*/\t/xm) { # Capture the testcase
               $current_test{testcase} = $1;
            }
            elsif (s/^\s*pre_run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test pre_run script
               $current_test{pre_run_script} = $1;
            }
            elsif (s/^\s*run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test run script
               $current_test{run_script} = $1;
            }
            elsif (s/^\s*run_script_options\s*\:\s*([\w\/\.-]+)\s*\;\s*/\t/xm) { # Capture the test run script options
               $current_test{run_script_options} = $1;
            }
            elsif (s/^\s*post_sim_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test post_simulate script
               $current_test{post_sim_script} = $1;
            }
            elsif (s/^\s*scan_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test scan script
               $current_test{scan_script} = $1;
            }
            elsif (s/^\s*post_run_script\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test post_run script
               $current_test{post_run_script} = $1;
            }
            elsif (s/^\s*auto_rerun_covscope\s*\:\s*([\w\/\.]+)\s*\;\s*/\t/xm) { # Capture the test auto-rerun coverage scope
               if ($current_test{count}) {
                  die "A test cannot contain both auto-rerun coverage scope and count attributes at line: $line_number of file $vsif_name\n";
               }
               else
               {
                  $current_test{auto_rerun_covscope} = $1;
               }
            }
            elsif (s/^\s*timeout\s*\:\s*(\d+)\s*\;\s*/\t/xm)     { # Capture the test timeout (in minutes)
               $current_test{timeout} = $1;
            }
            elsif (s/^\s*pre_commands\s*\:\s*(.*)\s*\;\s*/\t/xm) { # Capture the test pre-commands
               $current_test{pre_commands} = $1;
            }
            elsif (s/^\s*test_command\s*\:\s*(.*)\s*\;\s*/\t/xm) { # Capture the test's test command
               $current_test{test_command} = $1;
            }
            elsif (s/^\s*run_mode\s*\:\s*(batch_debug|batch)\s*\;\s*/\t/xm) { # Capture the test run_mode
               $current_test{run_mode} = $1;
            }
            elsif (s/^\s*sv_seed\s*\:\s*(\d+)\s*\;\s*/\t/xm) { # Capture the test sv_seed
               $current_test{sv_seed} = $1;
            }
            elsif (s/^\s*count\s*\:\s*(\d+)\s*\;\s*/\t/xm) { # Capture the test count
               if ($current_test{auto_rerun_covscope}) {
                  die "A test cannot contain both auto-rerun coverage scope and count attributes at line: $line_number of file $vsif_name\n";
               }
               else
               {
                  $current_test{count} = $1;
               }
            }
            elsif (s/^\s*hostname\s*\:\s*(.+)\s*\;\s*/\t/xm) { # Capture the test hostname
               $current_test{hostname} = $1;
            }
            elsif (s/^\s*\}\s*\;\s*/\t/xm) { # The closing parenthesis-semicolon pair of the test
               # Push a reference to the current test onto the list of test in the current test group
#####          push @{ $this->{_tests}}, \copy_test(%current_test);
               push @{ $this->{_tests}}, dclone \%current_test;
               $lex_scope = 'GLOBAL_SCOPE';
               # Don't break out of the loop to get a new line.
               # The current line may still have more lexicons.
            }
            elsif (m/^\s*$/xm) { # If all remaining characters (if any) are white-space characters
               last; # Break out of the loop to get a new line
            }
            else {
               die "Unrecognized group attribute or non-test member at line: $line_number of file $vsif_name\n";
            }
         }
         #-------------------------------------------------------------------------------------
      };
      if (not (m/^\s*$/xm)) { # If all remaining characters (if any) are NOT white-space characters
         die "Unrecognized keywords  $_ at line: $line_number of file $vsif_name\n";
      }
   };
   close $fh or die "Cannot close VSIF file\n";
   #-------------------------------------------------------------------------------------------
   if ($line_number == 0) {
      die "File is empty.\n"
   }
   else {
      print "Number of lines of file $vsif_name: $line_number\n"
   }
   return;
}



#------------------------------------------------------------------------------
# A verif_perspective session attribute is added to restrict coverage collection
# to one or more sub-hierarchies of the design. These scopes are extracted from
# the vPlan. If this attribute is absent, the whole design represents the
# current verif_perspective.
#------------------------------------------------------------------------------
sub Elaborate_VSIF {
   my ($this) = @_;
   umask 0022; # All created files will have permission 0755 (i.e. rwxr-xr-x)
   #---------------------------------------------------------------------------
   #------------- Create the top directory, if it doesn't exist ---------------
   #---------------------------------------------------------------------------
   my $top_directory = "$ENV{WORK_DIR}/regressions".'/'."$this->get_session_top_dir()";
   # The top directory may exist due to previous sessions run inside of it.
   # Create the top directory if this is the first session to name it.
   if (not -d $top_directory) {
      die "The passed top path $top_directory doesn't refer to a directory.\n";
   }
   elsif (not -e $top_directory) {
      mkdir  ( $top_directory ) or die "Failed to create $top_directory:\n$!\n";
   }
   opendir(my $top_dh, $top_directory ) or die "Failed to open  $top_directory:\n$!\n";
   chdir  (   $top_dh                 ) or die "Failed to enter $top_directory:\n$!\n";
   #---------------------------------------------------------------------------
   #-------- Create the session directory, or chain to an existing one --------
   #---------------------------------------------------------------------------
   my $session_directory = $this->get_session_name();
   if ($ENV{USER}) {
      $session_directory .= ".$ENV{USER}."
   }
   $session_directory .= time; # Append time stamp
   $this->{_session_dir_path} = $session_directory;
   mkdir(                  $session_directory ) or die "Failed to create $session_directory:\n$!\n";
   opendir(my $session_dh, $session_directory ) or die "Failed to open   $session_directory:\n$!\n";
   chdir(     $session_dh )                     or die "Failed to enter  $session_directory:\n$!\n";
   #---------------------------------------------------------------------------
   #----------------------- Write the session parameters ----------------------
   #---------------------------------------------------------------------------
   my $session_params_fname = 'session_params.txt';
   open(my $session_params_fh, '>', $session_params_fname) or
                 die "Cannot create $session_params_fname:\n$!\n";
   my @session_descriptor = %{ $this->{_session_section} }; # Convert to array
   my $session_descriptor_formatted = '';
   my $attr = 1;
   for (my $count = 1; $count <= @session_descriptor; $count++) {
      if ($attr == 1) {
         $session_descriptor_formatted .= $session_descriptor[$count] . ' : ';
         $attr = 0;
      }
      else {
         $session_descriptor_formatted .= $session_descriptor[$count] . ";\n";
         $attr = 1;
      }
   }
   print {$session_params_fh} $session_descriptor_formatted;
   close $session_params_fh;
   #---------------------------------------------------------------------------
   #----------------------- Write the session covfiles ------------------------
   #---------------------------------------------------------------------------
   $this->write_session_covfiles();
   #---------------------------------------------------------------------------
   #----------------------- Create the jobs directory -------------------------
   #---------------------------------------------------------------------------
   mkdir(               'jobs' ) or die "Failed to create the jobs directory:\n$!\n";
   opendir(my $jobs_dh, 'jobs' ) or die "Failed to open   the jobs directory:\n$!\n";
   #---------------------------------------------------------------------------
   #--- Iterate over all tests and elaborate each one as many times as "count".
   #---------------------------------------------------------------------------
   my $run_params_fname = 'run_params.txt';
   my $run_dirname;
   my $job_num  = 0;
   my $count    = 1;
                      $this->reset_test_iterator();
   my $current_test = $this->get_next_test();
   while (defined ($current_test)) {
      $count = $current_test->{count} || 1;
      for (my $n = 1; $n <= count; $n++) {
         $run_dirname = 'run_'.$job_num;
         mkdir(              $run_dirname ) or die "Failed to create $run_dirname:\n$!\n";
         opendir(my $run_dh, $run_dirname ) or die "Failed to open   $run_dirname:\n$!\n";
         chdir(     $run_dh )               or die "Failed to enter  $run_dirname:\n$!\n";
         $this->write_local_job_sh($job_num, $run_dh, $current_test);
         $this->write_job_completed_notifier($run_dh);
         #---------------------------------------------------------------------------
         #------------------------- Write the run parameters ------------------------
         #---------------------------------------------------------------------------
         open(my $run_params_fh, '>', $run_params_fname) or
                   die "Cannot create $run_params_fname:\n$!\n";
         my @run_descriptor = %{ $current_test }; # Convert to array
         my $run_descriptor_formatted = '';
         my $attr = 1;
         for (my $count = 1; $count <= @session_descriptor; $count++) {
            if ($run_descriptor[$count] != 'count') { # Skip the count attribute
               next;
            }
            elsif ($attr == 1) {
               $run_descriptor_formatted .= $run_descriptor[$count] . ' : ';
               $attr = 0;
            }
            else {
               $run_descriptor_formatted .= $run_descriptor[$count] . ";\n";
               $attr = 1;
            }
         }
         print {$run_params_fh} $run_descriptor_formatted;
         close $run_params_fh;
         closedir $run_dh;
         $job_num++;
      }
      $current_test = $this->get_next_test();
   }
   #---------------------------------------------------------------------------
   #------------ Create the coverage file to configure ncelab -----------------
   #---------------------------------------------------------------------------
   closedir($jobs_dh);
   closedir($session_dh);
   closedir($top_dh);
   return "$top_directory" . '/' . "$session_directory";
}


sub write_session_covfiles {
   my ($this) = @_;
   $this->write_block_covfile();
   $this->write_expr_covfile();
   $this->write_fsm_covfile();
   $this->write_toggle_covfile();
   $this->write_func_covfile();
}


sub write_block_covfile {
   my ($this) = @_;
   my $cov_file = '';
   my $verif_perspective = $this->{_session_section}->{verif_perspective};
   my $modules     = $this->{_vPlan_Reader}->Get_BlockCov_Modules  ($verif_perspective);
   my $instances   = $this->{_vPlan_Reader}->Get_BlockCov_Instances($verif_perspective);
   if ($modules or $instances) {
      $cov_file .= "select_coverage -block ";
      if ($modules) {
         $cov_file .= "-module $modules\n";
      }
      elsif ($instances) {
         $cov_file .= "-instance $instances\n";
      }
      # $cov_file .= "set_hit_count_limit 10\n";
      # $cov_file .= "set_glitch_strobe 3 ns\n"; # Filter signal glitches that can lead to artificially high coverage counts.
      # $cov_file .= "set_statement_scoring\n"
      # $cov_file .= "set_assign_scoring\n"
      # $cov_file .= "set_subprogram_scoring {-all | -used} *\n"
      my $block_cov_path = $this->{_session_dir_path} . '/block_cov.ccf';
      open(my $block_cov_fh,  '>',  $block_cov_path)
             or die "Cannot create the session block coverage configuration file:\n$!\n";
      print {$block_cov_fh} $cov_file;
      close $block_cov_fh;
   }
   return;
}


sub write_expr_covfile {
   my ($this) = @_;
   my $cov_file = '';
   my $verif_perspective = $this->{_session_section}->{verif_perspective};
   my $modules     = $this->{_vPlan_Reader}->Get_ExprCov_Modules  ($verif_perspective);
   my $instances   = $this->{_vPlan_Reader}->Get_ExprCov_Instances($verif_perspective);
   if ($modules or $instances) {
      $cov_file .= "select_coverage -expression ";
      if ($modules) {
         $cov_file .= "-module $modules\n";
      }
      elsif ($instances) {
         $cov_file .= "-instance $instances\n";
      }
      my $expr_cov_path = $this->{_session_dir_path} . '/expr_cov.ccf';
      open(my $expr_cov_fh,   '>', $expr_cov_path )
             or die "Cannot create the session expression coverage configuration file:\n$!\n";
      print {$expr_cov_fh} select_coverage [<coverages>] [[-module] <list> | -instance <list>]
      close $expr_cov_fh;
   }
   return;
}


sub write_fsm_covfile {
   my ($this) = @_;
   # set_fsm_attribute -tag <tag> -module <module> -statereg <state_reg>
   my $cov_file = '';
   my $verif_perspective = $this->{_session_section}->{verif_perspective};
   my $modules = $this->{_vPlan_Reader}->Get_FSMCov_Modules($verif_perspective);
   if ($modules) {
      # $cov_file .= "select_fsm [ -module <modules> | -tag <tags>]\n";
      # $cov_file .= "select_fsm [ -module <modules> | -tag <tags>]\n"
      # $cov_file .= "set_fsm_arc_scoring [-on | -off] [ -module <modules> | -tag <tags>]\n";
      $cov_file .= "set_fsm_reset_scoring\n"
      my $fsm_cov_path = $this->{_session_dir_path} . '/fsm_cov.ccf';
      open(my $fsm_cov_fh,    '>', $fsm_cov_path )
             or die "Cannot create the session FSM coverage configuration file:\n$!\n";
      print {$fsm_cov_fh} select_coverage [<coverages>] [[-module] <list> | -instance <list>]
      close $fsm_cov_fh;
   }
   return;
}


sub write_toggle_covfile {
   my ($this) = @_;
   my $cov_file = '';
   my $verif_perspective = $this->{_session_section}->{verif_perspective};
   my $modules     = $this->{_vPlan_Reader}->Get_ToggleCov_Modules  ($verif_perspective);
   my $instances   = $this->{_vPlan_Reader}->Get_ToggleCov_Instances($verif_perspective);
   if ($modules or $instances) {
      $cov_file .= "select_coverage -toggle ";
      if ($modules) {
         $cov_file .= "-module $modules\n";
      }
      elsif ($instances) {
         $cov_file .= "-instance $instances\n";
      }
      $cov_file .= "set_toggle_noports\n";
      $cov_file .= "set_toggle_strobe 5 ns\n";
      $cov_file .= "set_toggle_limit 5\n";
      $cov_file .= "set_toggle_includez\n";
      $cov_file .= "set_toggle_includex\n";
      my $toggle_cov_path = $this->{_session_dir_path} . '/toggle_cov.ccf';
      open(my $toggle_cov_fh, '>', $toggle_cov_path )
             or die "Cannot create the session Toggle coverage configuration file:\n$!\n";
      print {$toggle_cov_fh} select_coverage [<coverages>] [[-module] <list> | -instance <list>]
      close $toggle_cov_fh;
   }
   return;
}


sub write_func_covfile {
   my ($this) = @_;
   my $cov_file = '';
   my $verif_perspective = $this->{_session_section}->{verif_perspective};
   my $modules     = $this->{_vPlan_Reader}->Get_FuncCov_Modules  ($verif_perspective);
   my $instances   = $this->{_vPlan_Reader}->Get_FuncCov_Instances($verif_perspective);
   $cov_file .= "select_functional\n";
#  $cov_file .= "set_ignore_library_name\n";
   my $func_cov_path = $this->{_session_dir_path} . '/func_cov.ccf';
   open(my $func_cov_fh,   '>', $func_cov_path )
          or die "Cannot create the session Functional coverage configuration file:\n$!\n";
   print {$func_cov_fh} select_coverage [<coverages>] [[-module] <list> | -instance <list>]
   close $func_cov_fh;
   return;
}


sub write_local_job_sh {
   my ($this, $job_num, $run_dh, $current_test) = @_;
   my $job_fname = 'local_job_'.$job_num.'.sh';
   my $sim_args = '';
   chdir( $run_dh ) or die "Failed to change to the job directory:\n$!\n";
   open(my $fh, '>', $job_fname) or die "Cannot create $job_fname:\n$!\n";
   #-----------------------------------------------------------
   #------------ Write to the job_id file ---------------------
   #-----------------------------------------------------------
   #------------ Run Environment Variables --------------------
   print $fh "source $ENV{WORK_DIR}/bin/proj.env";
   #----------------- Pre-Run Script --------------------------
   if ($current_test->{pre_run_script}) {
      my $pre_run_cmd = "$current_test->{pre_run_script}\n";
      print $fh "$pre_run_cmd\n";
   }
   #------------------- Run Script ----------------------------
   my $run_cmd = $current_test->{run_script} || dosim.pl;
   $run_cmd   .= " $current_test->{run_script_options}";
   my $cov_files = '';
   my $block_cov_path  = $this->{_session_dir_path} . '/block_cov.ccf';
   my $expr_cov_path   = $this->{_session_dir_path} . '/expr_cov.ccf';
   my $fsm_cov_path    = $this->{_session_dir_path} . '/fsm_cov.ccf';
   my $toggle_cov_path = $this->{_session_dir_path} . '/toggle_cov.ccf';
   my $func_cov_path   = $this->{_session_dir_path} . '/func_cov.ccf';
   if (-e $block_cov_path) {
      $cov_files .= " -covfile $block_cov_path ";
   }
   if (-e $expr_cov_path) {
      $cov_files .= " -covfile $expr_cov_path ";
   }
   if (-e $fsm_cov_path) {
      $cov_files .= " -covfile $fsm_cov_path ";
   }
   if (-e $toggle_cov_path) {
      $cov_files .= " -covfile $toggle_cov_path ";
   }
   if (-e $func_cov_path) {
      $cov_files .= " -covfile $func_cov_path ";
   }
   # The -covdut is not necessary
   $run_cmd   .= qq{ -ncelab "$cov_files" };
   $run_cmd   .= qq{ -ncsim "-covoverwrite -covnomodeldump" };
   $run_cmd   .= " -s $current_test->{testsuite} -t $current_test->{testcase} ";
   print $fh "$run_cmd\n";
   #-------------- Post_Simulation Script ---------------------
   if ($current_test->{post_sim_script}) {
      my $post_sim_cmd = '';
      print $fh "$post_sim_cmd\n";
   }
   #------------------- Scan Script ---------------------------
   if ($current_test->{scan_script}) {
      my $scan_cmd = '';
      print $fh "$scan_cmd\n";
   }
   #----------------- Post-Run Script -------------------------
   if ($current_test->{post_run_script}) {
      my $post_run_cmd = '';
      print $fh "$post_run_cmd\n";
   }
   close $fh;
   $mode = 0755; chmod $mode, $job_fname;
   return;
}



sub write_job_completed_notifier {
   my ($this, $run_dh) = @_;
   my $complete_fname = 'job_completed.pl';
   chdir( $run_dh ) or die "Failed to change to the job directory:\n$!\n";
   open(my $fh, '>', $complete_fname) or die "Cannot create $complete_fname:\n$!\n";
   #-----------------------------------------------------------
   #------------ Write to the job_completed file --------------
   #-----------------------------------------------------------
   print $fh '#!/usr/bin/perl' . "\n";
   print $fh 'my $complete_fname = ''job_completed.txt;''' . "\n";
   print $fh 'open(my $fh, ">", $complete_fname) or die "Cannot create $complete_fname:\n$!\n";' . "\n";
   print $fh 'print $fh ' . $ENV{COMPLETE_MESSAGE} . "\n";
   close $fh;
   $mode = 0755; chmod $mode, $complete_fname;
   return;
}



sub copy_test_group {
   my @test_group = @_;
   my @test_group_cp;
   foreach my $test (@test_group) {
      push @test_group_cp, {}; # Push a reference to an anonymous empty hash.
      %{ $test_group_cp[-1] } = %{ $test }; # Copy the current test hash into the location just pushed
   }
   return @test_group_cp;
}


sub copy_test {
   my %current_test = @_;
   return %current_test;
}





1;




__END__


 
