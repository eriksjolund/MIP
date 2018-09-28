package MIP::Recipes::Analysis::Sv_annotate;

use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
use File::Spec::Functions qw{ catdir catfile devnull splitpath };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ allow check last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use List::MoreUtils qw { any };
use Readonly;

BEGIN {

    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.01;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_sv_annotate };

}

## Constants
Readonly my $ASTERISK    => q{*};
Readonly my $COLON      => q{:};
Readonly my $DASH       => q{-};
Readonly my $DOT        => q{.};
Readonly my $EMPTY_STR  => q{};
Readonly my $NEWLINE    => qq{\n};
Readonly my $PIPE       => q{|};
Readonly my $SPACE      => q{ };
Readonly my $UNDERSCORE => q{_};

sub analysis_sv_annotate {

## Function : CombineVariants to combine all structural variants call from different callers.
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $call_type               => Variant call type
##          : $family_id               => Family id
##          : $file_info_href          => File info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $outaligner_dir          => Outaligner_dir used in the analysis
##          : $parameter_href          => Parameter hash {REF}
##          : $program_name            => Program name
##          : $reference_dir           => MIP reference directory
##          : $sample_info_href        => Info on samples and family hash {REF}
##          : $temp_directory          => Temporary directory {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $file_info_href;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $parameter_href;
    my $program_name;
    my $sample_info_href;

    ## Default(s)
    my $call_type;
    my $family_id;
    my $outaligner_dir;
    my $reference_dir;
    my $temp_directory;

    my $tmpl = {
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
            strict_type => 1,
        },
        call_type =>
          { default => q{SV}, store => \$call_type, strict_type => 1, },
        family_id => {
            default     => $arg_href->{active_parameter_href}{family_id},
            store       => \$family_id,
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
        outaligner_dir => {
            default     => $arg_href->{active_parameter_href}{outaligner_dir},
            store       => \$outaligner_dir,
            strict_type => 1,
        },
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
        program_name => {
            defined     => 1,
            required    => 1,
            store       => \$program_name,
            strict_type => 1,
        },
        sample_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$sample_info_href,
            strict_type => 1,
        },
        reference_dir => {
            default     => $arg_href->{active_parameter_href}{reference_dir},
            store       => \$reference_dir,
            strict_type => 1,
        },
        temp_directory => {
            default     => $arg_href->{active_parameter_href}{temp_directory},
            store       => \$temp_directory,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Get::File qw{ get_file_suffix get_merged_infile_prefix };
    use MIP::Get::Parameter qw{ get_module_parameters get_program_parameters };
    use MIP::Gnu::Coreutils qw(gnu_mv);
    use MIP::IO::Files qw{ migrate_file };
    use MIP::Processmanagement::Slurm_processes
      qw{ slurm_submit_job_sample_id_dependency_add_to_family };
    use MIP::Program::Variantcalling::Bcftools
      qw{ bcftools_view bcftools_annotate bcftools_view_and_index_vcf };
    use MIP::Program::Variantcalling::Genmod
      qw{ genmod_annotate genmod_filter };
    use MIP::Program::Variantcalling::Picardtools qw{ sort_vcf };
    use MIP::Program::Variantcalling::Svdb qw{ svdb_query };
    use MIP::Program::Variantcalling::Vcfanno qw{ vcfanno };
    use MIP::QC::Record qw{ add_program_outfile_to_sample_info };
    use MIP::Script::Setup_script
      qw{ setup_script write_return_to_conda_environment write_source_environment_command };

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger(q{MIP});

    ## Set MIP program mode
    my $program_mode = $active_parameter_href->{$program_name};

    ## Unpack parameters
    my $consensus_analysis_type =
      $parameter_href->{dynamic_parameter}{consensus_analysis_type};
    my $job_id_chain = $parameter_href->{$program_name}{chain};
    my ( $core_number, $time, @source_environment_cmds ) =
      get_module_parameters(
        {
            active_parameter_href => $active_parameter_href,
            program_name          => $program_name,
        }
      );

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE = IO::Handle->new();

    ## Creates program directories (info & programData & programScript), program script filenames and writes sbatch header
    my ( $file_path, $program_info_path ) = setup_script(
        {
            active_parameter_href           => $active_parameter_href,
            call_type                       => $call_type,
            core_number                     => $core_number,
            directory_id                    => $family_id,
            FILEHANDLE                      => $FILEHANDLE,
            job_id_href                     => $job_id_href,
            log                             => $log,
            process_time                    => $time,
            program_directory               => catfile($outaligner_dir),
            program_name                    => $program_name,
            source_environment_commands_ref => \@source_environment_cmds,
            temp_directory                  => $temp_directory,
        }
    );

    ## Split to enable submission to &sample_info_qc later
    my ( $volume, $directory, $stderr_file ) =
      splitpath( $program_info_path . $DOT . q{stderr.txt} );

    ## Assign directories
    my $infamily_directory = catdir( $active_parameter_href->{outdata_dir},
        $family_id, $outaligner_dir );
    my $outfamily_directory = catdir( $active_parameter_href->{outdata_dir},
        $family_id, $outaligner_dir );

    ## Used downstream
    $parameter_href->{$program_name}{indirectory} = $outfamily_directory;

    ## Assign file_tags
    my $infile_tag =
      $file_info_href->{$family_id}{sv_combinevariantcallsets}{file_tag};

    ## Special case for vrn pipeline
    if ( $consensus_analysis_type eq q{vrn} ) {

        $infile_tag =
          $file_info_href->{$family_id}{sv_vcf_rerun_reformat}{file_tag};
    }
    my $outfile_tag =
      $file_info_href->{$family_id}{$program_name}{file_tag};
    my $infile_prefix  = $family_id . $infile_tag . $call_type;
    my $outfile_prefix = $family_id . $outfile_tag . $call_type;

    ## Assign suffix
    my $file_suffix = get_file_suffix(
        {
            jobid_chain    => $job_id_chain,
            parameter_href => $parameter_href,
            suffix_key     => q{variant_file_suffix},
        }
    );

    ## Paths
    my $infile_path_prefix  = catfile( $infamily_directory,  $infile_prefix );
    my $file_path_prefix    = catfile( $temp_directory,      $infile_prefix );
    my $outfile_path_prefix = catfile( $outfamily_directory, $outfile_prefix );
    my $infile_path         = catfile( $infile_path_prefix . $file_suffix ),

      ## Copy file(s) to temporary directory
      say {$FILEHANDLE} q{## Copy file(s) to temporary directory};
    migrate_file(
        {
            FILEHANDLE   => $FILEHANDLE,
            infile_path  => $infile_path . $ASTERISK,
            outfile_path => $temp_directory
        }
    );
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    ## Alternative file tag
    my $alt_file_tag = $EMPTY_STR;

    if ( $active_parameter_href->{sv_svdb_query} ) {

        ## Set for first infile
        my $svdb_infile_path = $file_path_prefix . $file_suffix;

        ## Update alternative ending
        $alt_file_tag .= $UNDERSCORE . q{svdbq};

        ## Ensure correct infile
        my $annotation_file_counter = 0;

        ## Ensure correct outfiles
        my $outfile_tracker = 0;

      QUERIES:
        while ( my ( $query_db_file, $query_db_tag ) =
            each %{ $active_parameter_href->{sv_svdb_query_db_files} } )
        {

            if ($annotation_file_counter) {

                $svdb_infile_path =
                    $file_path_prefix
                  . $alt_file_tag
                  . $file_suffix
                  . $DOT
                  . $outfile_tracker;

                ## Increment now that infile has been set
                $outfile_tracker++;
            }
            svdb_query(
                {
                    bnd_distance    => 25_000,
                    dbfile_path     => $query_db_file,
                    FILEHANDLE      => $FILEHANDLE,
                    frequency_tag   => $query_db_tag . q{AF},
                    hit_tag         => $query_db_tag,
                    infile_path     => $svdb_infile_path,
                    stdoutfile_path => $file_path_prefix
                      . $alt_file_tag
                      . $file_suffix
                      . $DOT
                      . $outfile_tracker,
                    overlap => 0.8,
                }
            );
            say {$FILEHANDLE} $NEWLINE;
            $annotation_file_counter++;
        }

        ## Rename to remove outfile_tracker
        gnu_mv(
            {
                FILEHANDLE  => $FILEHANDLE,
                infile_path => $file_path_prefix
                  . $alt_file_tag
                  . $file_suffix
                  . $DOT
                  . $outfile_tracker,
                outfile_path => $file_path_prefix
                  . $alt_file_tag
                  . $file_suffix,
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }

    ## Alternative file tag
    my $outfile_alt_file_tag = $alt_file_tag . $UNDERSCORE . q{sorted};

    ## Writes sbatch code to supplied filehandle to sort variants in vcf format
    sort_vcf(
        {
            active_parameter_href => $active_parameter_href,
            FILEHANDLE            => $FILEHANDLE,
            infile_paths_ref =>
              [ $file_path_prefix . $alt_file_tag . $file_suffix ],
            outfile => $outfile_path_prefix
              . $outfile_alt_file_tag
              . $file_suffix,
            sequence_dict_file => catfile(
                $reference_dir,
                $file_info_href->{human_genome_reference_name_prefix}
                  . $DOT . q{dict}
            ),
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    $alt_file_tag = $outfile_alt_file_tag;

    ## Remove FILTER ne PASS
    if ( $active_parameter_href->{sv_bcftools_view_filter} ) {

        say {$FILEHANDLE} q{## Remove FILTER ne PASS};
        bcftools_view(
            {
                apply_filters_ref => [qw{ PASS }],
                FILEHANDLE        => $FILEHANDLE,
                infile_path       => $outfile_path_prefix
                  . $alt_file_tag
                  . $file_suffix,
                outfile_path => $outfile_path_prefix
                  . $alt_file_tag
                  . $UNDERSCORE . q{filt}
                  . $file_suffix,
            }
        );
        say {$FILEHANDLE} $NEWLINE;

        ## Update file tag
        $alt_file_tag .= $UNDERSCORE . q{filt};
    }

    ## Remove common variants
    if ( $active_parameter_href->{sv_genmod_filter} ) {

        my @program_source_commands = get_program_parameters(
            {
                active_parameter_href => $active_parameter_href,
                program_name          => q{genmod},
            }
        );

        write_source_environment_command(
            {
                FILEHANDLE                      => $FILEHANDLE,
                source_environment_commands_ref => \@program_source_commands,
            }
        );

        say {$FILEHANDLE} q{## Remove common variants};
        genmod_annotate(
            {
                FILEHANDLE  => $FILEHANDLE,
                infile_path => $outfile_path_prefix
                  . $alt_file_tag
                  . $file_suffix,
                outfile_path => catfile( dirname( devnull() ), q{stdout} ),
                temp_directory_path => $temp_directory,
                thousand_g_file_path =>
                  $active_parameter_href->{sv_genmod_filter_1000g},
                verbosity => q{v},
            }
        );
        print {$FILEHANDLE} $PIPE . $SPACE;

        ## Update file tag
        $alt_file_tag .= $UNDERSCORE . q{genmod_filter};

        genmod_filter(
            {
                FILEHANDLE   => $FILEHANDLE,
                infile_path  => $DASH,
                outfile_path => $outfile_path_prefix
                  . $alt_file_tag
                  . $file_suffix,
                threshold =>
                  $active_parameter_href->{sv_genmod_filter_threshold},
                verbosity => q{v},
            }
        );
        print {$FILEHANDLE} $NEWLINE;

        write_return_to_conda_environment(
            {
                FILEHANDLE => $FILEHANDLE,
                source_main_environment_commands_ref =>
                  \@source_environment_cmds,
            }
        );
        print {$FILEHANDLE} $NEWLINE;
    }

    ## Annotate 1000G structural variants
    if ( $active_parameter_href->{sv_vcfanno} ) {

        say {$FILEHANDLE} q{## Annotate 1000G structural variants};
        vcfanno(
            {
                ends        => 1,
                FILEHANDLE  => $FILEHANDLE,
                infile_path => $outfile_path_prefix
                  . $alt_file_tag
                  . $file_suffix,
                luafile_path => $active_parameter_href->{sv_vcfanno_lua},
                toml_configfile_path =>
                  $active_parameter_href->{sv_vcfanno_config},
            }
        );
        print {$FILEHANDLE} $PIPE . $SPACE;

        ## Remove "[" and "]" from INFO as it breaks vcf format
        print {$FILEHANDLE}
q?perl -nae 'if($_=~/^#/) {print $_} else {$F[7]=~s/\[||\]//g; print join("\t", @F), "\n"}' ?;

        ## Update file tag
        $alt_file_tag .= $UNDERSCORE . q{vcfanno};

        say {$FILEHANDLE} q{>}
          . $SPACE
          . $outfile_path_prefix
          . $alt_file_tag
          . $file_suffix, $NEWLINE;

        if ( $program_mode == 1 ) {

            add_program_outfile_to_sample_info(
                {
                    path             => catfile( $directory, $stderr_file ),
                    program_name     => q{sv_annotate},
                    sample_info_href => $sample_info_href,
                }
            );
        }

        say {$FILEHANDLE}
          q{## Add header for 1000G annotation of structural variants};
        bcftools_annotate(
            {
                FILEHANDLE => $FILEHANDLE,
                headerfile_path =>
                  $active_parameter_href->{sv_vcfannotation_header_lines_file},
                infile_path => $outfile_path_prefix
                  . $alt_file_tag
                  . $file_suffix,
                outfile_path => $outfile_path_prefix
                  . $alt_file_tag
                  . $UNDERSCORE
                  . q{bcftools_annotate}
                  . $file_suffix,
                output_type => q{v},
            }
        );
        say {$FILEHANDLE} $NEWLINE;

        ## Update file tag
        $alt_file_tag .= $UNDERSCORE . q{bcftools_annotate};
    }

    ## Then we have something to rename
    if ( $alt_file_tag ne $EMPTY_STR ) {

        ## Writes sbatch code to supplied filehandle to sort variants in vcf format
        sort_vcf(
            {
                active_parameter_href => $active_parameter_href,
                FILEHANDLE            => $FILEHANDLE,
                infile_paths_ref =>
                  [ $outfile_path_prefix . $alt_file_tag . $file_suffix ],
                outfile            => $outfile_path_prefix . $file_suffix,
                sequence_dict_file => catfile(
                    $reference_dir,
                    $file_info_href->{human_genome_reference_name_prefix}
                      . $DOT . q{dict}
                ),
            }
        );

        say {$FILEHANDLE} $NEWLINE;
    }

    ## Copies file from temporary directory.
    say {$FILEHANDLE} q{## Copy file from temporary directory};
    migrate_file(
        {
            FILEHANDLE   => $FILEHANDLE,
            infile_path  => $outfile_path_prefix . $file_suffix,
            outfile_path => $outfamily_directory,
        }
    );
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    close $FILEHANDLE or $log->logcroak(q{Could not close FILEHANDLE});

    if ( $program_mode == 1 ) {

        my $qc_sv_annotate_outfile =
          $family_id . $outfile_tag . $call_type . $file_suffix;
        add_program_outfile_to_sample_info(
            {
                path =>
                  catfile( $outfamily_directory, $qc_sv_annotate_outfile ),
                program_name     => q{sv_annotate},
                sample_info_href => $sample_info_href,
            }
        );

        slurm_submit_job_sample_id_dependency_add_to_family(
            {
                family_id               => $family_id,
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_href             => $job_id_href,
                log                     => $log,
                path                    => $job_id_chain,
                sample_ids_ref   => \@{ $active_parameter_href->{sample_ids} },
                sbatch_file_name => $file_path,
            }
        );
    }
    return;
}

1;