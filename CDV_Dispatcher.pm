package CDV_Dispatcher;

use base qw(Exporter);
use strict;
use warnings;
use Storable qw(dclone);
use File::Copy;
use File::Spec;
use NEXT;
use threads;
use Thread::Semaphore;

our @EXPORT    = qw( Set_Session_Path
                     Read_Jobs
                     Dispatch_Jobs_Thread
                     Rerun_Jobs_Thread
                     Suspend_Jobs
                     Resume_Jobs
                     Kill_Jobs
                     Query_Job_Status
                     Get_CDV_Dispatchers_created
                    );
our @EXPORT_OK = qw( );
our $VERSION   = 1.00;

# Class Variables
my $CDV_Dispatchers_created = 0;

# Constants
# Job status is updated every two minutes (because this is a time-consuming operation)
use constant JOB_STATUS_UPDATE_PERIOD => "120"; # In seconds

# Constructor
sub new {
   my ($caller, %args) = @_;
   my $class = ref($caller) || $caller;
   my $this = {
                _session_path    => $args{session_path} || '', # The path to the session directory containing information about runs to be dispatched
                _idle            => 1,                         # Whether or not there are jobs running or pending.
                _jobs            => [],                        # A reference to an empty array of job hashes.
                _cov_agent       => $args{cov_agent},          # A reference to a coverage agent.
                _dispatcher_tobj => undef,                     # A reference to the dispatcher thread object.
                _jobs_semaphore  => Thread::Semaphore->new(),  # A reference to a thread-safe semaphore object to regulate access to $this->{_jobs}.
                _susp_semaphore  => Thread::Semaphore->new(),  # A reference to a thread-safe semaphore object to suspend/resume the dispatcher.
                _run_semaphore   => Thread::Semaphore->new(),  # A reference to a thread-safe semaphore object to count number of running jobs.
   };
   $this = bless $this, $class;
   $this->EVERY::LAST::_init(%args); # Initialize the whole inheritance hierarchy (parents first)
   $CDV_Dispatchers_created++; # This is a "Class Variables". Don't use $caller-> to set its value.
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
sub Get_CDV_Dispatchers_created {
   # This is a "Class Variables". Don't use $this-> to get its value.
#  my ($this) = @_;
   return $CDV_Dispatchers_created;
}



sub Set_Session_Path {
   my ($this, $session_path) = @_;
   if ($this->{_idle}) {
      $this->{_session_path} = $session_path;
      return 1;
   }
   else {
      return 0;
   }
}



sub Dispatch_Jobs_Thread {
   my ($this) = @_;
   #---------------- Multi-threading Code ---------------------
   # Get a reference to the thread object to be used by the Kill, Suspend and Resume routines.
   $this->{_dispatcher_tobj} = threads->self();
   # Behavior of exit()
   threads->set_thread_exit_only(1); # Calling exit() will cause this thread only to exit. The whole application is still running.
   # Thread 'cancellation' signal handler
   $SIG{'KILL'} = sub { threads->exit(); };
   # Suspend/Resume
   $SIG{'STOP'} = sub {
       $this->{_susp_semaphore}->down(); # Thread suspended (by trying to capture the unavailable semaphore)
       $this->{_susp_semaphore}->up();   # Thread resumes (release the semaphore once captured)
   }
   #--------------------- Main Code ---------------------------
   if ( (not $this->{_idle}) or (not $this->{_session_path}) ) {
      return 0;
   }
   else {
      $this->{_idle} = 0;
      $this->Read_Jobs();
      my $jobs_path = $this->{_session_path} . '/jobs';
      if ((not -d $jobs_path) or (not -e $jobs_path)) {
         die "The passed job path $jobs_path either doesn't refer to a directory or doesn't exist\n";
      }
      opendir(my $jobs_dh, $jobs_path ) or die "Failed to open  $jobs_path:\n$!\n";
      chdir  (   $jobs_dh             ) or die "Failed to enter $jobs_path:\n$!\n";
      # Spawn the Rerun and Track threads
      my $rerun_tobj = threads->create(\&$this->Rerun_Jobs_Thread);
      my $track_tobj = threads->create(\&$this->Track_Jobs_Thread);
      my $max_par_runs = $this->Get_Session_Max_Par_Runs();
      my $current_runs = 0;
      my $vacuous_pass = 0;
      # We do many passes until all jobs are completed (there are re-runnable jobs maintained by the Rerun_Thread)
      while (not $vacuous_pass) {
         $vacuous_pass = 1;
         #--------------------------------------------------------
         #-------------- Critical Section Start ------------------
         #--------------------------------------------------------
         # Scan through all jobs sequentially
         $this->{_jobs_semaphore}->down(); # Capture the semaphore
         foreach my $current_job_ref ( @{ $this->{_jobs} } ) {
            if ($current_job_ref->{completed}) {
               next; # Skip completed jobs
            }
            else {
               $vacuous_pass  = 0;
               my $run_number = $current_job_ref->{run_number};
               my $job_name   = 'run_' . $run_number;
               my $hostname   = $current_job_ref->{hostname};
               my $post_sim   = $cwd . '/job_completed.pl';
               my $cwd        = $jobs_path . '/' . $job_name;
               my $job_path   = $cwd . '/local_job_'.$run_number.'.sh';
               my $err_path   = $cwd . '/bsub_err_%J.log'; # %J will be replaced by the Job ID
               my $out_path   = $cwd . '/bsub_out_%J.log'; # %J will be replaced by the Job ID
               my $bsub_cmd   = 'bsub -q ius ' . $job_path;
               $bsub_cmd     .= qq{ -cwd "$cwd"};     # Current working directory of the job
               $bsub_cmd     .= qq{ -eo $err_path};   # Output error
               $bsub_cmd     .= qq{ -oo $out_path};   # Output log
               $bsub_cmd     .= qq{ -Ep "$post_sim"}; # Post-execution command
               $bsub_cmd     .= qq{ -J "$job_name"};  # Job name
               if ($current_job_ref->{timeout}) {
                  $bsub_cmd .= " -W $current_job_ref->{timeout}"; # Timeout in minutes
               #  $bsub_cmd .= " -c $current_job_ref->{timeout}"; # Timeout in CPU minutes
               }
               if ($hostname) {
                  $bsub_cmd .= qq{ -m "$hostname"}; # Host name
               }
               $current_job_ref->{name} = $job_name;
               if ( (not defined $max_par_runs) or
                       ((defined $max_par_runs) and ($current_runs < $max_par_runs))) {
                  # The jobs submitted are NOT interactive jobs. Therefore, we need to figure out a way to
                  # know when the job completes.
                  system($bsub_cmd);
                  #--------------------------------------------------------
                  #-------------- Critical Section Start ------------------
                  #--------------------------------------------------------
                  # Increment running jobs
                  $this->{_run_semaphore}->down(); # Capture the semaphore
                  $current_runs++;
                  $this->{_run_semaphore}->up();   # Release the semaphore
                  #--------------------------------------------------------
                  #--------------- Critical Section End -------------------
                  #--------------------------------------------------------
               }
               else {
                  #--------------------------------------------------------
                  #--------------- Critical Section End -------------------
                  #--------------------------------------------------------
                  $this->{_jobs_semaphore}->up();   # Release the semaphore temporarily before sleeping
                  sleep JOB_STATUS_UPDATE_PERIOD;
                  $this->{_jobs_semaphore}->down(); # Capture the semaphore again to proceed
                  #--------------------------------------------------------
                  #-------------- Critical Section Start ------------------
                  #--------------------------------------------------------
                  redo;     # Keep polling until a slot becomes available
               }
            }
         }
         $this->{_jobs_semaphore}->up();   # Release the semaphore
         #--------------------------------------------------------
         #--------------- Critical Section End -------------------
         #--------------------------------------------------------
      }
      # Signal the threads to terminate, and then detach
      # them so that they will get cleaned up automatically
      $rerun_tobj->kill('KILL')->detach();
      $track_tobj->kill('KILL')->detach();
      $this->{_idle} = 1;
      closedir $jobs_dh;
      return 1;
   }
}


sub Rerun_Jobs_Thread {
   my ($this) = @_;
   #---------------- Multi-threading Code ---------------------
   # Behavior of exit()
   # Calling exit() will cause this thread only to exit.
   # The whole application is still running.
   threads->set_thread_exit_only(1);
   # Thread 'cancellation' signal handler
   $SIG{'KILL'} = sub { threads->exit(); };
   #--------------------- Main Code ---------------------------
   while (1) {
      #--------------------------------------------------------
      #-------------- Critical Section Start ------------------
      #--------------------------------------------------------
      # Resume all jobs currently submitted
      $this->{_jobs_semaphore}->down(); # Capture the semaphore
      foreach my $current_job_ref ( @{ $this->{_jobs} } ) {
         if ($current_job_ref->{completed} and $current_job_ref->{auto_rerun_covscope}) {
            if ($this->{_cov_agent}->Can_Rerun($current_job_ref->{testcase})) {
               # $current_job_ref->{completed} = 0;
               push @{ $this->{_jobs} } $this->Clone_Run($current_job_ref);
            }
         }
      }
      $this->{_jobs_semaphore}->up(); # Release the semaphore
      #--------------------------------------------------------
      #--------------- Critical Section End -------------------
      #--------------------------------------------------------
   }
   return;
}


sub Track_Jobs_Thread {
   my ($this) = @_;
   #---------------- Multi-threading Code ---------------------
   # Behavior of exit()
   threads->set_thread_exit_only(1); # Calling exit() will cause this thread only to exit. The whole application is still running.
   # Thread 'cancellation' signal handler
   $SIG{'KILL'} = sub { threads->exit(); };
   #--------------------- Main Code ---------------------------
   while (1) {
      sleep JOB_STATUS_UPDATE_PERIOD;
      #--------------------------------------------------------
      #-------------- Critical Section Start ------------------
      #--------------------------------------------------------
      # Update all jobs currently completed
      $this->{_jobs_semaphore}->down(); # Capture the semaphore
      foreach my $current_job_ref ( @{ $this->{_jobs} } ) {
         my $job_completed_path = $current_job_ref->{run_dir_path} . '/job_completed.txt';
         if (not -e $job_completed_path) {
            next;
         }
         else {
            open(my $job_completed_fh, '<', $job_completed_path ) or die "Cannot create $job_completed_path:\n$!\n";
            local undef $/;
            my $job_completed_message = <$job_completed_fh>;
            if ($local_vsof =~ m/\s+$ENV{COMPLETE_MESSAGE}\s+/s) {
               $current_job_ref->{completed} = 1;
               #--------------------------------------------------------
               #-------------- Critical Section Start ------------------
               #--------------------------------------------------------
               # Increment running jobs
               $this->{_run_semaphore}->down(); # Capture the semaphore
               $current_runs--;
               $this->{_run_semaphore}->up();   # Release the semaphore
               #--------------------------------------------------------
               #--------------- Critical Section End -------------------
               #--------------------------------------------------------
            }
         }
      }
      $this->{_jobs_semaphore}->up(); # Release the semaphore
      #--------------------------------------------------------
      #--------------- Critical Section End -------------------
      #--------------------------------------------------------
   }
   return;
}


# The following subroutines are called by the main thread and execute in its context
sub Kill_Jobs {
   my ($this) = @_;
   if ($this->{_dispatcher_tobj}) {
      #--------------------------------------------------------
      #-------------- Critical Section Start ------------------
      #--------------------------------------------------------
      # Kill all jobs currently submitted
      $this->{_jobs_semaphore}->down(); # Capture the semaphore
      foreach my $current_job_ref ( @{ $this->{_jobs} } ) {
         if (not $current_job_ref->{completed}) {
            my $kill_cmd = 'bkill -J ' . $current_job_ref->{name};
            system($kill_cmd);
         }
      }
      $this->{_jobs_semaphore}->up(); # Release the semaphore
      #--------------------------------------------------------
      #--------------- Critical Section End -------------------
      #--------------------------------------------------------
      # Signal the thread to terminate, and then detach
      # it so that it will get cleaned up automatically
      $this->{_dispatcher_tobj}->kill('KILL')->detach();
      return 1;
   }
   else {
      return 0;
   }
}



sub Suspend_Jobs {
   my ($this) = @_;
   if ($this->{_dispatcher_tobj}) {
      # Suspend the dispatcher thread
      # 1- Capture the semaphore on which the dispatcher will wait.
      $this->{_susp_semaphore}->down();
      # 2- Send the dispatcher the signal to make it wait on the semaphore just captured
      $this->{_dispatcher_tobj}->kill('STOP');
      #--------------------------------------------------------
      #-------------- Critical Section Start ------------------
      #--------------------------------------------------------
      # Suspend all jobs currently submitted
      $this->{_jobs_semaphore}->down(); # Capture the semaphore
      foreach my $current_job_ref ( @{ $this->{_jobs} } ) {
         if (not $current_job_ref->{completed}) {
            my $suspend_cmd = 'bstop -J ' . $current_job_ref->{name};
            system($suspend_cmd);
         }
      }
      $this->{_jobs_semaphore}->up(); # Release the semaphore
      #--------------------------------------------------------
      #--------------- Critical Section End -------------------
      #--------------------------------------------------------
      return 1;
   }
   else {
      return 0;
   }
}


sub Resume_Jobs {
   my ($this) = @_;
   if ($this->{_dispatcher_tobj}) {
      #--------------------------------------------------------
      #-------------- Critical Section Start ------------------
      #--------------------------------------------------------
      # Resume all jobs currently submitted
      $this->{_jobs_semaphore}->down(); # Capture the semaphore
      foreach my $current_job_ref ( @{ $this->{_jobs} } ) {
         if (not $current_job_ref->{completed}) {
            my $resume_cmd = 'bresume -J ' . $current_job_ref->{name};
            system($resume_cmd);
         }
      }
      $this->{_jobs_semaphore}->up(); # Release the semaphore
      #--------------------------------------------------------
      #--------------- Critical Section End -------------------
      #--------------------------------------------------------
      # Resume the dispatcher thread
      $this->{_susp_semaphore}->up(); # Let the dispatcher to resume by releasing the semaphore on which it's waiting.
      return 1;
   }
   else {
      return 0;
   }
}


sub Read_Jobs {
   my ($this) = @_;
   my $run_params_fname = 'run_params.txt';
   my $jobs_path = $this->{_session_path} . '/jobs';
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
         my %current_job = (run_number => $1);
         opendir(my $run_dh, $current_dir ) or die "Failed to open  $current_dir:\n$!\n";
         chdir(     $run_dh )               or die "Failed to enter $current_dir:\n$!\n";
         open(my $run_params_fh, '<', $run_params_fname) or
                die "Cannot create $current_dir\/$run_params_fname:\n$!\n";
         local undef $/;
         my $run_params  = <$run_params_fh>;
         while ($run_params !~ m/^\s*$/s) { # Read dispatcher-related run parameters
            if ($run_params =~ s/\s*auto_rerun_covscope\s*:\s*([\w\/\.]+)\s*\;\s*/\t/s) {
               $current_job{auto_rerun_covscope} = $1;
            }
            elsif ($run_params =~ s/\s*timeout\s*\:\s*(\d+)\s*\;\s*/\t/) {
               $current_job{timeout} = $1;
            }
            elsif ($run_params =~ s/\s*hostname\s*\:\s*(.+)\s*\;\s*/\t/m) {
               $current_job{hostname} = $1;
            }
         }
         push @{ $this->{_jobs} }, dclone \%current_job;
         close    $run_params_fh;
         chdir ( File::Spec->updir() ) or die "Failed to return up the directory $current_dir:\n$!\n";
         closedir $run_dh;
      };
   }
   closedir $jobs_dh;
   return 1;
}


sub Get_Session_Max_Par_Runs {
   my ($this) = @_;
   my $session_params_path = $this->{_session_path} . '/session_params.txt';
   open(my $session_params_fh, '<', $session_params_path) or
                 die "Cannot create $session_params_fname:\n$!\n";
   local undef $/;
   my $session_params  = <$session_params_fh>;
   my $max_par_runs;
   if ($session_params =~ m/\s*max_par_runs\s*\:\s*(\d+)\s*\;\s*/) {
      $max_par_runs = $1;
   }
   else {
      $max_par_runs = undef;
   }
   close $session_params_fh;
   return $max_par_runs;
}



sub Clone_Run {
   my ($this, $original_job_ref) = @_;
   return;
}




sub Query_Job_Status {
   my ($this) = @_;
   return;
}


1;


__END__



 
