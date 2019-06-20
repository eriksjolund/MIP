package MIP::Recipes::Analysis::Dragen_dna;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
use File::Spec::Functions qw{ catdir catfile devnull };
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
use MIP::Constants qw{ $COMMA $DOT $NEWLINE $UNDERSCORE };

BEGIN {

    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.00;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_dragen_dna };

}

sub analysis_dragen_dna {

## Function : Rapid dragen dna end-to-end analysis
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => File_info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $profile_base_command    => Submission profile base command
##          : $recipe_name             => Recipe name
##          : $sample_info_href        => Info on samples and case hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $file_info_href;
    my $infile_lane_prefix_href;
    my $job_id_href;
    my $parameter_href;
    my $recipe_name;
    my $sample_info_href;

    ## Default(s)
    my $case_id;
    my $profile_base_command;

    my $tmpl = {
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
            strict_type => 1,
        },
        case_id => {
            default     => $arg_href->{active_parameter_href}{case_id},
            store       => \$case_id,
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
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
        profile_base_command => {
            default     => q{sbatch},
            store       => \$profile_base_command,
            strict_type => 1,
        },
        recipe_name => {
            defined     => 1,
            required    => 1,
            store       => \$recipe_name,
            strict_type => 1,
        },
        sample_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$sample_info_href,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::File::Format::Dragen qw{ create_dragen_fastq_list_sample_id };
    use MIP::File::Format::Pedigree qw{ create_fam_file };
    use MIP::Get::File qw{ get_io_files };
    use MIP::Get::Parameter qw{ get_recipe_attributes get_recipe_resources };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Program::Dragen qw{ dragen_dna_analysis };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::Sample_info
      qw{ get_read_group get_sequence_run_type get_sequence_run_type_is_interleaved set_recipe_outfile_in_sample_info };
    use MIP::Script::Setup_script qw{ setup_script };

    ### PREPROCESSING:

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger( uc q{mip_analyse} );

    my %sample_path;

  SAMPLE_ID:
    foreach my $sample_id ( @{ $active_parameter_href->{sample_ids} } ) {

        ## Unpack parameters
        ## Get the io infiles per chain and id
        my %io = get_io_files(
            {
                id             => $sample_id,
                file_info_href => $file_info_href,
                parameter_href => $parameter_href,
                recipe_name    => $recipe_name,
                stream         => q{in},
            }
        );
        @{ $sample_path{$sample_id}{infile_paths} } = @{ $io{in}{file_paths} };
        @{ $sample_path{$sample_id}{infile_names} } = @{ $io{in}{file_names} };
        @{ $sample_path{$sample_id}{infile_name_prefixes} } =
          @{ $io{in}{file_name_prefixes} };
    }

    my $job_id_chain = get_recipe_attributes(
        {
            attribute      => q{chain},
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
        }
    );
    my $recipe_mode     = $active_parameter_href->{$recipe_name};
    my %recipe_resource = get_recipe_resources(
        {
            active_parameter_href => $active_parameter_href,
            recipe_name           => $recipe_name,
        }
    );

    ## Set and get the io files per chain, id and stream
    my %io = parse_io_outfiles(
        {
            chain_id               => $job_id_chain,
            id                     => $case_id,
            file_info_href         => $file_info_href,
            file_name_prefixes_ref => [$case_id],
            outdata_dir            => $active_parameter_href->{outdata_dir},
            parameter_href         => $parameter_href,
            recipe_name            => $recipe_name,
        }
    );

    my $outdir_path         = $io{out}{dir_path};
    my $outdir_path_prefix  = $io{out}{dir_path_prefix};
    my $outfile_name_prefix = $io{out}{file_name_prefix};
    my @outfile_paths       = @{ $io{out}{file_paths} };
    my $outfile_path_prefix = $io{out}{file_path_prefix};
    my $outfile_suffix      = $io{out}{file_suffix};

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE = IO::Handle->new();

    ## Creates recipe directories (info & data & script), recipe script filenames and writes sbatch header
    my ( $recipe_file_path, $recipe_info_path ) = setup_script(
        {
            active_parameter_href           => $active_parameter_href,
            core_number                     => $recipe_resource{core_number},
            directory_id                    => $case_id,
            FILEHANDLE                      => $FILEHANDLE,
            job_id_href                     => $job_id_href,
            log                             => $log,
            memory_allocation               => $recipe_resource{memory},
            process_time                    => $recipe_resource{time},
            recipe_directory                => $recipe_name,
            recipe_name                     => $recipe_name,
            source_environment_commands_ref => $recipe_resource{load_env_ref},
        }
    );

    ### SHELL:

    say {$FILEHANDLE} q{## } . $recipe_name;

    my $case_file_path = catfile( $outdir_path_prefix, $case_id . $DOT . q{fam} );

    ## Create .fam file to be used in variant calling analyses
    create_fam_file(
        {
            active_parameter_href => $active_parameter_href,
            fam_file_path         => $case_file_path,
            FILEHANDLE            => $FILEHANDLE,
            log                   => $log,
            parameter_href        => $parameter_href,
            sample_info_href      => $sample_info_href,
        }
    );

    ## Get all sample fastq info for dragen as csv file
    my @dragen_fastq_list_lines;
  SAMPLE_ID:
    foreach my $sample_id ( @{ $active_parameter_href->{sample_ids} } ) {

        # Too avoid adjusting infile_index in submitting to jobs
        my $paired_end_tracker = 0;

        my @infile_paths = @{ $sample_path{$sample_id}{infile_paths} };

        ## Perform per single-end or read pair
      INFILE_PREFIX:
        while ( my ( $infile_index, $infile_prefix ) =
            each @{ $infile_lane_prefix_href->{$sample_id} } )
        {

            ## Read group header line
            my %read_group = get_read_group(
                {
                    infile_prefix    => $infile_prefix,
                    platform         => $active_parameter_href->{platform},
                    sample_id        => $sample_id,
                    sample_info_href => $sample_info_href,
                }
            );
            ## Add read groups to line
            my @read_groups = qw{ id sm lb lane };

            push @dragen_fastq_list_lines, join $COMMA, @read_group{@read_groups};

            # Collect paired-end or single-end sequence run type
            my $sequence_run_type = get_sequence_run_type(
                {
                    infile_lane_prefix => $infile_prefix,
                    sample_id          => $sample_id,
                    sample_info_href   => $sample_info_href,
                }
            );

            # Collect interleaved status for fastq file
            my $is_interleaved_fastq = get_sequence_run_type_is_interleaved(
                {
                    infile_lane_prefix => $infile_prefix,
                    sample_id          => $sample_id,
                    sample_info_href   => $sample_info_href,
                }
            );

            ## Infile(s)
            my $fastq_file_path = $infile_paths[$paired_end_tracker];

            ## Add file paths to line
            push @dragen_fastq_list_lines, join $COMMA, $fastq_file_path;

            my $second_fastq_file_path;

            # If second read direction is present
            if ( $sequence_run_type eq q{paired-end} ) {

                # Increment to collect correct read 2
                $paired_end_tracker     = $paired_end_tracker + 1;
                $second_fastq_file_path = $infile_paths[$paired_end_tracker];

                ## Add file paths to line
                push @dragen_fastq_list_lines, join $COMMA, $second_fastq_file_path;
            }
        }
    }

    create_dragen_fastq_list_sample_id(
        {
            fastq_list_lines_ref => \@dragen_fastq_list_lines,
            fastq_list_file_path => $active_parameter_href->{dragen_fastq_list_file_path},
            log                  => $log,
        }
    );

    dragen_dna_analysis(
        {
            alignment_output_format       => q{BAM},
            cnv_enable_self_normalization => 1,
            dbsnp_file_path               => $active_parameter_href->{dragen_dbsnp},
            dragen_hash_ref_dir_path =>
              $active_parameter_href->{dragen_hash_ref_dir_path},
            enable_bam_indexing      => 1,
            enable_cnv               => 1,
            enable_combinegvcfs      => 1,
            enable_duplicate_marking => 1,
            enable_joint_genotyping  => 1,
            enable_map_align         => 1,
            enable_multi_sample_gvcf => 1,
            enable_sort              => 1,
            enable_variant_caller    => 1,
            fastq_list_all_samples   => $active_parameter_href->{fastq_list_all_samples},
            fastq_list_file_path => $active_parameter_href->{dragen_fastq_list_file_path},
            FILEHANDLE           => $FILEHANDLE,
            force                => 1,
            pedigree_file_path   => $case_file_path,
            outdirectory_path    => $outdir_path,
            outfile_prefix       => $outfile_name_prefix,

        }
    );
    ## Close FILEHANDLES
    close $FILEHANDLE or $log->logcroak(q{Could not close FILEHANDLE});

    if ( $recipe_mode == 1 ) {

        ## Collect QC metadata info for later use
        set_recipe_outfile_in_sample_info(
            {
                path             => $outfile_paths[0],
                recipe_name      => $recipe_name,
                sample_info_href => $sample_info_href,
            }
        );

        submit_recipe(
            {
                base_command            => $profile_base_command,
                case_id                 => $case_id,
                dependency_method       => q{sample_to_case},
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_chain            => $job_id_chain,
                job_id_href             => $job_id_href,
                log                     => $log,
                recipe_file_path        => $recipe_file_path,
                sample_ids_ref          => \@{ $active_parameter_href->{sample_ids} },
                submission_profile      => $active_parameter_href->{submission_profile},
            }
        );
    }
    return 1;
}

1;