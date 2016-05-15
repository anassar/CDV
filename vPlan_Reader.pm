package vPlan_Reader;

use base qw(Exporter);
use strict;
use warnings;
use Storable qw(dclone);
use XML::Simple qw(:strict);

# Class Variables
my $vPlan_Readers_created = 0;


our @EXPORT = qw( Read_vPlan
                  Annotate_vPlan_with_Coverage
                );

our @EXPORT_OK = qw();
our $VERSION   = 1.00;

######################################################################################
# vPlan Editor Capabilities:
# 1- Exporting the vPlan to customizable HTML format for publishing it on the web.
# 2- Exporting the vPlan to XML format to be read and annotated by the vPlan_Reader.
# 3- Reusing verification plans across projects or from module to system level.
# 4- Linking vPlan features to coverage metrics, thus proving TRACEABILITY.
# Coverage model is implemented in Verilog modules in one of the following ways:
# 1- A coverage module that only contains PSL assertions.
# 2- A coverage module that contains nothing and is bound to a PSL VUNIT.
# 3- A coverage module that only contains SVA coverpoints and covergroups.
######################################################################################



# Constructor
sub new {
   my ($caller, %args) = @_;
   my $class = ref($caller) || $caller;
   my $this = {
                _vplan_path         => undef, # The vPlan file path
                _vplan              => {},    # A reference to an empty hash
                _vplan_sections     => [],    # A reference to an empty array
                _vplan_perspectives => [],    # A reference to an empty array
                _xml_handler        => undef, # A reference to the XML object
                _cov_agent          => undef, # A reference to the coverage agent object
   };
   #---------- Using XML::Simple OO Interface
   # Specify options to have a regular structure in memory, one which is very easy to deal with programmatically.
   # Making this definition in one place is important to keep consistency of vPlan reading and writing.
   # The ForceArray option is especially useful if the data structure is likely to be written back out as XML and
   # the default behaviour of "rolling single nested elements up into attributes" is not desirable.
   $this->{_xml_handler} = XML::Simple->new(KeyAttr        => [], # Disable array folding into hashes and hash unfolding into arrays
                                            ForceArray     => 1,  # Force nested elements to be represented as arrays
                                            KeepRoot       => 1,
                                            AttrIndent     => 1,  # Attributes are printed one-per-line with sensible indentation rather than all on one line
                                            NoAttr         => 1,  # XMLout() represents all hash key/value pairs as nested elements. XMLin() ignores any attributes in the XML.
                                            NormalizeSpace => 1,  # whitespace is normalised in any value used as a hash key (normalising means removing leading and trailing whitespace and collapsing sequences of whitespace characters to a single space).
                                            );




   $this = bless $this, $class;
   $this->EVERY::LAST::_init(%args); # Initialize the whole inheritance hierarchy (parents first)
   $vPlan_Readers_created++; # This is a "Class Variables". Don't use $caller-> to set its value.
   return $this;
}

sub Set_Cov_Agent {
   my ($this, $cov_agent) = @_;
   $this->{_cov_agent} = $cov_agent;
   return;
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
sub get_vPlan_Readers_created {
   # This is a "Class Variables". Don't use $this-> to get its value.
   # my ($this) = @_;
   return $vPlan_Readers_created;
}



sub Read_vPlan {
   my ($this, $vplan_path) = @_;
   if (not -e $vplan_path or not -r $vplan_path) {
      die "The given vPlan file doesn't exist or is not readable";
   }
   $this->{_vplan_path} = $vplan_path;
   # Read the XML vPlan file into a hierarchical Perl data structure (a mixture of anonymous arrays and hashes)
   $this->{_vplan}      = $this->{_xml_handler}->XMLin($vplan_path);
   #---------------------------------------------------------------
   #--------------------- Validity Check --------------------------
   #---------------------------------------------------------------
   my $vPlan_elements;
   my $vPlan_sections;
   my $vPlan_perspectives;
   # Get a reference to an array of all subelements in the vPlan
   if ($this->{_vplan}->{vPlan}) {
      $vPlan_elements = $this->{_vplan}->{vPlan};
   }
   else {
      die "The given vPlan doesn't contain a top vPlan element";
   }
   # Extract the vPlan attributes and sections
   foreach my $hash_ref (@{ $vPlan_elements }) {
      if ($hash_ref->{name}) {
         $this->{_vplan_name} = $hash_ref->{name}->[0];
      }
      elsif ($hash_ref->{section}) {
         $this->{_vplan_sections} = $hash_ref->{section};
      }
      elsif ($hash_ref->{perspective}) {
         $this->{_vplan_perspectives} = $hash_ref->{perspective};
      }
      else {
         die "The given vPlan contains an unrecognized element type other than Sections and Perspectives";
      }
   }
   if (not @{ $vPlan_perspectives }) {
      die "The given vPlan doesn't contain a Perspectives list";
   }
   elsif (not @{ $vPlan_sections }) {
      die "The given vPlan doesn't contain a Sections list";
   }
   return;
}



sub Annotate_vPlan_With_Coverage {
   my ($this) = @_;
   $this->Annotate_Section_With_Coverage($this->{_vplan_sections});
   return;
}


sub Annotate_Section_With_Coverage {
   my ($this, $given_section) = @_;
   my $coverage = 0;
   my $weight   = 100;
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $coverage += $this->Annotate_Section_With_Coverage($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $modules   = join (" ", @{ $hash_ref->{verif_scope}->{module  } });
         my $instances = join (" ", @{ $hash_ref->{verif_scope}->{instance} });
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         $coverage += $this->{_cov_agent}->Report_Coverage(modules   => $modules,
                                                           instances => $instances,
                                                           coverages => $coverages);
      }
      elsif ($hash_ref->{weight}) {
         $weight = $hash_ref->{weight};
      }
   }
   #-----------------------------------------------------------------
   # Annotate the current section by adding a coverage element to its
   # element array.
   #-----------------------------------------------------------------
   push @{ $given_section }, {coverage => [$coverage]};
   #-----------------------------------------------------------------
   # Pass the coverage contribution of the current section to higher-
   # level recursive calls.
   #-----------------------------------------------------------------
   return ($coverage * ($weight))/100;
}




sub Write_vPlan {
   my ($this) = @_;
   my $vplan_path = $this->{_vplan_path};
   $vplan_path =~ s/.+?/.xml$//; # Remove the .xml extension
   open(my $vplan_fh, '>', "$vplan_path_cov.xml") or die "Cannot create $vplan_path_cov.xml:\n$!\n";
   # The default behaviour of XMLout() is to return the XML as a string.
   # If you wish to write the XML to a file, simply supply the filename using the 'OutputFile' option.
   # XMLout($ref, OutputFile => $fh);
   $this->{_xml_handler}->XMLout($this->{_vplan}, OutputFile => $vplan_fh);
   close $vplan_fh;
   return;
}




sub Get_BlockCov_Modules {
   my ($this, $verif_perspective) = @_;
   my $modules = $this->Get_Section_BlockCov_Modules($this->{_vplan_sections});
   return $modules;

}


sub Get_Section_BlockCov_Modules {
   my ($this, $given_section) = @_;
   my $modules = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $modules .= $this->Get_Section_BlockCov_Modules($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-b/i) {
            $modules .= join (" ", @{ $hash_ref->{verif_scope}->{module  } });
         }
      }
   }
   return $modules;
}


sub Get_BlockCov_Instances {
   my ($this, $verif_perspective) = @_;
   my $instances = $this->Get_Section_BlockCov_Instances($this->{_vplan_sections});
   return $instances;

}


sub Get_Section_BlockCov_Instances {
   my ($this, $given_section) = @_;
   my $instances = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $instances .= $this->Get_Section_BlockCov_Instances($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-b/i) {
            $instances .= join(" ", @{ $hash_ref->{verif_scope}->{instance} });
         }
      }
   }
   return $instances;
}


sub Get_ExprCov_Modules {
   my ($this, $verif_perspective) = @_;
   my $modules = $this->Get_Section_ExprCov_Modules($this->{_vplan_sections});
   return $modules;

}


sub Get_Section_ExprCov_Modules {
   my ($this, $given_section) = @_;
   my $modules = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $modules .= $this->Get_Section_ExprCov_Modules($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-e/i) {
            $modules .= join (" ", @{ $hash_ref->{verif_scope}->{module  } });
         }
      }
   }
   return $modules;

}


sub Get_ExprCov_Instances {
   my ($this, $verif_perspective) = @_;
   my $instances = $this->Get_Section_ExprCov_Instances($this->{_vplan_sections});
   return $instances;

}



sub Get_Section_ExprCov_Instances {
   my ($this, $given_section) = @_;
   my $instances = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $instances .= $this->Get_Section_ExprCov_Instances($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-e/i) {
            $instances .= join(" ", @{ $hash_ref->{verif_scope}->{instance} });
         }
      }
   }
   return $instances;
}


sub Get_FSMCov_Modules {
   my ($this, $verif_perspective) = @_;
   my $modules = $this->Get_Section_FSMCov_Modules($this->{_vplan_sections});
   return $modules;
}



sub Get_Section_FSMCov_Modules {
   my ($this, $given_section) = @_;
   my $modules = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $modules .= $this->Get_Section_FSMCov_Modules($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-s/i) {
            $modules .= join (" ", @{ $hash_ref->{verif_scope}->{module  } });
         }
      }
   }
   return $modules;
}


sub Get_FSMCov_Instances {
   my ($this, $verif_perspective) = @_;
   my $instances = $this->Get_Section_FSMCov_Instances($this->{_vplan_sections});
   return $instances;
}




sub Get_Section_FSMCov_Instances {
   my ($this, $given_section) = @_;
   my $instances = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $instances .= $this->Get_Section_FSMCov_Instances($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-s/i) {
            $instances .= join(" ", @{ $hash_ref->{verif_scope}->{instance} });
         }
      }
   }
   return $instances;
}


sub Get_ToggleCov_Modules {
   my ($this, $verif_perspective) = @_;
   my $modules = '';
   my $modules = $this->Get_Section_ToggleCov_Modules($this->{_vplan_sections});
   return $modules;

}



sub Get_Section_ToggleCov_Modules {
   my ($this, $given_section) = @_;
   my $modules = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $modules .= $this->Get_Section_ToggleCov_Modules($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-t/i) {
            $modules .= join (" ", @{ $hash_ref->{verif_scope}->{module  } });
         }
      }
   }
   return $modules;

}


sub Get_ToggleCov_Instances {
   my ($this, $verif_perspective) = @_;
   my $instances = $this->Get_Section_ToggleCov_Instances($this->{_vplan_sections});
   return $instances;
}



sub Get_Section_ToggleCov_Instances {
   my ($this, $given_section) = @_;
   my $instances = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $instances .= $this->Get_Section_ToggleCov_Instances($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-t/i) {
            $instances .= join(" ", @{ $hash_ref->{verif_scope}->{instance} });
         }
      }
   }
   return $instances;
}


sub Get_FuncCov_Modules {
   my ($this, $verif_perspective) = @_;
   my $modules = '';
   my $modules = $this->Get_Section_FuncCov_Modules($this->{_vplan_sections});
   return $modules;

}



sub Get_Section_FuncCov_Modules {
   my ($this, $given_section) = @_;
   my $modules = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $modules .= $this->Get_Section_FuncCov_Modules($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-f/i) {
            $modules .= join (" ", @{ $hash_ref->{verif_scope}->{module  } });
         }
      }
   }
   return $modules;

}


sub Get_FuncCov_Instances {
   my ($this, $verif_perspective) = @_;
   my $instances = $this->Get_Section_FuncCov_Instances($this->{_vplan_sections});
   return $instances;
}




sub Get_Section_FuncCov_Instances {
   my ($this, $given_section) = @_;
   my $instances = '';
   #-----------------------------------------------------------------
   # Traverse the given section recursively in a depth-first fashion.
   #-----------------------------------------------------------------
   for each my $hash_ref (@{ $given_section }) {
      if ($hash_ref->{section}) { # The given section contains nested subsections
         #----------------------------------------------------
         #---------------------- RECURSION -------------------
         #----------------------------------------------------
         $instances .= $this->Get_Section_FuncCov_Instances($hash_ref->{section});
      }
      elsif ($hash_ref->{verif_scope}) { # The given section contains verif_scope elements
         my $coverages = join (" ", @{ $hash_ref->{verif_scope}->{covType } });
         if ($coverages =~ m/-f/i) {
            $instances .= join(" ", @{ $hash_ref->{verif_scope}->{instance} });
         }
      }
   }
   return $instances;
}





1;




__END__


XML::Simple
    * Discards the name of the root element.
    * Collapses elements with the same name into a single reference to an anonymous array.
    * Treats attributes and subelements identically.
You can change each of these behaviors by options to XMLin().

The XML document is transformed into a tree structure:
The (KeepRoot=>1) option causes the name of the root element to be retained.
The whole document is represented by a single-element hash with the root element name as the single key.
The root element is associated with a reference to an array of hashes representing all document elements.
Every XML element name is used as the name of a node in the tree and represented as a key in a hash that is
associated with a reference to an array of all subelements (each represented as a hash).

