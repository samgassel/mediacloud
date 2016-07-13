#!/usr/bin/env perl
#
# (Re-)aggregate Bit.ly stats for stories that have their Bit.ly stats fetched but not yet aggregated
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Util::Bitly;
use MediaWords::CM;
use MediaWords::Job::Bitly::AggregateStoryStats;

use Getopt::Long;
use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Readonly my $usage => <<EOF;
Usage: $0 --controversy < controversy id or pattern >
EOF

    my ( $controversy_opt );
    Getopt::Long::GetOptions( 'controversy=s' => \$controversy_opt, ) or die $usage;

    die $usage unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db;

    unless ( MediaWords::Util::Bitly::bitly_processing_is_enabled() )
    {
        die "Bit.ly processing is not enabled.";
    }

    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );

    for my $controversy ( @{ $controversies } )
    {
        my $controversies_id = $controversy->{ controversies_id };

        if ( MediaWords::Util::Bitly::num_controversy_stories_without_bitly_statistics( $db, $controversies_id ) == 0 )
        {
            say STDERR "All controversy's $controversies_id stories are processed against Bit.ly, skipping.";
            next;
        }

        my $stories_to_add = $db->query(
            <<EOF,
            SELECT stories_id
            FROM controversy_stories
            WHERE controversies_id = ?
              AND stories_id NOT IN (
                SELECT stories_id
                FROM bitly_clicks_total
            )
            ORDER BY stories_id
EOF
            $controversies_id
        )->hashes;

        foreach my $story ( @{ $stories_to_add } )
        {
            my $stories_id = $story->{ stories_id };

            unless ( MediaWords::Util::Bitly::story_stats_are_fetched( $db, $stories_id ) )
            {
                say STDERR "Story $stories_id has not been fetched yet.";
                next;
            }

            say STDERR "Addin story $stories_id...";
            MediaWords::Job::Bitly::AggregateStoryStats->add_to_queue( { stories_id => $stories_id } );
        }
    }
}

main();