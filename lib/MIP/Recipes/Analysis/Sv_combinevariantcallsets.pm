package MIP::Recipes::Analysis::Sv_combinevariantcallsets;

use 5.026;
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
    our $VERSION = 1.07;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ analysis_sv_combinevariantcallsets };

}

## Constants
Readonly my $ASTERISK   => q{*};
Readonly my $COLON      => q{:};
Readonly my $DOT        => q{.};
Readonly my $EMPTY_STR  => q{};
Readonly my $NEWLINE    => qq{\n};
Readonly my $UNDERSCORE => q{_};

sub analysis_sv_combinevariantcallsets {

## Function : CombineVariants to combine all structural variants call from different callers
## Returns  :
## Arguments: $active_parameter_href   => Active parameters for this analysis hash {REF}
##          : $case_id                 => Family id
##          : $file_info_href          => File info hash {REF}
##          : $infile_lane_prefix_href => Infile(s) without the ".ending" {REF}
##          : $job_id_href             => Job id hash {REF}
##          : $parameter_href          => Parameter hash {REF}
##          : $recipe_name             => Program name
##          : $reference_dir           => MIP reference directory
##          : $sample_info_href        => Info on samples and case hash {REF}
##          : $temp_directory          => Temporary directory {REF}

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

    use MIP::Get::File qw{ get_io_files };
    use MIP::Get::Parameter qw{ get_recipe_attributes get_recipe_parameters };
    use MIP::IO::Files qw{ migrate_file };
    use MIP::Parse::File qw{ parse_io_outfiles };
    use MIP::Processmanagement::Processes qw{ submit_recipe };
    use MIP::Program::Variantcalling::Bcftools
      qw{ bcftools_merge bcftools_view bcftools_view_and_index_vcf };
    use MIP::Program::Variantcalling::Svdb qw{ svdb_merge };
    use MIP::Program::Variantcalling::Vt qw{ vt_decompose };
    use MIP::QC::Record
      qw{ add_recipe_outfile_to_sample_info add_recipe_metafile_to_sample_info };
    use MIP::Script::Setup_script qw{ setup_script };

    ### PREPROCESSING:

    ## Stores the parallel chains that job ids should be inherited from
    my @parallel_chains;

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger(q{MIP});

    ## Unpack parameters
    my $job_id_chain = get_recipe_attributes(
        {
            parameter_href => $parameter_href,
            recipe_name    => $recipe_name,
            attribute      => q{chain},
        }
    );

    my $recipe_mode = $active_parameter_href->{$recipe_name};
    my @structural_variant_callers;

    ## Only process active callers
    foreach my $structural_variant_caller (
        @{ $parameter_href->{cache}{structural_variant_callers} } )
    {
        if ( $active_parameter_href->{$structural_variant_caller} ) {

            push @structural_variant_callers, $structural_variant_caller;
        }
    }

    my ( $core_number, $time, @source_environment_cmds ) = get_recipe_parameters(
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
            temp_directory         => $temp_directory,
        }
    );

    my $outdir_path_prefix       = $io{out}{dir_path_prefix};
    my $outfile_path_prefix      = $io{out}{file_path_prefix};
    my $outfile_suffix           = $io{out}{file_suffix};
    my $outfile_path             = $outfile_path_prefix . $outfile_suffix;
    my $temp_outfile_path_prefix = $io{temp}{file_path_prefix};
    my $temp_outfile_suffix      = $io{temp}{file_suffix};
    my $temp_outfile_path        = $temp_outfile_path_prefix . $temp_outfile_suffix;

    ## Filehandles
    # Create anonymous filehandle
    my $FILEHANDLE = IO::Handle->new();

    ## Creates recipe directories (info & data & script), recipe script filenames and writes sbatch header
    my ( $recipe_file_path, $recipe_info_path ) = setup_script(
        {
            active_parameter_href           => $active_parameter_href,
            core_number                     => $core_number,
            directory_id                    => $case_id,
            FILEHANDLE                      => $FILEHANDLE,
            job_id_href                     => $job_id_href,
            log                             => $log,
            process_time                    => $time,
            recipe_directory                => $recipe_name,
            recipe_name                     => $recipe_name,
            source_environment_commands_ref => \@source_environment_cmds,
            temp_directory                  => $temp_directory,
        }
    );
    ## Split to enable submission to &sample_info_qc later
    my ( $volume, $directory, $stderr_file ) =
      splitpath( $recipe_info_path . $DOT . q{stderr.txt} );

    ### SHELL:

    ## Collect infiles for all sample_ids for programs that do not do joint calling to enable migration to temporary directory
    # Paths for structural variant callers to be merged
    my %file_path;

    _migrate_and_preprocess_single_callers_file(
        {
            active_parameter_href          => $active_parameter_href,
            FILEHANDLE                     => $FILEHANDLE,
            file_info_href                 => $file_info_href,
            file_path_href                 => \%file_path,
            parallel_chains_ref            => \@parallel_chains,
            parameter_href                 => $parameter_href,
            structural_variant_callers_ref => \@structural_variant_callers,
        }
    );

    ## Merged sample files to one case file (samples > 1) else reformat to standardise
    _merge_or_reformat_single_callers_file(
        {
            active_parameter_href          => $active_parameter_href,
            FILEHANDLE                     => $FILEHANDLE,
            file_path_href                 => \%file_path,
            outfile_suffix                 => $outfile_suffix,
            parameter_href                 => $parameter_href,
            recipe_info_path               => $recipe_info_path,
            structural_variant_callers_ref => \@structural_variant_callers,
        }
    );

    ## Migrate joint calling per case callers like Manta and Delly
    _migrate_joint_callers_file(
        {
            active_parameter_href          => $active_parameter_href,
            FILEHANDLE                     => $FILEHANDLE,
            file_info_href                 => $file_info_href,
            file_path_href                 => \%file_path,
            outfile_suffix                 => $outfile_suffix,
            parallel_chains_ref            => \@parallel_chains,
            parameter_href                 => $parameter_href,
            structural_variant_callers_ref => \@structural_variant_callers,
        }
    );

    ## Merge structural variant caller's case vcf files
    say {$FILEHANDLE} q{## Merge structural variant caller's case vcf files};

    ## Get parameters
    my @svdb_infile_paths;
  STRUCTURAL_CALLER:
    foreach my $structural_variant_caller (@structural_variant_callers) {

        ## Only use first part of name
        my ($variant_caller_prio_tag) = split /_/sxm, $structural_variant_caller;
        push @svdb_infile_paths,
          catfile( $temp_directory,
                $case_id
              . $UNDERSCORE
              . $structural_variant_caller
              . $outfile_suffix
              . $COLON
              . $variant_caller_prio_tag );
    }

    svdb_merge(
        {
            FILEHANDLE       => $FILEHANDLE,
            infile_paths_ref => \@svdb_infile_paths,
            priority         => $active_parameter_href->{sv_svdb_merge_prioritize},
            same_order       => 1,
            stdoutfile_path  => $temp_outfile_path,
        }
    );
    say {$FILEHANDLE} $NEWLINE;

    ## Alternative file tag
    my $alt_file_tag = $EMPTY_STR;

    if ( $active_parameter_href->{sv_vt_decompose} ) {

        ## Update file tag
        $alt_file_tag = $UNDERSCORE . q{vt};

        ## Split multiallelic variants
        say {$FILEHANDLE} q{## Split multiallelic variants};
        vt_decompose(
            {
                FILEHANDLE   => $FILEHANDLE,
                infile_path  => $temp_outfile_path,
                outfile_path => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $outfile_suffix,
                smart_decomposition => 1,
            }
        );
        say {$FILEHANDLE} $NEWLINE;
    }

    if ( $active_parameter_href->{sv_combinevariantcallsets_bcf_file} ) {

        ## Reformat variant calling file and index
        bcftools_view_and_index_vcf(
            {
                FILEHANDLE  => $FILEHANDLE,
                infile_path => $temp_outfile_path_prefix
                  . $alt_file_tag
                  . $outfile_suffix,
                outfile_path_prefix => $outfile_path_prefix,
                output_type         => q{b},
            }
        );
    }

    ## Copies file from temporary directory.
    say {$FILEHANDLE} q{## Copy file from temporary directory};
    migrate_file(
        {
            FILEHANDLE   => $FILEHANDLE,
            infile_path  => $temp_outfile_path_prefix . $alt_file_tag . $outfile_suffix,
            outfile_path => $outfile_path,
        }
    );
    say {$FILEHANDLE} q{wait}, $NEWLINE;

    close $FILEHANDLE or $log->logcroak(q{Could not close FILEHANDLE});

    if ( $recipe_mode == 1 ) {

        add_recipe_outfile_to_sample_info(
            {
                path             => $outfile_path,
                recipe_name      => $recipe_name,
                sample_info_href => $sample_info_href,
            }
        );

        $sample_info_href->{sv_vcf_file}{ready_vcf}{path} = $outfile_path;

        if ( $active_parameter_href->{sv_combinevariantcallsets_bcf_file} ) {

            my $sv_bcf_file_path = $outfile_path_prefix . $DOT . q{bcf};
            add_recipe_metafile_to_sample_info(
                {
                    metafile_tag     => q{sv_bcf_file},
                    path             => $sv_bcf_file_path,
                    recipe_name      => $recipe_name,
                    sample_info_href => $sample_info_href,
                }
            );
        }

        submit_recipe(
            {
                dependency_method       => q{sample_to_case},
                case_id                 => $case_id,
                infile_lane_prefix_href => $infile_lane_prefix_href,
                job_id_href             => $job_id_href,
                log                     => $log,
                job_id_chain            => $job_id_chain,
                parallel_chains_ref     => \@parallel_chains,
                recipe_file_path        => $recipe_file_path,
                sample_ids_ref          => \@{ $active_parameter_href->{sample_ids} },
                submission_profile      => $active_parameter_href->{submission_profile},
            }
        );
    }
    return;
}

sub _add_to_parallel_chain {

## Function : Add to parallel chain
## Returns  :
## Arguments: $parallel_chains_ref             => Store structural variant caller parallel chain
##          : $structural_variant_caller_chain => Chain of structural variant caller

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $parallel_chains_ref;
    my $structural_variant_caller_chain;

    my $tmpl = {
        parallel_chains_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$parallel_chains_ref,
            strict_type => 1,
        },
        structural_variant_caller_chain => {
            defined     => 1,
            required    => 1,
            store       => \$structural_variant_caller_chain,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## If element is not part of array
    if (
        not any {
            $_ eq $structural_variant_caller_chain
        }
        @{$parallel_chains_ref}
      )
    {
        push @{$parallel_chains_ref}, $structural_variant_caller_chain;
    }
    return;
}

sub _migrate_joint_callers_file {

## Function : Migrate joint calling per case callers like Manta and Delly
## Returns  :
## Arguments: $active_parameter_href          => Active parameters for this analysis hash {REF}
##          : $case_id                      => Family id
##          : $FILEHANDLE                     => Filehandle to write to
##          : $file_info_href                 => File info hash {REF
##          : $file_path_href                 => Store file path prefix {REF}
##          : $outfile_suffix                 => Outfile suffix
##          : $parallel_chains_ref            => Store structural variant caller parallel chain
##          : $parameter_href                 => Parameter hash {REF}
##          : $structural_variant_callers_ref => Structural variant callers that do not use joint calling
##          : $temp_directory                 => Temporary directory

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $FILEHANDLE;
    my $case_id;
    my $file_info_href;
    my $file_path_href;
    my $outfile_suffix;
    my $parallel_chains_ref;
    my $parameter_href;
    my $structural_variant_callers_ref;

    ## Default(s)
    my $temp_directory;

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
        FILEHANDLE     => { required => 1, store => \$FILEHANDLE, },
        file_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_info_href,
            strict_type => 1,
        },
        file_path_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_path_href,
            strict_type => 1,
        },
        outfile_suffix => {
            defined     => 1,
            required    => 1,
            store       => \$outfile_suffix,
            strict_type => 1,
        },
        parallel_chains_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$parallel_chains_ref,
            strict_type => 1,
        },
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
        structural_variant_callers_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$structural_variant_callers_ref,
            strict_type => 1,
        },
        temp_directory => {
            default     => $arg_href->{active_parameter_href}{temp_directory},
            store       => \$temp_directory,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Get::File qw{ get_io_files };

    my $joint_caller = q{manta | delly_reformat | tiddit};
    my $stream       = q{out};

  STRUCTURAL_CALLER:
    foreach my $structural_variant_caller ( @{$structural_variant_callers_ref} ) {

        next STRUCTURAL_CALLER
          if ( $structural_variant_caller !~ / $joint_caller /xsm );

        ## Expect vcf. Special case: manta, delly, tiddit are processed by joint calling and per case

        ## Get the io infiles per chain and id
        my %sample_io = get_io_files(
            {
                id             => $case_id,
                file_info_href => $file_info_href,
                parameter_href => $parameter_href,
                recipe_name    => $structural_variant_caller,
                stream         => $stream,
                temp_directory => $temp_directory,
            }
        );
        my $infile_path_prefix = $sample_io{$stream}{file_path_prefix};
        my $infile_suffix      = $sample_io{$stream}{file_suffix};
        my $infile_path =
          $infile_path_prefix . substr( $infile_suffix, 0, 2 ) . $ASTERISK;
        my $temp_infile_path_prefix = $sample_io{temp}{file_path_prefix};
        my $temp_infile_path        = $temp_infile_path_prefix . $infile_suffix;

        _add_to_parallel_chain(
            {
                parallel_chains_ref => $parallel_chains_ref,
                structural_variant_caller_chain =>
                  $parameter_href->{$structural_variant_caller}{chain},
            }
        );

        my $decompose_outfile_path = catfile( $temp_directory,
            $case_id . $UNDERSCORE . $structural_variant_caller . $outfile_suffix );
        ## Store merged outfile per caller
        push @{ $file_path_href->{$structural_variant_caller} }, $decompose_outfile_path;
        if ( $active_parameter_href->{sv_vt_decompose} ) {

            ## Split multiallelic variants
            say {$FILEHANDLE} q{## Split multiallelic variants};
            vt_decompose(
                {
                    FILEHANDLE          => $FILEHANDLE,
                    infile_path         => $infile_path,
                    outfile_path        => $decompose_outfile_path,
                    smart_decomposition => 1,
                }
            );
            say {$FILEHANDLE} $NEWLINE;
        }
    }
    return;
}

sub _migrate_and_preprocess_single_callers_file {

## Function : Collect infiles for all sample_ids for programs that do not do joint calling to enable migration to temporary directory. Add chain of structural variant caller to parallel chains
## Returns  :
## Arguments: $active_parameter_href          => Active parameters for this analysis hash {REF}
##          : $FILEHANDLE                     => Filehandle to write to
##          : $file_info_href                 => File info hash {REF
##          : $file_path_href                 => Store file path prefix {REF}
##          : $parallel_chains_ref            => Store structural variant caller parallel chain
##          : $parameter_href                 => Parameter hash {REF}
##          : $structural_variant_callers_ref => Structural variant callers that do not use joint calling
##          : $temp_directory                 => Temporary directory

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $FILEHANDLE;
    my $file_info_href;
    my $file_path_href;
    my $parallel_chains_ref;
    my $parameter_href;
    my $structural_variant_callers_ref;

    ## Default(s)
    my $temp_directory;

    my $tmpl = {
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
            strict_type => 1,
        },
        FILEHANDLE     => { required => 1, store => \$FILEHANDLE, },
        file_info_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_info_href,
            strict_type => 1,
        },
        file_path_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_path_href,
            strict_type => 1,
        },
        parallel_chains_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$parallel_chains_ref,
            strict_type => 1,
        },
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
        structural_variant_callers_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$structural_variant_callers_ref,
            strict_type => 1,
        },
        temp_directory => {
            default     => $arg_href->{active_parameter_href}{temp_directory},
            store       => \$temp_directory,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Get::File qw{ get_io_files };

    my $joint_caller = q{manta | delly_reformat | tiddit};
    my $stream       = q{out};

  SAMPLE_ID:
    foreach my $sample_id ( @{ $active_parameter_href->{sample_ids} } ) {

      STRUCTURAL_CALLER:
        foreach my $structural_variant_caller ( @{$structural_variant_callers_ref} ) {

            next STRUCTURAL_CALLER
              if ( $structural_variant_caller =~ / $joint_caller /xsm );

            ## Expect vcf. Special case: manta, delly and tiddit are processed by joint calling and per case

            ## Get the io infiles per chain and id
            my %sample_io = get_io_files(
                {
                    id             => $sample_id,
                    file_info_href => $file_info_href,
                    parameter_href => $parameter_href,
                    recipe_name    => $structural_variant_caller,
                    stream         => $stream,
                    temp_directory => $temp_directory,
                }
            );
            my $infile_path_prefix = $sample_io{$stream}{file_path_prefix};
            my $infile_suffix      = $sample_io{$stream}{file_suffix};
            my $infile_path =
              $infile_path_prefix . substr( $infile_suffix, 0, 2 ) . $ASTERISK;
            my $temp_infile_path_prefix = $sample_io{temp}{file_path_prefix};
            my $temp_infile_path        = $temp_infile_path_prefix . $infile_suffix;

            push @{ $file_path_href->{$structural_variant_caller} },
              $temp_infile_path . $DOT . q{gz};

            _add_to_parallel_chain(
                {
                    parallel_chains_ref => $parallel_chains_ref,
                    structural_variant_caller_chain =>
                      $parameter_href->{$structural_variant_caller}{chain},
                }
            );

            ## Copy file(s) to temporary directory
            say {$FILEHANDLE} q{## Copy file(s) to temporary directory};
            migrate_file(
                {
                    FILEHANDLE   => $FILEHANDLE,
                    infile_path  => $infile_path,
                    outfile_path => $temp_directory
                }
            );

            say {$FILEHANDLE} q{wait}, $NEWLINE;

            ## Reformat variant calling file and index
            bcftools_view_and_index_vcf(
                {
                    infile_path         => $temp_infile_path,
                    outfile_path_prefix => $temp_infile_path_prefix,
                    output_type         => q{z},
                    FILEHANDLE          => $FILEHANDLE,
                }
            );
        }
    }
    return;
}

sub _merge_or_reformat_single_callers_file {

## Function : Merged sample files to one case file (samples > 1) else reformat to standardise
## Returns  :
## Arguments: $active_parameter_href          => Active parameters for this analysis hash {REF}
##          : $case_id                      => Family ID
##          : $FILEHANDLE                     => Filehandle to write to
##          : $file_path_href                 => Store file path prefix {REF}
##          : $outfile_suffix                 => Outfile suffix
##          : $parameter_href                 => Parameter hash {REF}
##          : $recipe_info_path              => Program info path
##          : $structural_variant_callers_ref => Structural variant callers that do not use joint calling
##          : $temp_directory                 => Temporary directory

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $FILEHANDLE;
    my $file_path_href;
    my $outfile_suffix;
    my $parameter_href;
    my $recipe_info_path;
    my $structural_variant_callers_ref;

    ## Default(s)
    my $case_id;
    my $temp_directory;

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
        FILEHANDLE     => { required => 1, store => \$FILEHANDLE, },
        file_path_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$file_path_href,
            strict_type => 1,
        },
        outfile_suffix => {
            defined     => 1,
            required    => 1,
            store       => \$outfile_suffix,
            strict_type => 1,
        },
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
        recipe_info_path => {
            defined     => 1,
            required    => 1,
            store       => \$recipe_info_path,
            strict_type => 1,
        },
        structural_variant_callers_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$structural_variant_callers_ref,
            strict_type => 1,
        },
        temp_directory => {
            default     => $arg_href->{active_parameter_href}{temp_directory},
            store       => \$temp_directory,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    my $joint_caller = q{manta | delly_reformat | tiddit};

  STRUCTURAL_CALLER:
    foreach my $structural_variant_caller ( @{$structural_variant_callers_ref} ) {

        next STRUCTURAL_CALLER
          if ( $structural_variant_caller =~ / $joint_caller /xsm );

        ## Expect vcf. Special case: joint calling and per case

        ## Assemble file paths by adding file ending
        my @merge_infile_paths = @{ $file_path_href->{$structural_variant_caller} };
        my $merge_outfile_path = catfile( $temp_directory,
            $case_id . $UNDERSCORE . $structural_variant_caller . $outfile_suffix );
        ## Store merged outfile per caller
        push @{ $file_path_href->{$structural_variant_caller} }, $merge_outfile_path;

        if ( scalar @{ $active_parameter_href->{sample_ids} } > 1 ) {

            ## Merge all structural variant caller's vcf files per sample_id
            say {$FILEHANDLE}
              q{## Merge all structural variant caller's vcf files per sample_id};

            bcftools_merge(
                {
                    FILEHANDLE       => $FILEHANDLE,
                    infile_paths_ref => \@merge_infile_paths,
                    outfile_path     => $merge_outfile_path,
                    output_type      => q{v},
                    stderrfile_path  => $recipe_info_path
                      . $UNDERSCORE
                      . $structural_variant_caller
                      . $UNDERSCORE
                      . q{merge.stderr.txt},
                }
            );
            say {$FILEHANDLE} $NEWLINE;
        }
        else {

            ## Reformat all structural variant caller's vcf files per sample_id
            say {$FILEHANDLE}
              q{## Reformat all structural variant caller's vcf files per sample_id};

            bcftools_view(
                {
                    FILEHANDLE      => $FILEHANDLE,
                    infile_path     => $merge_infile_paths[0],    # Can be only one
                    outfile_path    => $merge_outfile_path,
                    output_type     => q{v},
                    stderrfile_path => $recipe_info_path
                      . $UNDERSCORE
                      . $structural_variant_caller
                      . $UNDERSCORE
                      . q{merge.stderr.txt},
                }
            );
            say {$FILEHANDLE} $NEWLINE;
        }
    }
    return;
}

1;
