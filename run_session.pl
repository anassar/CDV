#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use threads;



#--------------------------------------------------------
#---------------- Get command-line arguments ------------
#--------------------------------------------------------
if(@ARGV) {
   GetOptions (
              'help'   => \$help,
              'vsif'   => \$vsif,
              'vplan'  => \$vplan,
              'no_run' => \$no_run, # Don't run regression. But only generate the detailed reports requested in the vPlan
              );
}
else { 
   print "run_regression.pl : ********* No options specified *********";
   usage();
   exit();
}


#--------------------------------------------------------
#------------------ Create Objects ----------------------
#--------------------------------------------------------
print "------------ Creating Objects -----------------\n";
my $vsif_reader     =     VSIF_Reader->new();
my $vPlan_Reader    =    vPlan_Reader->new();
my $session_tracker = Session_Tracker->new();
my $CDV_Dispatcher  =  CDV_Dispatcher->new();
my $Coverage_Agent  =  Coverage_Agent->new();


#--------------------------------------------------------
#------------------ Connect Objects ---------------------
#--------------------------------------------------------
print "------------ Connecting Objects -----------------\n";
$vsif_reader     -> Set_vPlan_Reader   ($vPlan_Reader  );
$Coverage_Agent  -> Set_vPlan_Reader   ($vPlan_Reader  );
$Coverage_Agent  -> Set_CDV_Dispatcher ($CDV_Dispatcher);
$Coverage_Agent  -> Set_Session_Reader ($vsif_reader   );
$session_tracker -> Set_Session_Reader ($vsif_reader   );
$CDV_Dispatcher  -> Set_Session_Reader ($vsif_reader   );
$CDV_Dispatcher  -> Set_Coverage_Agent ($Coverage_Agent);
$vPlan_Reader    -> Set_Coverage_Agent ($Coverage_Agent);



#--------------------------------------------------------
#-------------------- Run Session -----------------------
#--------------------------------------------------------
print "------------ Starting Session -----------------\n";
$vsif_reader  -> Read_VSIF();
$vPlan_Reader -> Read_vPlan();
$vsif_reader  -> Elaborate_VSIF();

my $job_dispatch_thread  = threads->create( \&$CDV_Dispatcher->Dispatch_Jobs_Thread() );
my $job_rerun_thread     = threads->create( \&$CDV_Dispatcher->Rerun_Jobs_Thread() );
my $job_track_thread     = threads->create( \&$CDV_Dispatcher->Track_Jobs_Thread() );
my $session_track_thread = threads->create( \&$session_tracker->Track_Session_Thread() );


print "------------ Updating vPlan -----------------\n";
$vPlan_Reader -> Annotate_vPlan_With_Coverage();
$vPlan_Reader -> Write_vPlan();


print "------------ Session Completed --------------\n";

exit(1);


__END__



