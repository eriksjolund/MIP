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
use autodie qw{ :all };
use Modern::Perl qw{ 2018 };
use Readonly;

## MIPs lib/
use lib catdir( dirname($Bin), q{lib} );
use MIP::Constants qw{ $COMMA $SPACE };
use MIP::Test::Commands qw{ test_function };
use MIP::Test::Fixtures qw{ test_standard_cli };

my $VERBOSE = 1;
our $VERSION = 1.01;

$VERBOSE = test_standard_cli(
    {
        verbose => $VERBOSE,
        version => $VERSION,
    }
);

BEGIN {

    use MIP::Test::Fixtures qw{ test_import };

### Check all internal dependency modules and imports
## Modules with import
    my %perl_module = (
        q{MIP::Program::Rhocall} => [qw{ rhocall_annotate }],
        q{MIP::Test::Fixtures}   => [qw{ test_standard_cli }],
    );

    test_import( { perl_module_href => \%perl_module, } );
}

use MIP::Program::Rhocall qw{ rhocall_annotate };

diag(   q{Test rhocall_annotate from Rhocall.pm v}
      . $MIP::Program::Rhocall::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Base arguments
my @function_base_commands = qw{ rhocall annotate };

my %base_argument = (
    filehandle => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
    stderrfile_path => {
        input           => q{stderrfile.test},
        expected_output => q{2> stderrfile.test},
    },
    stderrfile_path_append => {
        input           => q{stderrfile.test},
        expected_output => q{2>> stderrfile.test},
    },
    stdoutfile_path => {
        input           => q{stdoutfile.test},
        expected_output => q{1> stdoutfile.test},
    },
);

## Can be duplicated with %base_argument and/or %specific_argument
## to enable testing of each individual argument
my %required_argument = (
    infile_path => {
        input           => catfile(qw{ file_path_prefix_contig infile_suffix }),
        expected_output => catfile(qw{ file_path_prefix_contig infile_suffix }),
    },
);

my %specific_argument = (
    bedfile_path => {
        input           => catfile(qw{ path_to_bedfile file.bed }),
        expected_output => q{-b} . $SPACE . catfile(qw{ path_to_bedfile file.bed }),
    },
    outfile_path => {
        input           => catfile(qw{ outfile_path_prefix_contig infile_suffix }),
        expected_output => q{--output}
          . $SPACE
          . catfile(qw{ outfile_path_prefix_contig infile_suffix }),
    },
    rohfile_path => {
        input           => catfile(qw{ file_path_prefix _contig.roh }),
        expected_output => q{-r} . $SPACE . catfile(qw{ file_path_prefix _contig.roh }),
    },
    v14 => {
        input           => 1,
        expected_output => q{--v14} . $SPACE,
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&rhocall_annotate;

## Test both base and function specific arguments
my @arguments = ( \%base_argument, \%specific_argument );

ARGUMENT_HASH_REF:
foreach my $argument_href (@arguments) {
    my @commands = test_function(
        {
            argument_href              => $argument_href,
            required_argument_href     => \%required_argument,
            module_function_cref       => $module_function_cref,
            function_base_commands_ref => \@function_base_commands,
            do_test_base_command       => 1,
        }
    );
}
done_testing();
