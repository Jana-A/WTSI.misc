#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use WWW::Mechanize;
use Getopt::Long;
use Try::Tiny;
#use Term::ReadKey;
use JSON::Parse 'json_file_to_perl';
use JSON 'encode_json';

#ReadMode("noecho");
#print "Enter pass:";
#chomp (my $passw = <>);
#ReadMode("original");

## main
## ----
my $config_path;
my $plates_path;
my $output;

GetOptions(
    'config=s' => \$config_path,
    'plates=s' => \$plates_path,
    'output=s' => \$output
);

my $config = load_config($config_path);
my $mech = htgt_login (&mech_init);

open FH, '<' . $plates_path;
my @data = (<FH>);
close FH;

my $header = shift @data;

open WH, '>' . $output;

my $count = 0;
my @res;

foreach my $l (@data) {
    ## chomp doesn't remove \r so use regex instead
    $l =~ s/\r?\n$//;
    my $line_data;

    my @temp_l = split ",", $l;
    my ($q1,$q3,$q2,$q4,$forth,$fifth) = @temp_l;
    my %qs = (Q1 => $q1, Q2 => $q2, Q3 => $q3, Q4 => $q4);

    $line_data->{'Date Made'} = $forth;
    $line_data->{'Plate Name'} = $fifth;

    foreach my $q (keys %qs) {
        print "\nobtaining csv data for $q " . $qs{$q} . "...\n";
        my $temp_csv = find_plate_data($mech, $qs{$q});
        $mech->get( $config->{htgt_welcome_url} );
        my @csv_arr = split "\n", $temp_csv;
        my @csv_header = split ",", shift @csv_arr;

        foreach my $line (@csv_arr) {
            ## chomp doesn't remove \r
            $line =~ s/\r?\n$//;
            my $temp_hash;
            my @temp_values = split ",", $line;
            foreach my $indx (0..scalar @csv_header) {
                $temp_hash->{$csv_header[$indx]} = $temp_values[$indx];
            }
            push @{$line_data->{'child_plates'}->{$q}}, $temp_hash;
        }
    }
    push @res, $line_data;
    $count++;
}

#print Dumper @res;

print WH encode_json({ data => \@res });

close WH;

## logout
$mech->get( $config->{htgt_welcome_url} );
$mech->follow_link(text => 'LOGOUT');


sub load_config {
    my $path = shift;
    return json_file_to_perl($path);
}

sub mech_init {
    my $mech_handle = WWW::Mechanize->new();
    $mech_handle->env_proxy();
    $mech_handle->timeout(500);
    return $mech_handle;
}

sub htgt_login {
    my $mechanize_obj = shift;

    $mechanize_obj->get( $config->{htgt_login_url} );
    $mechanize_obj->submit_form(
        form_name => 'login_form',
        fields    => { username  => $config->{username}, password => $config->{password}, htgtsession => $config->{session_id}},
        button => 'login'
    );
    return $mechanize_obj;
}

sub find_plate_data {
    my ($mecha, $plate_name) = @_;

    my $res;
    try {
        ## find plate name
        $mecha->submit_form(
            form_name => 'plate_search',
            fields    => { plate_name  => $plate_name}
        );

        ## view as CSV format
        $mecha->follow_link( text => 'Wells' );
        $res = $mecha->content;
    };

    return $res;
}
