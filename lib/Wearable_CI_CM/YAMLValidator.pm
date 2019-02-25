package Wearable_CI_CM::YAMLValidator;

=head1 Wearable_CI_CM::YAMLValidator.pm

A perl module to validate structures in ansible YAML data.

As YAML just contains structures without a way to give the data meaning
it's not possible to easily validate a YAML file.

This module reads in ansible YAML files, and tries to validate the data
according to the rules documented within the CI ansible modules. As far
as possible it tries to continue validation of an entry even after errors.

=cut

=head2 Module functions

=over

=cut

use strict;
use Wearable_CI_CM::YAMLLoader;
use Algorithm::Diff qw(traverse_sequences);

=item new()

Create a new validator object. One validator object per script should be
sufficient.

C<< Wearable_CI_CM::YAMLValidator->new() >>

=cut

sub new{
  shift;
  my $o=shift;
  my $s={};

  if (ref($o) eq "Wearable_CI_CM::YAMLLoader"){
    $s->{loader} = $o;
  } else {
    $s->{loader} = new Wearable_CI_CM::YAMLLoader;
  }

  $s->{result}->{
                 warnings => 0,
                 errors => 0,
                 warning_messages => "",
                 error_messages => "",
                 };

  bless $s;
  $s;
}

=item loadFromFile($file, $var)

Load a YAML file C<< $file >> from disk, and store it in a section named
by C<< $var >>.

=cut

sub loadFromFile {
  my $s=shift;

  $s->{loader}->loadFromFile(@_);
}

=item compareInterfaceLists($type, $machine, $phy_list, $type_list)

Check that associations of advanced network types (vlans, bridges, ...) to
physical devices are correct for type C<< $type >> on machine C<< $machine >>.

C<< $type >> and C<< $machine >> are used for logging purposes only, and need
to identify the correct ansible section for correcting errors.

C<< $phy_list >> is a list of configurations attached to a physical interface,
while C<< $type_list >> is a list of interfaces of the specific type.

=cut

sub compareInterfaceLists {
  my $s=shift;

  my $type=shift;
  my $machine=shift;
  my $phy_list=shift;
  my $type_list=shift;

  # compare the two vlan lists collected earlier in the pass, and throw
  # appropriate error messages if an item is missing from one of the lists
  if (defined $phy_list or defined $type_list){
    if (!defined $phy_list){
      $s->{result}->{errors}++;
      $s->{result}->{error_messages}.=
        "Physical interface missing $type list for $machine\n";
    } elsif (!defined $type_list){
      $s->{result}->{errors}++;
      $s->{result}->{error_messages}.=
        "$type list missing for $machine\n";
    } else {
      my @phy=sort @{$phy_list};
      my @tp=sort @{$type_list};

      traverse_sequences
        (\@phy, \@tp,
         {
          MATCH => sub{ },
          DISCARD_A =>
          sub{ my $i=shift;
               $s->{result}->{errors}++;
               $s->{result}->{error_messages}.=
                 "$type defined without physical interface: '$phy[$i]' on $machine\n";
               $s->{result}->{error_messages}.="Phy:\n". join("\n\t", @phy)."\n";
               $s->{result}->{error_messages}.="Tp:\n". join("\n\t", @tp)."\n";
             },
          DISCARD_B => sub{ my $i1=shift; my $i2=shift;
                            $s->{result}->{errors}++;
                            $s->{result}->{error_messages}.=
                              "$type only defined on physical interface: '$tp[$i2]' on $machine\n";
               $s->{result}->{error_messages}.="Phy:\n". join("\n\t", @phy)."\n";
               $s->{result}->{error_messages}.="Tp:\n". join("\n\t", @tp)."\n";
                          },
         });
    }
  }
}

=item validateNetworkSection($var)

Validate a network configuration section (item C<< network_nodes >>) stored
in the configuration section named C<< $var >>.

=cut

sub validateNetworkSection {
  my $s=shift;
  my $var=shift;

  my $network_nodes=$s->{loader}->{data}->{$var}->{network_nodes};

  # loop over all network nodes, and check them individually some keys (like
  # VM assignments) require performing additional checks on hosts not the
  # current one
  foreach my $key (sort(keys %$network_nodes)){
    my $system=%$network_nodes{$key};
    # systems without a 'type' key are now illegal. Failing this as first check
    # potentially masks later errors in this host entry, though several entries
    # can't be properly validated without a type specification anyway
    if (not defined %$system{type}){
      $s->{result}->{errors}++;
      $s->{result}->{error_messages}.="Type missing: $key\n";
    } else {
      my $type=%$system{type};
      # exclude everything not directly mounted into a rack by itself
      if ($type ne "lxc" and $type ne "kvm" and $type ne "dns" and
          $type ne "workstation" and $type ne "ilo"){

        # and check if whatever is left has a rack it's mounted into defined
        if (not defined %$system{rack} and
            (not defined %$system{rack_mounted} or %$system{rack_mounted} != 0 )){
          $s->{result}->{errors}++;
          $s->{result}->{error_messages}.="Racked hardware without rack: $key\n";
        }
      } else {
        # from what's left, everything but workstations and generic DNS
        # configurations should be assigned to a rack mounted machine
        if (not defined %$system{machine} and
            $type ne "workstation" and $type ne "dns"){
          $s->{result}->{errors}++;
          $s->{result}->{error_messages}.="VM or IPMI without machine: $key\n";
        }
      }

      # the vlans variable will contain two arrays, one for all vlans tied
      # to physical interfaces, one for all vlan configurations.
      # after the iface validation run those two lists get compared for
      # validating the vlan configuration.
      my $vlans;
      my $bridges;
      my $bonds;
      # verify network interfaces of the current system
      my $networks=%$system{networks};
      foreach my $if_key (sort(keys %$networks)){
        # interfaces with a physical network port are expected to have a switch
        # port assigned. For direct connections this may be set to -1 (but still
        # needs to be present)
        # servers may have additional, non-physical interfaces connected. Those
        # are handled separately by checking if they have the correct type set,
        # and then do additional verification for this type of interface.
        if ($type eq "server" or $type eq "ilo" or $type eq "ipmi" or $type eq "workstation"){
          if (not defined %$networks{$if_key}->{port}){
            # shared ports are physical ports shared between two or more MACs
            # a typical setup is a server with an IPMI/ILo interface sharing
            # one of the network interfaces.
            # for shared ports the specified interface needs to be checked
            # against the other interfaces of this system. If it's exist
            # it should be OK, as the interface is checked itself as physical
            # interface
            if (defined %$networks{$if_key}->{'shared-port'}){
              my @shared_network=split /\s*,\s*/, %$networks{$if_key}->{'shared-port'};
              if (not defined %$network_nodes{$shared_network[0]}->{networks}
                  ->{$shared_network[1]}){
                $s->{result}->{errors}++;
                $s->{result}->{error_messages}.=
                  "Physical port $shared_network[0]:$shared_network[1] not found for shared network $if_key\n";
              }
              # VLans are tied to a physical interface. However, the VLan
              # interface itself does not need to know about the physical
              # interface - the linking happens inside the physical interface.
              # To verify all physical interfaces of the current node needs to
              # be checked for this VLan
            } elsif (defined %$networks{$if_key}->{type}
                     and %$networks{$if_key}->{type} eq "vlan"){
              print "VLan: $key, $if_key\n";
              push @{$vlans->{phy}}, $if_key =~ /^vl.(.*)/g;
            } elsif (defined %$networks{$if_key}->{type}
                     and %$networks{$if_key}->{type} eq "bridge"){
              print "Bridge: $key, $if_key\n";
              push @{$bridges->{phy}}, $if_key;
            } elsif (defined %$networks{$if_key}->{type}
                     and %$networks{$if_key}->{type} eq "bond"){
              print "Bond: $key, $if_key\n";
              push @{$bonds->{phy}}, $if_key;
              # anything left at this point is a physical interface without a
              # port specification -> error
            } else {
              $s->{result}->{errors}++;
              $s->{result}->{error_messages}.=
                "Physical interface without port: $key, $if_key\n";
            }
          }
        }

        if (defined %$networks{$if_key}->{vlans}){
          push(@{$vlans->{vl}}, @{%$networks{$if_key}->{vlans}});
        }

        if (defined %$networks{$if_key}->{bridge}){
          push(@{$bridges->{br}}, %$networks{$if_key}->{bridge});
        }

        if (defined %$networks{$if_key}->{bond}){
          my $bond_if=%$networks{$if_key}->{bond};
          # multiple interfaces belong to one bond, but only one is needed to
          # verify the phy<>bond mapping
          unless (grep(/^$bond_if$/, @{$bonds->{bn}})){
            push(@{$bonds->{bn}}, $bond_if);
          }
        }
        # instead of standalone an ilo/ipmi card might be specified as a network
        # interface named 'ilo' within the server it belongs to. In that case
        # it is expected that a vlan key is defined, and set to 'ilo'
        if ($if_key eq "ilo"){
          if (not defined %$networks{$if_key}->{vlan}){
            $s->{result}->{errors}++;
            $s->{result}->{error_messages}.=
              "ILO interface without VLan: $key, $if_key\n";
          } elsif (%$networks{$if_key}->{vlan} ne "ilo"){
            $s->{result}->{errors}++;
            $s->{result}->{error_messages}.=
              "ILO interface outside 'ilo' VLan: $key, $if_key\n";
          }
        }
      }

      # compare the two vlan lists collected earlier in the pass, and throw
      # appropriate error messages if an item is missing from one of the lists
      $s->compareInterfaceLists("VLan", $key, $vlans->{phy}, $vlans->{vl});
      $s->compareInterfaceLists("Bridge", $key, $bridges->{phy}, $bridges->{br});
      $s->compareInterfaceLists("Bond", $key, $bonds->{phy}, $bonds->{bn});
    }
  }
}


=item errors()

Return the number of errors encountered while validating YAML data so far.

=cut

sub errors {
  my $s=shift;
  $s->{result}->{errors};
}

=item warnings()

Return the number of warnings encountered while validating YAML data so far.

=cut

sub warnings {
  my $s=shift;
  $s->{result}->{warnings};
}

=item results()

Print the number of errors/warnings encountered so far, as well as any stored
warning/error messages.

A script used for gating should call this function after validation, and then
return the number of errors gotten from C<< errors() >> as exit status.

=cut

sub results {
  my $s=shift;

  if ($s->{result}->{warnings} != 0){
    print "Warnings:\t ". $s->{result}->{warnings}."\n\n";
    print $s->{result}->{warning_messages};
  }
  if ($s->{result}->{errors} != 0){
    print "\nErrors:\t ". $s->{result}->{errors}."\n\n";
    print $s->{result}->{error_messages};
  }
}

1;

=back

=cut
