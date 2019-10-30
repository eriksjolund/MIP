#!/usr/bin/env perl

use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname basename };
use File::Spec::Functions qw{ catfile catdir };
use FindBin qw{ $Bin };
use Getopt::Long;
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ check allow last_error };
use Test::More;
use utf8;
use warnings qw{ FATAL utf8 };
use 5.026;

## CPANM
use Modern::Perl qw{ 2018 };
use autodie;
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
        say {*STDOUT} $NEWLINE . basename($PROGRAM_NAME) . $SPACE . $VERSION . $NEWLINE;
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
    my @modules = (q{MIP::Program::Variantcalling::Bcftools});

  MODULE:
    for my $module (@modules) {
        require_ok($module) or BAIL_OUT q{Cannot load} . $SPACE . $module;
    }
}

use MIP::Program::Variantcalling::Bcftools qw{ bcftools_mpileup };
use MIP::Test::Commands qw{ test_function };

diag(   q{Test bcftools_mpileup from Variantcalling::Bcftools.pm v}
      . $MIP::Program::Variantcalling::Bcftools::VERSION
      . $COMMA
      . $SPACE . q{Perl}
      . $SPACE
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Constants
Readonly my $ADJUST_MAPPING_QUALITY => 45;

## Base arguments
my @function_base_commands = qw{ bcftools };

my %base_argument = (
    filehandle => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
);

## Can be duplicated with %base and/or %specific to enable testing of each individual argument
my %required_argument = (
    stdoutfile_path => {
        input           => q{stdoutfile.test},
        expected_output => q{1> stdoutfile.test},
    },
    stderrfile_path => {
        input           => q{stderrfile.test},
        expected_output => q{2> stderrfile.test},
    },
    stderrfile_path_append => {
        input           => q{stderrfile.test},
        expected_output => q{2>> stderrfile.test},
    },
    filehandle => {
        input           => undef,
        expected_output => \@function_base_commands,
    },
    infile_paths_ref => {
        inputs_ref      => [ catfile(qw{dir file_1}), catfile(qw{dir file_2}) ],
        expected_output => catfile(qw{dir file_1}) . $SPACE . catfile(qw{dir file_2}),
    },
    output_tags_ref => {
        inputs_ref      => [qw{tag1 tag3 etc}],
        expected_output => q{--annotate tag1,tag2,etc},
    },
    referencefile_path => {
        input           => catfile(qw{ dir genome.fasta}),
        expected_output => q{--fasta-ref} . $SPACE . catfile(qw{ dir genome.fasta}),
    },
);

## Specific arguments
my %specific_argument = (
    outfile_path => {
        input           => catfile(qw{dir outfile_1}),
        expected_output => q{--output} . $SPACE . catfile(qw{dir outfile_1}),
    },
    per_sample_increased_sensitivity => {
        input           => 1,
        expected_output => q{--per-sample-mF},
    },
    adjust_mq => {
        input           => $ADJUST_MAPPING_QUALITY,
        expected_output => q{--adjust-MQ} . $SPACE . $ADJUST_MAPPING_QUALITY,
    },
    stderrfile_path_append => {
        input           => q{stderrfile_path_append},
        expected_output => q{2>> stderrfile_path_append},
    },
);
## Coderef - enables generalized use of generate call
my $module_function_cref = \&bcftools_mpileup;

## Test both base and function specific arguments
my @arguments = ( \%base_argument, \%specific_argument );

foreach my $argument_href (@arguments) {

    my @commands = test_function(
        {
            argument_href              => $argument_href,
            required_argument_href     => \%required_argument,
            module_function_cref       => $module_function_cref,
            function_base_commands_ref => \@function_base_commands,
        }
    );
}

done_testing();

######################
####SubRoutines#######
######################

sub build_usage {

##build_usage

##Function : Build the USAGE instructions
##Returns  : ""
##Arguments: $program_name
##         : $program_name => Name of the script

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

    check( $tmpl, $arg_href, 1 ) or croak qw{Could not parse arguments!};

    return <<"END_USAGE";
 $program_name [options]
    -vb/--verbose Verbose
    -h/--help Display this help message
    -v/--version Display version
END_USAGE
}
