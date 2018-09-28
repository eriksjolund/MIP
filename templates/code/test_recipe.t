#!/usr/bin/env perl

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
use File::Spec::Functions qw{ catdir catfile };
use FindBin qw{ $Bin };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
use Test::More;
use utf8;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw { :all };
use Modern::Perl qw{ 2014 };
use Readonly;
use Test::Trap;

## MIPs lib/
use lib catdir( dirname($Bin), q{lib} );
use MIP::Test::Fixtures qw{ test_log test_mip_hashes test_standard_cli };

my $VERBOSE = 1;
our $VERSION = 1.00;

$VERBOSE = test_standard_cli(
    {
        verbose => $VERBOSE,
        version => $VERSION,
    }
);

## Constants
Readonly my $COLON => q{:};
Readonly my $COMMA => q{,};
Readonly my $SPACE => q{ };

BEGIN {

    use MIP::Test::Fixtures qw{ test_import };

### Check all internal dependency modules and imports
## Modules with import
    my %perl_module = (
        q{MIP::PATH::TO::MODULE} => [qw{ SUB_ROUTINE }],
        q{MIP::Test::Fixtures} =>
          [qw{ test_log test_mip_hashes test_standard_cli }],
    );

    test_import( { perl_module_href => \%perl_module, } );
}

use MIP::PATH::TO::MODULE qw{ SUB_ROUTINE };

diag(   q{Test SUB_ROUTINE from MODULE.pm v}
      . $MIP::PATH::TO::MODULE::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

my $log = test_log();

## Given build parameters
my $program_name = q{PROGRAM_NAME};

my %active_parameter = test_mip_hashes(
    {
        mip_hash_name => q{active_parameter},
        program_name  => $program_name,
    }
);
my %file_info = test_mip_hashes(
    {
        mip_hash_name => q{file_info},
        program_name  => $program_name,
    }
);
my %infile_lane_prefix;
my %job_id;
my %parameter = test_mip_hashes( { mip_hash_name => q{parameter}, } );

my %sample_info;

trap {
    SUB_ROUTINE(
        {
            active_parameter_href   => \%active_parameter,
            file_info_href          => \%file_info,
            infile_lane_prefix_href => \%infile_lane_prefix,
            job_id_href             => \%job_id,
            log                     => $log,
            parameter_href          => \%parameter,
            program_name            => $program_name,
            sample_id               => $sample_id,
            sample_info_href        => \%sample_info,
        }
      )
};

## Then broadcast info log message
my $log_msg = q{};
like( $trap->stderr, qr/$log_msg/msx, q{Broadcast PROGRAM_NAME log message} );

done_testing();