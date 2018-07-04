package MIP::Main::Analyse;

#### Master script for analysing paired end reads from the Illumina plattform in fastq(.gz) format to annotated ranked disease causing variants. The program performs QC, aligns reads using BWA, performs variant discovery and annotation as well as ranking the found variants according to disease potential.

#### Copyright 2011 Henrik Stranneheim

use 5.018;
use Carp;
use charnames qw{ :full :short };
use Cwd;
use Cwd qw{ abs_path };
use English qw{ -no_match_vars };
use File::Basename qw{ basename dirname fileparse };
use File::Copy qw{ copy };
use File::Spec::Functions qw{ catdir catfile devnull };
use FindBin qw{ $Bin };
use Getopt::Long;
use IPC::Cmd qw{ can_run run};
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ check allow last_error };
use POSIX;
use Time::Piece;
use utf8;
use warnings qw{ FATAL utf8 };

## Third party module(s)
use autodie qw{ open close :all };
use IPC::System::Simple;
use List::MoreUtils qw { any uniq all };
use Modern::Perl qw{ 2014 };
use Path::Iterator::Rule;
use Readonly;

## MIPs lib/
# Add MIPs internal lib
use MIP::Check::Cluster qw{ check_max_core_number };
use MIP::Check::Modules qw{ check_perl_modules };
use MIP::Check::Parameter qw{ check_allowed_temp_directory
  check_aligner
  check_cmd_config_vs_definition_file
  check_email_address
  check_parameter_hash
  check_program_exists_in_hash
  check_program_mode
  check_sample_ids
  check_sample_id_in_hash_parameter
  check_sample_id_in_hash_parameter_path
  check_snpsift_keys
  check_vep_directories
};
use MIP::Check::Path
  qw{ check_command_in_path check_parameter_files check_target_bed_file_suffix check_vcfanno_toml };
use MIP::Check::Reference
  qw{ check_human_genome_file_endings check_parameter_metafiles };
use MIP::File::Format::Config qw{ write_mip_config };
use MIP::File::Format::Mip qw{ build_file_prefix_tag };
use MIP::File::Format::Pedigree
  qw{ create_fam_file detect_founders detect_sample_id_gender detect_trio parse_yaml_pedigree_file reload_previous_pedigree_info };
use MIP::File::Format::Yaml qw{ load_yaml write_yaml order_parameter_names };
use MIP::Get::Analysis qw{ get_overall_analysis_type };
use MIP::Get::File qw{ get_select_file_contigs };
use MIP::Log::MIP_log4perl qw{ initiate_logger set_default_log4perl_file };
use MIP::Parse::File qw{ parse_fastq_infiles };
use MIP::Parse::Parameter
  qw{ parse_infiles parse_prioritize_variant_callers parse_start_with_program };
use MIP::Script::Utils qw{ help };
use MIP::Set::Contigs qw{ set_contigs };
use MIP::Set::Parameter
  qw{ set_config_to_active_parameters set_custom_default_to_active_parameter set_default_config_dynamic_parameters set_default_to_active_parameter set_dynamic_parameter set_human_genome_reference_features set_parameter_reference_dir_path set_parameter_to_broadcast };
use MIP::Update::Contigs
  qw{ size_sort_select_file_contigs update_contigs_for_run };
use MIP::Update::Parameters
  qw{ update_dynamic_config_parameters update_exome_target_bed update_reference_parameters update_vcfparser_outfile_counter };
use MIP::Update::Path qw{ update_to_absolute_path };
use MIP::Update::Programs
  qw{ update_prioritize_flag update_program_mode_for_analysis_type update_program_mode_with_dry_run_all };
use MIP::QC::Record qw{ add_to_sample_info };

## Recipes
use MIP::Recipes::Analysis::Gzip_fastq qw{ analysis_gzip_fastq };
use MIP::Recipes::Analysis::Split_fastq_file qw{ analysis_split_fastq_file };
use MIP::Recipes::Pipeline::Rare_disease qw{ pipeline_rare_disease };
use MIP::Recipes::Pipeline::Rna qw{ pipeline_rna };
use MIP::Recipes::Pipeline::Cancer qw{ pipeline_cancer };

BEGIN {

    use base qw{ Exporter };
    require Exporter;

    # Set the version for version checking
    our $VERSION = 1.06;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ mip_analyse };
}

## Constants
Readonly my $DOT          => q{.};
Readonly my $EMPTY_STR    => q{};
Readonly my $NEWLINE      => qq{\n};
Readonly my $SINGLE_QUOTE => q{'};
Readonly my $SPACE        => q{ };
Readonly my $TAB          => qq{\t};

sub mip_analyse {

## Function : Execute mip analyse pre pipeline parsing
## Returns  :
## Arguments: $active_parameter_href => Active parameters for this analysis hash {REF}
##          : $file_info_href        => File info hash {REF}
#           : $order_parameters_ref  => Order of addition to parameter array {REF}
##          : $order_programs_ref    => Order of programs {REF}
##          : $parameter_href        => Parameter hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $file_info_href;
    my $order_parameters_ref;
    my $order_programs_ref;
    my $parameter_href;

    my $tmpl = {
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
            strict_type => 1,
        },
        file_info_href => {
            required    => 1,
            defined     => 1,
            default     => {},
            strict_type => 1,
            store       => \$file_info_href,
        },
        order_parameters_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$order_parameters_ref,
            strict_type => 1,
        },
        order_programs_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$order_programs_ref,
            strict_type => 1,
        },
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Transfer to lexical variables
    my %active_parameter = %{$active_parameter_href};
    my %file_info        = %{$file_info_href};
    my @order_parameters = @{$order_parameters_ref};
    my @order_programs   = @{$order_programs_ref};
    my %parameter        = %{$parameter_href};

#### Script parameters

## Add date_time_stamp for later use in log and qc_metrics yaml file
    my $date_time       = localtime;
    my $date_time_stamp = $date_time->datetime;
    my $date            = $date_time->ymd;

    # Catches script name and removes ending
    my $script = fileparse( basename( $PROGRAM_NAME, $DOT . q{pl} ) );
    chomp( $date_time_stamp, $date, $script );

#### Set program parameters

## Set MIP version
    our $VERSION = 'v7.0.1';

    if ( $active_parameter{version} ) {

        say {*STDOUT} $NEWLINE . basename($PROGRAM_NAME) . $SPACE . $VERSION,
          $NEWLINE;
        exit;
    }

## Directories, files, job_ids and sample_info
    my ( %infile, %indir_path, %infile_lane_prefix, %lane,
        %infile_both_strands_prefix, %job_id, %sample_info );

#### Staging Area
### Get and/or set input parameters

## Special case for boolean flag that will be removed from
## config upon loading
    my @boolean_parameter = qw{dry_run_all};
    foreach my $parameter (@boolean_parameter) {

        if ( not defined $active_parameter{$parameter} ) {

            delete $active_parameter{$parameter};
        }
    }

## Change relative path to absolute path for parameter with "update_path: absolute_path" in config
    update_to_absolute_path(
        {
            active_parameter_href => \%active_parameter,
            parameter_href        => \%parameter,
        }
    );

### Config file
## If config from cmd
    if ( exists $active_parameter{config_file}
        && defined $active_parameter{config_file} )
    {

        ## Loads a YAML file into an arbitrary hash and returns it.
        my %config_parameter =
          load_yaml( { yaml_file => $active_parameter{config_file}, } );

        ## Remove previous analysis specific info not relevant for current run e.g. log file, which is read from pedigree or cmd
        my @remove_keys = (qw{ log_file dry_run_all });

      KEY:
        foreach my $key (@remove_keys) {

            delete $config_parameter{$key};
        }

## Set config parameters into %active_parameter unless $parameter
## has been supplied on the command line
        set_config_to_active_parameters(
            {
                active_parameter_href => \%active_parameter,
                config_parameter_href => \%config_parameter,
            }
        );

        ## Compare keys from config and cmd (%active_parameter) with definitions file (%parameter)
        check_cmd_config_vs_definition_file(
            {
                active_parameter_href => \%active_parameter,
                parameter_href        => \%parameter,
            }
        );

        my @config_dynamic_parameters =
          qw{ analysis_constant_path outaligner_dir };

        ## Replace config parameter with cmd info for config dynamic parameter
        set_default_config_dynamic_parameters(
            {
                active_parameter_href => \%active_parameter,
                parameter_href        => \%parameter,
                parameter_names_ref   => \@config_dynamic_parameters,
            }
        );

        ## Loop through all parameters and update info
      PARAMETER:
        foreach my $parameter_name ( keys %parameter ) {

            ## Updates the active parameters to particular user/cluster for dynamic config parameters following specifications. Leaves other entries untouched.
            update_dynamic_config_parameters(
                {
                    active_parameter_href => \%active_parameter,
                    parameter_name        => $parameter_name,
                }
            );
        }
    }

## Set the default Log4perl file using supplied dynamic parameters.
    $active_parameter{log_file} = set_default_log4perl_file(
        {
            active_parameter_href => \%active_parameter,
            cmd_input             => $active_parameter{log_file},
            date                  => $date,
            date_time_stamp       => $date_time_stamp,
            script                => $script,
        }
    );

## Creates log object
    my $log = initiate_logger(
        {
            file_path => $active_parameter{log_file},
            log_name  => q{MIP},
        }
    );

## Write MIP VERSION and log file path
    $log->info( q{MIP Version: } . $VERSION );
    $log->info( q{Script parameters and info from are saved in file: }
          . $active_parameter{log_file} );

## Parse pedigree file
## Reads family_id_pedigree file in YAML format. Checks for pedigree data for allowed entries and correct format. Add data to sample_info depending on user info.
    # Meta data in YAML format
    if ( defined $active_parameter{pedigree_file} ) {

        ## Loads a YAML file into an arbitrary hash and returns it. Load parameters from previous run from sample_info_file
        my %pedigree =
          load_yaml( { yaml_file => $active_parameter{pedigree_file}, } );

        $log->info( q{Loaded: } . $active_parameter{pedigree_file} );

        parse_yaml_pedigree_file(
            {
                active_parameter_href => \%active_parameter,
                file_path             => $active_parameter{pedigree_file},
                parameter_href        => \%parameter,
                pedigree_href         => \%pedigree,
                sample_info_href      => \%sample_info,
            }
        );
    }

# Detect if all samples has the same sequencing type and return consensus if reached
    $parameter{dynamic_parameter}{consensus_analysis_type} =
      get_overall_analysis_type(
        { analysis_type_href => \%{ $active_parameter{analysis_type} }, } );

### Populate uninitilized active_parameters{parameter_name} with default from parameter
  PARAMETER:
    foreach my $parameter_name ( keys %parameter ) {

        ## If hash and set - skip
        next PARAMETER
          if ( ref $active_parameter{$parameter_name} eq qw{HASH}
            && keys %{ $active_parameter{$parameter_name} } );

        ## If array and set - skip
        next PARAMETER
          if ( ref $active_parameter{$parameter_name} eq qw{ARRAY}
            && @{ $active_parameter{$parameter_name} } );

        ## If scalar and set - skip
        next PARAMETER
          if ( defined $active_parameter{$parameter_name}
            and not ref $active_parameter{$parameter_name} );

        ### Special case for parameters that are dependent on other parameters values
        my @custom_default_parameters = qw{
          analysis_type
          bwa_build_reference
          exome_target_bed
          expansionhunter_repeat_specs_dir
          gatk_path
          infile_dirs
          picardtools_path
          sample_info_file
          snpeff_path
          rtg_vcfeval_reference_genome
          vep_directory_path
        };

        if ( any { $_ eq $parameter_name } @custom_default_parameters ) {

            set_custom_default_to_active_parameter(
                {
                    active_parameter_href => \%active_parameter,
                    parameter_href        => \%parameter,
                    parameter_name        => $parameter_name,
                }
            );
            next PARAMETER;
        }

        ## Checks and sets user input or default values to active_parameters
        set_default_to_active_parameter(
            {
                active_parameter_href => \%active_parameter,
                associated_programs_ref =>
                  \@{ $parameter{$parameter_name}{associated_program} },
                log            => $log,
                parameter_href => \%parameter,
                parameter_name => $parameter_name,
            }
        );
    }

## Update path for supplied reference(s) associated with parameter that should reside in the mip reference directory to full path
    set_parameter_reference_dir_path(
        {
            active_parameter_href => \%active_parameter,
            parameter_name        => q{human_genome_reference},
        }
    );

## Detect version and source of the human_genome_reference: Source (hg19 or GRCh).
    set_human_genome_reference_features(
        {
            file_info_href => \%file_info,
            human_genome_reference =>
              basename( $active_parameter{human_genome_reference} ),
            log => $log,
        }
    );

## Update exome_target_bed files with human_genome_reference_source and human_genome_reference_version
    update_exome_target_bed(
        {
            exome_target_bed_file_href => $active_parameter{exome_target_bed},
            human_genome_reference_source =>
              $file_info{human_genome_reference_source},
            human_genome_reference_version =>
              $file_info{human_genome_reference_version},
        }
    );

    # Holds all active parameters values for broadcasting
    my @broadcasts;

    if ( $active_parameter{verbose} ) {

        set_parameter_to_broadcast(
            {
                parameter_href        => \%parameter,
                active_parameter_href => \%active_parameter,
                order_parameters_ref  => \@order_parameters,
                broadcasts_ref        => \@broadcasts,
            }
        );
    }

## Reference in MIP reference directory
  PARAMETER:
    foreach my $parameter_name ( keys %parameter ) {

        ## Expect file to be in reference directory
        if ( exists $parameter{$parameter_name}{reference} ) {

            update_reference_parameters(
                {
                    active_parameter_href => \%active_parameter,
                    associated_programs_ref =>
                      \@{ $parameter{$parameter_name}{associated_program} },
                    parameter_name => $parameter_name,
                }
            );
        }
    }

### Checks

## Check existence of files and directories
  PARAMETER:
    foreach my $parameter_name ( keys %parameter ) {

        if ( exists $parameter{$parameter_name}{exists_check} ) {

            check_parameter_files(
                {
                    active_parameter_href => \%active_parameter,
                    associated_programs_ref =>
                      \@{ $parameter{$parameter_name}{associated_program} },
                    log => $log,
                    parameter_exists_check =>
                      $parameter{$parameter_name}{exists_check},
                    parameter_href => \%parameter,
                    parameter_name => $parameter_name,
                }
            );
        }
    }

## Updates sample_info hash with previous run pedigree info
    reload_previous_pedigree_info(
        {
            log                   => $log,
            sample_info_href      => \%sample_info,
            sample_info_file_path => $active_parameter{sample_info_file},
        }
    );

## Special case since dict is created with .fastq removed
## Check the existance of associated human genome files
    check_human_genome_file_endings(
        {
            active_parameter_href => \%active_parameter,
            file_info_href        => \%file_info,
            log                   => $log,
            parameter_href        => \%parameter,
            parameter_name        => q{human_genome_reference},
        }
    );

## Check that supplied target file ends with ".bed" and otherwise croaks
  TARGET_FILE:
    foreach
      my $target_bed_file ( keys %{ $active_parameter{exome_target_bed} } )
    {

        check_target_bed_file_suffix(
            {
                log            => $log,
                parameter_name => q{exome_target_bed},
                path           => $target_bed_file,
            }
        );
    }

## Checks parameter metafile exists and set build_file parameter
    check_parameter_metafiles(
        {
            parameter_href        => \%parameter,
            active_parameter_href => \%active_parameter,
            file_info_href        => \%file_info,
        }
    );

## Update the expected number of outfile after vcfparser
    update_vcfparser_outfile_counter(
        { active_parameter_href => \%active_parameter, } );

## Collect select file contigs to loop over downstream
    if ( $active_parameter{vcfparser_select_file} ) {

## Collects sequences contigs used in select file
        @{ $file_info{select_file_contigs} } = get_select_file_contigs(
            {
                select_file_path =>
                  catfile( $active_parameter{vcfparser_select_file} ),
                log => $log,
            }
        );
    }

## Detect family constellation based on pedigree file
    $parameter{dynamic_parameter}{trio} = detect_trio(
        {
            active_parameter_href => \%active_parameter,
            log                   => $log,
            sample_info_href      => \%sample_info,
        }
    );

## Detect number of founders (i.e. parents ) based on pedigree file
    detect_founders(
        {
            active_parameter_href => \%active_parameter,
            sample_info_href      => \%sample_info,
        }
    );

## Check email adress syntax and mail host
    if ( defined $active_parameter{email} ) {

        check_email_address(
            {
                email => $active_parameter{email},
                log   => $log,
            }
        );
    }

## Check that the temp directory value is allowed
    check_allowed_temp_directory(
        {
            log            => $log,
            temp_directory => $active_parameter{temp_directory},
        }
    );

## Parameters that have keys as MIP program names
    my @parameter_keys_to_check =
      (qw{ module_time module_core_number module_source_environment_command });
  PARAMETER_NAME:
    foreach my $parameter_name (@parameter_keys_to_check) {

        ## Test if key from query hash exists truth hash
        check_program_exists_in_hash(
            {
                log            => $log,
                parameter_name => $parameter_name,
                query_ref      => \%{ $active_parameter{$parameter_name} },
                truth_href     => \%parameter,
            }
        );
    }

## Parameters with key(s) that have elements as MIP program names
    my @parameter_element_to_check = qw(associated_program);
  PARAMETER:
    foreach my $parameter ( keys %parameter ) {

      KEY:
        foreach my $parameter_name (@parameter_element_to_check) {

            next KEY if ( not exists $parameter{$parameter}{$parameter_name} );

            ## Test if element from query array exists truth hash
            check_program_exists_in_hash(
                {
                    log            => $log,
                    parameter_name => $parameter_name,
                    query_ref  => \@{ $parameter{$parameter}{$parameter_name} },
                    truth_href => \%parameter,
                }
            );
        }
    }

## Parameters that have elements as MIP program names
    my @parameter_elements_to_check =
      (qw(associated_program decompose_normalize_references));
    foreach my $parameter_name (@parameter_elements_to_check) {

        ## Test if element from query array exists truth hash
        check_program_exists_in_hash(
            {
                log            => $log,
                parameter_name => $parameter_name,
                query_ref      => \@{ $active_parameter{$parameter_name} },
                truth_href     => \%parameter,
            }
        );
    }

## Check that the module core number do not exceed the maximum per node
    foreach my $program_name ( keys %{ $active_parameter{module_core_number} } )
    {

        ## Limit number of cores requested to the maximum number of cores available per node
        $active_parameter{module_core_number}{$program_name} =
          check_max_core_number(
            {
                max_cores_per_node => $active_parameter{max_cores_per_node},
                core_number_requested =>
                  $active_parameter{module_core_number}{$program_name},
            }
          );
    }

## Check programs in path, and executable
    check_command_in_path(
        {
            active_parameter_href => \%active_parameter,
            log                   => $log,
            parameter_href        => \%parameter,
        }
    );

## Test that the family_id and the sample_id(s) exists and are unique. Check if id sample_id contains "_".
    check_sample_ids(
        {
            family_id      => $active_parameter{family_id},
            log            => $log,
            sample_ids_ref => \@{ $active_parameter{sample_ids} },
        }
    );

## Check sample_id provided in hash parameter is included in the analysis and only represented once
    check_sample_id_in_hash_parameter(
        {
            active_parameter_href => \%active_parameter,
            log                   => $log,
            parameter_names_ref =>
              [qw{ analysis_type expected_coverage sample_origin }],
            parameter_href => \%parameter,
            sample_ids_ref => \@{ $active_parameter{sample_ids} },
        }
    );

## Check sample_id provided in hash path parameter is included in the analysis and only represented once
    check_sample_id_in_hash_parameter_path(
        {
            active_parameter_href => \%active_parameter,
            log                   => $log,
            parameter_names_ref   => [qw{ infile_dirs exome_target_bed }],
            sample_ids_ref        => \@{ $active_parameter{sample_ids} },
        }
    );

## Check that VEP directory and VEP cache match
    if ( exists $active_parameter{varianteffectpredictor} ) {
        check_vep_directories(
            {
                log                 => $log,
                vep_directory_cache => $active_parameter{vep_directory_cache},
                vep_directory_path  => $active_parameter{vep_directory_path},
            }
        );
    }

## Check that the supplied vcfanno toml frequency file match record 'file=' within toml config file
    if (    exists $active_parameter{sv_combinevariantcallsets}
        and $active_parameter{sv_combinevariantcallsets} > 0
        and $active_parameter{sv_vcfanno} > 0 )
    {

        check_vcfanno_toml(
            {
                log               => $log,
                vcfanno_file_freq => $active_parameter{sv_vcfanno_config_file},
                vcfanno_file_toml => $active_parameter{sv_vcfanno_config},
            }
        );
    }

    check_snpsift_keys(
        {
            log => $log,
            snpsift_annotation_files_href =>
              \%{ $active_parameter{snpsift_annotation_files} },
            snpsift_annotation_outinfo_key_href =>
              \%{ $active_parameter{snpsift_annotation_outinfo_key} },
        }
    );

## Adds dynamic aggregate information from definitions to parameter hash
    set_dynamic_parameter(
        {
            aggregates_ref => [
                ## Collects all programs that MIP can handle
                q{type:program},
                ## Collects all variant_callers
                q{program_type:variant_callers},
                ## Collects all structural variant_callers
                q{program_type:structural_variant_callers},
                ## Collect all aligners
                q{program_type:aligners},
                ## Collects all references in that are supposed to be in reference directory
                q{reference:reference_dir},
            ],
            parameter_href => \%parameter,
        }
    );

## Check correct value for program mode in MIP
    check_program_mode(
        {
            active_parameter_href => \%active_parameter,
            log                   => $log,
            parameter_href        => \%parameter,
        }
    );

    my $consensus_analysis_type =
      $parameter{dynamic_parameter}{consensus_analysis_type};

## Get initiation program, downstream dependencies and update program modes for start_with_program parameter depending on pipeline
    my $initiation_file =
      catfile( $Bin, qw{ definitions rare_disease_initiation_map.yaml } );

    # For RNA pipeline
    if ( $consensus_analysis_type eq q{wts} ) {

        $initiation_file =
          catfile( $Bin, qw{ definitions rna_initiation_map.yaml } );
    }
    parse_start_with_program(
        {
            active_parameter_href => \%active_parameter,
            initiation_file       => $initiation_file,
            parameter_href        => \%parameter,
        },
    );

## Update program mode depending on dry_run_all flag
    update_program_mode_with_dry_run_all(
        {
            active_parameter_href => \%active_parameter,
            dry_run_all           => $active_parameter{dry_run_all},
            programs_ref => \@{ $parameter{dynamic_parameter}{program} },
        }
    );

## Check that the correct number of aligners is used in MIP and sets the aligner flag accordingly
    check_aligner(
        {
            active_parameter_href => \%active_parameter,
            broadcasts_ref        => \@broadcasts,
            log                   => $log,
            parameter_href        => \%parameter,
            verbose               => $active_parameter{verbose},
        }
    );

## Check that all active variant callers have a prioritization order and that the prioritization elements match a supported variant caller
    parse_prioritize_variant_callers(
        {
            active_parameter_href => \%active_parameter,
            log                   => $log,
            parameter_href        => \%parameter,
        }
    );

## Broadcast set parameters info
    foreach my $parameter_info (@broadcasts) {

        $log->info($parameter_info);
    }

## Update program mode depending on analysis run value as some programs are not applicable for e.g. wes
    update_program_mode_for_analysis_type(
        {
            active_parameter_href => \%active_parameter,
            consensus_analysis_type =>
              $parameter{dynamic_parameter}{consensus_analysis_type},
            log          => $log,
            programs_ref => [
                qw{ cnvnator delly_call delly_reformat expansionhunter tiddit samtools_subsample_mt }
            ],
        }
    );

## Update prioritize flag depending on analysis run value as some programs are not applicable for e.g. wes
    $active_parameter{sv_svdb_merge_prioritize} = update_prioritize_flag(
        {
            consensus_analysis_type =>
              $parameter{dynamic_parameter}{consensus_analysis_type},
            prioritize_key => $active_parameter{sv_svdb_merge_prioritize},
            programs_ref   => [qw{ cnvnator delly_call delly_reformat tiddit }],
        }
    );

## Write config file for family
    write_mip_config(
        {
            active_parameter_href => \%active_parameter,
            log                   => $log,
            remove_keys_ref       => [qw{ associated_program }],
            sample_info_href      => \%sample_info,
        }
    );

## Detect the gender(s) included in current analysis
    (

        $active_parameter{found_male},
        $active_parameter{found_female},
        $active_parameter{found_other},
        $active_parameter{found_other_count},
      )
      = detect_sample_id_gender(
        {
            active_parameter_href => \%active_parameter,
            sample_info_href      => \%sample_info,
        }
      );

### Contigs
## Set contig prefix and contig names depending on reference used
    set_contigs(
        {
            file_info_href         => \%file_info,
            human_genome_reference => $active_parameter{human_genome_reference},
        }
    );

## Update contigs depending on settings in run (wes or if only male samples)
    update_contigs_for_run(
        {
            analysis_type_href  => \%{ $active_parameter{analysis_type} },
            exclude_contigs_ref => \@{ $active_parameter{exclude_contigs} },
            file_info_href      => \%file_info,
            found_male          => $active_parameter{found_male},
        }
    );

## Sorts array depending on reference array. NOTE: Only entries present in reference array will survive in sorted array.
    @{ $file_info{sorted_select_file_contigs} } = size_sort_select_file_contigs(
        {
            consensus_analysis_type =>
              $parameter{dynamic_parameter}{consensus_analysis_type},
            file_info_href          => \%file_info,
            hash_key_sort_reference => q{contigs_size_ordered},
            hash_key_to_sort        => q{select_file_contigs},
            log                     => $log,
        }
    );

## Get the ".fastq(.gz)" files from the supplied infiles directory. Checks if the files exist
    parse_infiles(
        {
            active_parameter_href => \%active_parameter,
            indir_path_href       => \%indir_path,
            infile_href           => \%infile,
            log                   => $log,
        }
    );

## Reformat file names to MIP format, get file name info and add info to sample_info
    my $is_file_uncompressed = parse_fastq_infiles(
        {
            active_parameter_href           => \%active_parameter,
            file_info_href                  => \%file_info,
            indir_path_href                 => \%indir_path,
            infile_both_strands_prefix_href => \%infile_both_strands_prefix,
            infile_href                     => \%infile,
            infile_lane_prefix_href         => \%infile_lane_prefix,
            lane_href                       => \%lane,
            log                             => $log,
            sample_info_href                => \%sample_info,
        }
    );

## Creates all fileendings as the samples is processed depending on the chain of modules activated
    build_file_prefix_tag(
        {
            active_parameter_href => \%active_parameter,
            file_info_href        => \%file_info,
            order_programs_ref    => \@order_programs,
            parameter_href        => \%parameter,
        }
    );

## Create .fam file to be used in variant calling analyses
    create_fam_file(
        {
            parameter_href        => \%parameter,
            active_parameter_href => \%active_parameter,
            sample_info_href      => \%sample_info,
            execution_mode        => 'system',
            fam_file_path         => catfile(
                $active_parameter{outdata_dir},
                $active_parameter{family_id},
                $active_parameter{family_id} . '.fam'
            ),
        }
    );

## Add to sample info
    add_to_sample_info(
        {
            active_parameter_href => \%active_parameter,
            file_info_href        => \%file_info,
            sample_info_href      => \%sample_info,
        }
    );

############
####MAIN####
############

    if ( not $active_parameter{dry_run_all} ) {

        my %no_dry_run_info = (
            analysisrunstatus => q{not_finished},
            analysis_date     => $date_time_stamp,
            mip_version       => $VERSION,
        );

      KEY_VALUE_PAIR:
        while ( my ( $key, $value ) = each %no_dry_run_info ) {

            $sample_info{$key} = $value;
        }
    }

## Split of fastq files in batches
    if ( $active_parameter{split_fastq_file} ) {

        $log->info(q{[Split fastq files in batches]});

      SAMPLE_ID:
        foreach my $sample_id ( @{ $active_parameter{sample_ids} } ) {

            ## Split input fastq files into batches of reads, versions and compress. Moves original file to subdirectory
            analysis_split_fastq_file(
                {
                    parameter_href        => \%parameter,
                    active_parameter_href => \%active_parameter,
                    infile_href           => \%infile,
                    job_id_href           => \%job_id,
                    insample_directory    => $indir_path{$sample_id},
                    outsample_directory   => $indir_path{$sample_id},
                    sample_id             => $sample_id,
                    program_name          => q{split_fastq_file},
                    sequence_read_batch =>
                      $active_parameter{split_fastq_file_read_batch},
                }
            );
        }

        ## End here if this module is turned on
        exit;
    }

## GZip of fastq files
    if (   $active_parameter{gzip_fastq}
        && $is_file_uncompressed )
    {

        $log->info(q{[Gzip for fastq files]});

      SAMPLES:
        foreach my $sample_id ( @{ $active_parameter{sample_ids} } ) {

            ## Determine which sample id had the uncompressed files
          INFILES:
            foreach my $infile ( @{ $infile{$sample_id} } ) {

                my $infile_suffix = $parameter{gzip_fastq}{infile_suffix};

                if ( $infile =~ /$infile_suffix$/sxm ) {

                    ## Automatically gzips fastq files
                    analysis_gzip_fastq(
                        {
                            parameter_href          => \%parameter,
                            active_parameter_href   => \%active_parameter,
                            sample_info_href        => \%sample_info,
                            infile_href             => \%infile,
                            infile_lane_prefix_href => \%infile_lane_prefix,
                            job_id_href             => \%job_id,
                            insample_directory      => $indir_path{$sample_id},
                            sample_id               => $sample_id,
                            program_name            => q{gzip_fastq},
                        }
                    );

                    # Call once per sample_id
                    last INFILES;
                }
            }
        }
    }

### Cancer
    if ( $consensus_analysis_type eq q{cancer} )

    {

        $log->info( q{Pipeline analysis type: } . $consensus_analysis_type );

        ## Pipeline recipe for cancer data
        pipeline_cancer(
            {
                parameter_href          => \%parameter,
                active_parameter_href   => \%active_parameter,
                sample_info_href        => \%sample_info,
                file_info_href          => \%file_info,
                indir_path_href         => \%indir_path,
                infile_href             => \%infile,
                infile_lane_prefix_href => \%infile_lane_prefix,
                lane_href               => \%lane,
                job_id_href             => \%job_id,
                outaligner_dir          => $active_parameter{outaligner_dir},
                log                     => $log,
            }
        );
    }

### RNA
    if ( $consensus_analysis_type eq q{wts} ) {

        $log->info( q{Pipeline analysis type: } . $consensus_analysis_type );

        ## Pipeline recipe for rna data
        pipeline_rna(
            {
                parameter_href          => \%parameter,
                active_parameter_href   => \%active_parameter,
                sample_info_href        => \%sample_info,
                file_info_href          => \%file_info,
                indir_path_href         => \%indir_path,
                infile_href             => \%infile,
                infile_lane_prefix_href => \%infile_lane_prefix,
                lane_href               => \%lane,
                job_id_href             => \%job_id,
                outaligner_dir          => $active_parameter{outaligner_dir},
                log                     => $log,
            }
        );
    }

### WES|WGS
    if (   $consensus_analysis_type eq q{wgs}
        || $consensus_analysis_type eq q{wes}
        || $consensus_analysis_type eq q{mixed} )
    {

        $log->info( q{Pipeline analysis type: } . $consensus_analysis_type );

        ## Pipeline recipe for rna data
        pipeline_rare_disease(
            {
                parameter_href          => \%parameter,
                active_parameter_href   => \%active_parameter,
                sample_info_href        => \%sample_info,
                file_info_href          => \%file_info,
                indir_path_href         => \%indir_path,
                infile_href             => \%infile,
                infile_lane_prefix_href => \%infile_lane_prefix,
                lane_href               => \%lane,
                job_id_href             => \%job_id,
                outaligner_dir          => $active_parameter{outaligner_dir},
                log                     => $log,
            }
        );
    }

## Write QC for programs used in analysis
    # Write SampleInfo to yaml file
    if ( $active_parameter{sample_info_file} ) {

        ## Writes a YAML hash to file
        write_yaml(
            {
                yaml_href      => \%sample_info,
                yaml_file_path => $active_parameter{sample_info_file},
            }
        );
        $log->info( q{Wrote: } . $active_parameter{sample_info_file} );
    }
    return;
}

######################
####Sub routines######
######################

##Investigate potential autodie error
if ( $EVAL_ERROR and $EVAL_ERROR->isa(q{autodie::exception}) ) {

    if ( $EVAL_ERROR->matches(q{default}) ) {

        say {*STDERR} q{Not an autodie error at all};
    }
    if ( $EVAL_ERROR->matches(q{open}) ) {

        say {*STDERR} q{Error from open};
    }
    if ( $EVAL_ERROR->matches(q{:io}) ) {

        say {*STDERR} q{Non-open, IO error.};
    }
}
elsif ($EVAL_ERROR) {

    say {*STDERR} q{A non-autodie exception.};
}

1;