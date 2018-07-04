package MIP::Recipes::Build::Rare_disease;

use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use Readonly;

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.00;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ build_rare_disease_meta_files };
}

## Constants
Readonly my $SPACE     => q{ };
Readonly my $EMPTY_STR => q{};
Readonly my $TAB       => qq{\t};

sub build_rare_disease_meta_files {

## Function : Pipeline recipe for wgs data analysis.
## Returns  :

## Arguments: $parameter_href          => Parameter hash {REF}
##          : $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $sample_info_href        => Info on samples and family hash {REF}
##          : $file_info_href          => File info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $log                     => Log object to write to

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $parameter_href;
    my $active_parameter_href;
    my $sample_info_href;
    my $file_info_href;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $log;

    my $tmpl = {
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
            strict_type => 1,
        },
        sample_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$sample_info_href,
            strict_type => 1,
        },
        file_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_info_href,
            strict_type => 1,
        },
        infile_lane_prefix_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$infile_lane_prefix_href,
            strict_type => 1,
        },
        job_id_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$job_id_href,
            strict_type => 1,
        },
        log => {
            defined  => 1,
            required => 1,
            store    => \$log,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Check::Reference qw{ check_bwa_prerequisites
      check_capture_file_prerequisites
      check_human_genome_prerequisites
      check_parameter_metafiles
      check_references_for_vt
      check_rtg_prerequisites };
    use MIP::Recipes::Analysis::Vt_core qw{ analysis_vt_core };

## Check capture file prerequistes exists
  PROGRAM:
    foreach my $program_name (
        @{ $parameter_href->{exome_target_bed}{associated_program} } )
    {

        next PROGRAM if ( not $active_parameter_href->{$program_name} );

        ## Remove initial "p" from program_name
        substr $program_name, 0, 1, $EMPTY_STR;

        check_capture_file_prerequisites(
            {
                parameter_href          => $parameter_href,
                active_parameter_href   => $active_parameter_href,
                sample_info_href        => $sample_info_href,
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_href             => $job_id_href,
                infile_list_suffix => $file_info_href->{exome_target_bed}[0],
                padded_infile_list_suffix =>
                  $file_info_href->{exome_target_bed}[1],
                padded_interval_list_suffix =>
                  $file_info_href->{exome_target_bed}[2],
                program_name => $program_name,
                log          => $log,
            }
        );
    }

## Check human genome prerequistes exists
  PROGRAM:
    foreach my $program_name (
        @{ $parameter_href->{human_genome_reference}{associated_program} } )
    {

        next PROGRAM if ( $program_name eq q{mip} );

        next PROGRAM if ( not $active_parameter_href->{$program_name} );

        ## Remove initial "p" from program_name
        substr $program_name, 0, 1, $EMPTY_STR;

        my $is_finished = check_human_genome_prerequisites(
            {
                parameter_href          => $parameter_href,
                active_parameter_href   => $active_parameter_href,
                sample_info_href        => $sample_info_href,
                file_info_href          => $file_info_href,
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_href             => $job_id_href,
                program_name            => $program_name,
                log                     => $log,
            }
        );
        last PROGRAM if ($is_finished);
    }

## Check Rtg build prerequisites

    if ( $active_parameter_href->{rtg_vcfeval} ) {

        check_rtg_prerequisites(
            {
                parameter_href          => $parameter_href,
                active_parameter_href   => $active_parameter_href,
                sample_info_href        => $sample_info_href,
                file_info_href          => $file_info_href,
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_href             => $job_id_href,
                program_name            => q{rtg_vcfeval},
                parameter_build_name    => q{rtg_vcfeval_reference_genome},
            }
        );
    }

## Check BWA build prerequisites

    if ( $active_parameter_href->{bwa_mem} ) {

        check_bwa_prerequisites(
            {
                parameter_href          => $parameter_href,
                active_parameter_href   => $active_parameter_href,
                sample_info_href        => $sample_info_href,
                file_info_href          => $file_info_href,
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_href             => $job_id_href,
                program_name            => q{bwa_mem},
                parameter_build_name    => q{bwa_build_reference},
            }
        );
    }
    $log->info( $TAB . q{Reference check: Reference prerequisites checked} );

## Check if vt has processed references, if not try to reprocesses them before launcing modules
    $log->info(q{[Reference check - Reference processed by VT]});
    if (   $active_parameter_href->{vt_decompose}
        || $active_parameter_href->{vt_normalize} )
    {

        my @to_process_references = check_references_for_vt(
            {
                parameter_href        => $parameter_href,
                active_parameter_href => $active_parameter_href,
                vt_references_ref =>
                  \@{ $active_parameter_href->{decompose_normalize_references}
                  },
                log => $log,
            }
        );

      REFERENCE:
        foreach my $reference_file_path (@to_process_references) {

            $log->info(q{[VT - Normalize and decompose]});
            $log->info( $TAB . q{File: } . $reference_file_path );

            ## Split multi allelic records into single records and normalize
            analysis_vt_core(
                {
                    parameter_href          => $parameter_href,
                    active_parameter_href   => $active_parameter_href,
                    infile_lane_prefix_href => $infile_lane_prefix_href,
                    job_id_href             => $job_id_href,
                    infile_path             => $reference_file_path,
                    program_directory       => q{vt},
                    decompose               => 1,
                    normalize               => 1,
                }
            );
        }
    }
    return;
}

1;