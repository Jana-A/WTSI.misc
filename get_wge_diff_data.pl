#!/usr/bin/env perl

=head1 DESCRIPTION

This script reads from a compressed CSV file and the WGE database to save any differences between the 2 based on the crisprs_human table.

=cut

use strict;
use warnings;

use IO::Zlib;
use Text::CSV;
use Getopt::Long;
use WGE::Model::DB;

## command-line arguments - the path of the .csv.gz file
my ($input_file, $output_file);
GetOptions(
    'input_file=s'  => \$input_file,
    'output_file=s' => \$output_file
);

## connect to WGE db and get crispr IDs with no off_target_summary
my @db_crispr_ids;

my $model = WGE::Model::DB->new( user => 'wge_admin' );
my @db_trans = $model->schema->resultset('CrisprsHuman')->search( { off_target_summary => { '=', undef } }, { columns => [ qw/id/ ] } )->all;

foreach my $rec (@db_trans) {
    push @db_crispr_ids, $rec->id;
}

## opening handles
my $rfh = new IO::Zlib;
$rfh->open($input_file, "rb");
my $csv = Text::CSV->new();

my @final_data;
my @header;
my $count = 0;

## loop every line in the .csv.gz file (except the header)
while (my $row = <$rfh>) {
    chomp $row;

    my $row_data;
    if ($count == 0) {
        @header = split ",", $row;
        $count++;
        next;
    }

    ## read line as a CSV
    my $status = $csv->parse($row);
    my @fields =  $csv->fields();

    $row_data->{$header[$_]} = $fields[$_] foreach (0..$#header);
    $count++;
    my $res = $row_data->{off_target_summary};

    ## evaluate the off_target_summary string into a ref hash
    $res =~ s/:/ =>/g;
    my $h = eval $res;

    ## compare CSV line to DB record and save new modifications
    if (keys %$h and grep { $_ == $res->id } @db_crispr_ids ) {
        push @final_data, $row;
    }
}

$rfh->close;

## save output in .csv.gz file
my $wfh = new IO::Zlib;
$wfh->open($output_file, "wb");
print $wfh join "\n", @final_data;
$wfh->close;
