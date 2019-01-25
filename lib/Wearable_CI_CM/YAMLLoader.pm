package Wearable_CI_CM::YAMLLoader;

=head1 YAMLLoader.pm

A perl module to load YAML files into perl data structures, and perform
limited post/pre-processing.

It's intended to be used by modules performing checks on analysis on the data
as a shared loader to avoid code duplication and / or loading files to memory
multiple times.

=cut

use strict;
use YAML::XS qw(LoadFile);
use Data::Dumper;

sub new{
  shift;
  my $o=shift;
  my $s={};

  bless $s;
  $s;
}

=item dumpDataSection($var)

Dump a YAML file loaded into C<< $var >> by C<< loadFromFile >>.

=cut

sub dumpDataSection {
  my $s=shift;
  my $var=shift;

  print Dumper($s->{data}->{$var});
}

=item loadFromFile($file, $var)

Load a YAML file C<< $file >> from disk, and store it in a section named
by C<< $var >>.

=cut

sub loadFromFile {
  my $s=shift;
  my $file=shift;
  my $var=shift;

  return unless (defined $var);

  $s->{data}->{$var} = LoadFile $file;
}

1;
