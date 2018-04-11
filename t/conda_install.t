#!/usr/bin/env perl

use Modern::Perl qw{2014};
use warnings qw{FATAL utf8};
use autodie;
use 5.018;    #Require at least perl 5.18
use utf8;
use open qw{ :encoding(UTF-8) :std };
use charnames qw{ :full :short };
use Carp;
use English qw{-no_match_vars};
use Params::Check qw{check allow last_error};

use FindBin qw{$Bin};    #Find directory of script
use File::Basename qw{dirname basename};
use File::Spec::Functions qw{catdir};
use Getopt::Long;
use Test::More;
use Readonly;

## MIPs lib/
use lib catdir( dirname($Bin), 'lib' );
use MIP::Script::Utils qw{help};

our $USAGE = build_usage( {} );

my $VERBOSE = 1;
our $VERSION = '1.0.3';

## Constants
Readonly my $SPACE   => q{ };
Readonly my $NEWLINE => qq{\n};

###User Options
GetOptions(
    q{h|help} => sub {
        done_testing();
        say {*STDOUT} $USAGE;
        exit;
    },    #Display help text
    q{v|version} => sub {
        done_testing();
        say {*STDOUT} $NEWLINE, basename($PROGRAM_NAME),
          $SPACE, $VERSION, $NEWLINE;
        exit;
    },    #Display version number
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
##Modules with import
    my %perl_module;

    $perl_module{'MIP::Script::Utils'} = [qw{help}];

  PERL_MODULES:
    while ( my ( $module, $module_import ) = each %perl_module ) {
        use_ok( $module, @{$module_import} )
          or BAIL_OUT q{Cannot load } . $module;
    }

##Modules
    my @modules = (q{MIP::Package_manager::Conda});

  MODULES:
    for my $module (@modules) {
        require_ok($module) or BAIL_OUT q{Cannot load } . $module;
    }
}

use MIP::Package_manager::Conda qw{conda_install};
use MIP::Test::Commands qw{test_function};

diag(   q{Test conda_install from Conda.pm v}
      . $MIP::Package_manager::Conda::VERSION
      . q{, Perl }
      . $PERL_VERSION
      . $SPACE
      . $EXECUTABLE_NAME );

## Base arguments
my $function_base_command = q{conda install};

my %base_argument = (
    FILEHANDLE => {
        input           => undef,
        expected_output => $function_base_command,
    },
);

## Can be duplicated with %base and/or %specific to enable testing of each individual argument
my %required_argument = (
    packages_ref => {
        inputs_ref      => [qw{ test_package_1=1.2.3 test_package_2=1.2 }],
        expected_output => q{test_package_1=1.2.3 test_package_2=1.2},
    },
    FILEHANDLE => {
        input           => undef,
        expected_output => $function_base_command,
    },
);

my %specific_argument = (
    conda_channels_ref => {
        inputs_ref      => [qw{ conda-forge bioconda }],
        expected_output => q{--channel bioconda --channel conda-forge},
    },
    env_name => {
        input           => q{test_env},
        expected_output => q{--name test_env},
    },
    no_confirmation => {
        input           => 1,
        expected_output => q{--yes},
    },
    packages_ref => {
        inputs_ref      => [qw{ test_package_1 test_package_2}],
        expected_output => q{test_package_1 test_package_2},
    },
    quiet => {
        input           => 1,
        expected_output => q{--quiet},
    },
);

## Coderef - enables generalized use of generate call
my $module_function_cref = \&conda_install;

## Test both base and function specific arguments
my @arguments = ( \%base_argument, \%specific_argument );

foreach my $argument_href (@arguments) {
    my @commands = test_function(
        {
            argument_href          => $argument_href,
            required_argument_href => \%required_argument,
            module_function_cref   => $module_function_cref,
            function_base_command  => $function_base_command,
            do_test_base_command   => 1,
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

    check( $tmpl, $arg_href, 1 ) or croak qw(Could not parse arguments!);

    return <<"END_USAGE";
 $program_name [options]
    -vb/--verbose Verbose
    -h/--help Display this help message
    -v/--version Display version
END_USAGE
}
