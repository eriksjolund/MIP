package MIP::Recipes::Install::Mip_scripts;

use Carp;
use charnames qw{ :full :short };
use Cwd;
use English qw{ -no_match_vars };
use File::Spec::Functions qw{ catdir catfile };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ check allow last_error };
use strict;
use utf8;
use warnings qw{ FATAL utf8 };
use warnings;

## Cpanm
use Readonly;

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.06;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ install_mip_scripts };
}

## Constants
Readonly my $DOT        => q{.};
Readonly my $NEWLINE    => qq{\n};
Readonly my $SPACE      => q{ };
Readonly my $UNDERSCORE => q{_};

sub install_mip_scripts {

## Function : Install mip_scripts
## Returns  :
##          : $conda_environment       => Conda environment
##          : $conda_prefix_path       => Conda prefix path
##          : $FILEHANDLE              => Filehandle to write to
##          : $noupdate                => Do not update
##          : $program_parameters_href => Hash with mip_scripts specific parameters {REF}
##          : $quiet                   => Be quiet
##          : $verbose                 => Set verbosity

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $conda_environment;
    my $conda_prefix_path;
    my $FILEHANDLE;
    my $mip_scripts_parameters_href;
    my $noupdate;
    my $quiet;
    my $verbose;

    my $tmpl = {
        conda_environment => {
            store       => \$conda_environment,
            strict_type => 1,
        },
        conda_prefix_path => {
            defined     => 1,
            required    => 1,
            store       => \$conda_prefix_path,
            strict_type => 1,
        },
        FILEHANDLE => {
            defined  => 1,
            required => 1,
            store    => \$FILEHANDLE,
        },
        noupdate => {
            store       => \$noupdate,
            strict_type => 1,
        },
        program_parameters_href => {
            default     => {},
            required    => 1,
            store       => \$mip_scripts_parameters_href,
            strict_type => 1,
        },
        quiet => {
            allow       => [ undef, 0, 1 ],
            store       => \$quiet,
            strict_type => 1,
        },
        verbose => {
            allow       => [ undef, 0, 1 ],
            store       => \$verbose,
            strict_type => 1,
        },

    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Modules
    use File::Basename qw{ fileparse };
    use FindBin qw{ $Bin };
    use MIP::Gnu::Coreutils qw{ gnu_chmod gnu_cp gnu_ln gnu_mkdir};
    use MIP::Log::MIP_log4perl qw{ retrieve_log };

    ## Unpack parameters
    my $mip_scripts_version = $mip_scripts_parameters_href->{version};

    ## Retrieve logger object
    my $log = retrieve_log(
        {
            log_name => q{mip_install::install_mip_scripts},
            quiet    => $quiet,
            verbose  => $verbose,
        }
    );

    ## Store original working directory
    my $pwd = cwd();

    ## Define MIP scripts and yaml files
    my @mip_scripts = qw{ mip vcfparser.pl qccollect.pl };

    my %mip_sub_script = (
        utility_scripts =>
          [qw{ calculate_af.pl covplots_exome.R covplots_genome.R max_af.pl }],
        t => [
            qw{ mip_install.test mip_analyse_rare_disease.test mip_core.t mip_analysis.test }
        ],
        templates => [qw{ mip_config.yaml }],
    );

    my @mip_directories = qw{ lib t definitions };

    say {$FILEHANDLE} q{### Install MIP};

    ## Check if installation exists and is executable
    # mip is proxy for all mip scripts
    if ( -x catfile( $conda_prefix_path, qw{ bin mip } ) ) {
        $log->info(
            q{MIP is already installed in the specified conda environment.});
        if ($noupdate) {
            say {$FILEHANDLE}
              q{## MIP is already installed, skippping installation};
            say {$FILEHANDLE} $NEWLINE;
            return;
        }
        $log->warn(q{This will overwrite the current installation of MIP});
    }

    $log->info(q{Writing installation instructions for MIP});

    ## Create directories
    say {$FILEHANDLE} q{## Create directories};
  DIRECTORY:
    foreach my $directory ( keys %mip_sub_script ) {

        my $indirectory_path = catdir( $conda_prefix_path, q{bin}, $directory );
        gnu_mkdir(
            {
                FILEHANDLE       => $FILEHANDLE,
                indirectory_path => $indirectory_path,
                parents          => 1,
            }
        );
        print {$FILEHANDLE} $NEWLINE;
    }
    print {$FILEHANDLE} $NEWLINE;

    ## Copy directory to conda env
    say {$FILEHANDLE} q{## Copy directory to conda env};
  DIRECTORY:
    foreach my $directory (@mip_directories) {

        gnu_cp(
            {
                FILEHANDLE   => $FILEHANDLE,
                force        => 1,
                infile_path  => catdir( $Bin, $directory ),
                outfile_path => catdir( $conda_prefix_path, q{bin} ),
                recursive    => 1,
            }
        );
        print {$FILEHANDLE} $NEWLINE;
    }
    print {$FILEHANDLE} $NEWLINE;

    ## Copy mip scripts and sub scripts to conda env and make executable
    say {$FILEHANDLE}
q{## Copy mip scripts and subdirectory scripts to conda env and make executable};

  SCRIPT:
    foreach my $script (@mip_scripts) {

        my $script_no_ending = fileparse( $script, qr/\.[^.]*/xms );
        gnu_cp(
            {
                FILEHANDLE  => $FILEHANDLE,
                infile_path => catfile( $Bin, $script ),
                outfile_path =>
                  catdir( $conda_prefix_path, q{bin}, $script_no_ending ),
            }
        );
        print {$FILEHANDLE} $NEWLINE;

        my $file_path =
          catfile( $conda_prefix_path, q{bin}, $script_no_ending );
        gnu_chmod(
            {
                file_path  => $file_path,
                FILEHANDLE => $FILEHANDLE,
                permission => q{a+x},
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }

  DIRECTORY:
    foreach my $directory ( keys %mip_sub_script ) {

      SCRIPT:
        foreach my $script ( @{ $mip_sub_script{$directory} } ) {

            gnu_cp(
                {
                    FILEHANDLE  => $FILEHANDLE,
                    infile_path => catfile( $Bin, $directory, $script ),
                    outfile_path =>
                      catdir( $conda_prefix_path, q{bin}, $directory ),
                }
            );
            print {$FILEHANDLE} $NEWLINE;

            my $file_path =
              catfile( $conda_prefix_path, q{bin}, $directory, $script );
            gnu_chmod(
                {
                    FILEHANDLE => $FILEHANDLE,
                    file_path  => $file_path,
                    permission => q{a+x},
                }
            );
            say {$FILEHANDLE} $NEWLINE;
        }
    }
    print {$FILEHANDLE} $NEWLINE;

    return;
}

1;
