package MIP::Test::Fixtures;

use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ basename dirname };
use File::Spec::Functions qw{ catdir catfile };
use FindBin qw{ $Bin };
use File::Temp;
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use Readonly;

## MIPs lib/
use lib catdir( dirname($Bin), q{lib} );
use MIP::Script::Utils qw{ help };

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.01;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK =
      qw{ test_import test_log test_mip_hashes test_standard_cli };
}

## Constants
Readonly my $COMMA   => q{,};
Readonly my $NEWLINE => qq{\n};
Readonly my $SPACE   => q{ };

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
            store       => \$program_name,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    return <<"END_USAGE";
 $program_name [options]
    -vb/--verbose Verbose
    -h/--help     Display this help message
    -v/--version  Display version
END_USAGE
}

sub test_import {

## Function : Test modules and imports
## Returns  :
## Arguments: $perl_module_href => Modules with imports to test

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $perl_module_href;

    my $tmpl = {
        perl_module_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$perl_module_href,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use Test::More;

    ## Modules with import
  PERL_MODULE:
    while ( my ( $module, $module_import ) = each %{$perl_module_href} ) {

        use_ok( $module, @{$module_import} )
          or BAIL_OUT q{Cannot load} . $SPACE . $module;

        require_ok($module) or BAIL_OUT q{Cannot load} . $SPACE . $module;
    }

    return;
}

sub test_log {

## Function : Generate a log object and a temporary log file
## Returns  : $log
## Arguments:

    my ($arg_href) = @_;

    use MIP::Log::MIP_log4perl qw{ initiate_logger };

    ## Create temp logger
    my $test_dir = File::Temp->newdir();
    my $test_log_path = catfile( $test_dir, q{test.log} );

    ## Creates log object
    my $log = initiate_logger(
        {
            file_path => $test_log_path,
            log_name  => q{TEST},
        }
    );

    return $log;
}

sub test_mip_hashes {

## Function : Loads test MIP hashes with core parameters set e.g. active_parameter
## Returns  : MIP core hash
## Arguments: $mip_hash_name  => MIP core hash to return
##          : $program_name   => Program name
##          : $temp_directory => Temporary directory

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $mip_hash_name;
    my $program_name;
    my $temp_directory;

    my $tmpl = {
        mip_hash_name => {
            allow       => [qw{ active_parameter file_info parameter }],
            defined     => 1,
            required    => 1,
            store       => \$mip_hash_name,
            strict_type => 1,
        },
        program_name => {
            default     => q{bwa_mem},
            store       => \$program_name,
            strict_type => 1,
        },
        temp_directory => {
            default     => catfile( File::Temp->newdir() ),
            store       => \$temp_directory,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::File::Format::Yaml qw{ load_yaml };

    my %test_hash = (
        active_parameter =>
          catfile( $Bin, qw{ data test_data recipe_active_parameter.yaml } ),
        file_info =>
          catfile( $Bin, qw{ data test_data recipe_file_info.yaml } ),
        parameter =>
          catfile( $Bin, qw{ data test_data recipe_parameter.yaml } ),
    );

    my %hash_to_return = load_yaml(
        {
            yaml_file => $test_hash{$mip_hash_name},
        }
    );
    ## Add dynamic parameters
    if ( $mip_hash_name eq q{active_parameter} ) {

        ## Adds the program name
        $hash_to_return{$program_name} = 2;

        ## Adds reference dir
        $hash_to_return{reference_dir} =
          catfile( $Bin, qw{ data test_data references } );

        ## Adds parameters with temp directory
        $hash_to_return{outdata_dir} =
          catfile( $temp_directory, q{test_data_dir} );
        $hash_to_return{outscript_dir} =
          catfile( $temp_directory, q{test_script_dir} );
        $hash_to_return{temp_directory} = $temp_directory;
    }
    if ( $mip_hash_name eq q{parameter} ) {

        ## Adds a program chain
        $hash_to_return{$program_name}{chain} = q{TEST};
    }
    return %hash_to_return;
}

sub test_standard_cli {

## Function : Generate standard command line interface for test scripts
## Returns  : $verbose
## Arguments: $verbose => Verbosity of test
##          : $version => Version of test

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $verbose;
    my $version;

    my $tmpl = {
        verbose => {
            default     => 1,
            defined     => 1,
            required    => 1,
            store       => \$verbose,
            strict_type => 1,
        },
        version => {
            default     => 1,
            defined     => 1,
            required    => 1,
            store       => \$version,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use Getopt::Long;

    my $USAGE = build_usage( {} );

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
              . $version
              . $NEWLINE;
            exit;
        },
        q{vb|verbose} => $verbose,
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

    return $verbose;
}

1;
