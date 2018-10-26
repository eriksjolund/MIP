#!/usr/bin/env perl

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ basename dirname  };
use File::Spec::Functions qw{ catdir catfile };
use FindBin qw{ $Bin };
use Getopt::Long;
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
use Test::More;
use utf8;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use Modern::Perl qw{ 2014 };
use Readonly;

## MIPs lib/
use lib catdir( dirname($Bin), q{lib} );
use MIP::Script::Utils qw{ help };

our $USAGE = build_usage( {} );

my $VERBOSE = 1;
our $VERSION = 1.0.0;

## Constants
Readonly my $COMMA   => q{,};
Readonly my $NEWLINE => qq{\n};
Readonly my $SPACE   => q{ };

### User Options
GetOptions(

    # Display help text
    q{h|help} => sub {
        done_testing();
        say {*STDOUT} $USAGE;
        exit;
    },

    # Display version number
    q{v|version} => sub {
        done_testing();
        say {*STDOUT} $NEWLINE
          . basename($PROGRAM_NAME)
          . $SPACE
          . $VERSION
          . $NEWLINE;
        exit;
    },
    q{vb|verbose} => $VERBOSE,
  )
  or (
    done_testing(),
    help(
        {
            USAGE     => $USAGE,
            exit_code => 1,
        }
    )
  );

BEGIN {

### Check all internal dependency modules and imports
## Modules with import
    my %perl_module = ( q{MIP::Script::Utils} => [qw{ help }], );

  PERL_MODULE:
    while ( my ( $module, $module_import ) = each %perl_module ) {
        use_ok( $module, @{$module_import} )
          or BAIL_OUT q{Cannot load} . $SPACE . $module;
    }

## Modules
    my @modules = (q{MIP::Program::Variantcalling::Svdb});

  MODULE:
    for my $module (@modules) {
        require_ok($module) or BAIL_OUT q{Cannot load} . $SPACE . $module;
    }
}

use MIP::Program::Variantcalling::Svdb qw{ svdb_query };
use MIP::Test::Commands qw{ test_function };

diag(   q{Test svdb_query from Svdb.pm v}
      . $MIP::Program::Variantcalling::Svdb::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Constants
Readonly my $BND_DISTANCE  => 10_000;
Readonly my $EVENT_OVERLAP => 0.6;

## Base arguments
my @function_base_commands = qw{ svdb --query };

my %base_argument = (
    FILEHANDLE => {
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
    dbfile_path => {
        input           => catfile(qw{ a test databasefile }),
        expected_output => q{--db}
          . $SPACE
          . catfile(qw{ a test databasefile }),
    },
    infile_path => {
        input           => catfile(qw{ a test infile }),
        expected_output => q{--query_vcf}
          . $SPACE
          . catfile(qw{ a test infile }),
    },
);

my %specific_argument = (
    bnd_distance => {
        input           => $BND_DISTANCE,
        expected_output => q{--bnd_distance} . $SPACE . $BND_DISTANCE,
    },
    dbfile_path => {
        input           => catfile(qw{ a test databasefile }),
        expected_output => q{--db}
          . $SPACE
          . catfile(qw{ a test databasefile }),
    },
    frequency_tag => {
        input           => q{FRQ},
        expected_output => q{--frequency_tag} . $SPACE . q{FRQ},
    },
    hit_tag => {
        input           => q{OCC},
        expected_output => q{--hit_tag} . $SPACE . q{OCC},
    },
    infile_path => {
        input           => catfile(qw{ a test infile }),
        expected_output => q{--query_vcf}
          . $SPACE
          . catfile(qw{ a test infile }),
    },
    overlap => {
        input           => $EVENT_OVERLAP,
        expected_output => q{--overlap} . $SPACE . $EVENT_OVERLAP,
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&svdb_query;

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

######################
####SubRoutines#######
######################

sub build_usage {

## Function  : Build the USAGE instructions
## Returns   :
## Arguments : $program_name => Name of the script

    my ($arg_href) = @_;

    ## Default(s)
    my $program_name;

    my $tmpl = {
        program_name => {
            default     => basename($PROGRAM_NAME),
            strict_type => 1,
            store       => \$program_name,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    return <<"END_USAGE";
 $program_name [options]
    -vb/--verbose Verbose
    -h/--help Display this help message
    -v/--version Display version
END_USAGE
}
