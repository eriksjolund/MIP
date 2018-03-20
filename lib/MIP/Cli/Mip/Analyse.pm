package MIP::Cli::Mip::Analyse;

use 5.018;
use Carp;
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ check allow last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use autodie qw{ :all };
use MooseX::App::Command;
use MooseX::Types::Moose qw{ Str Int HashRef Num Bool ArrayRef };
use Moose::Util::TypeConstraints;

our $VERSION = 0.01;

extends(qw{ MIP::Cli::Mip });

command_short_description(q{MIP analyse command});

command_long_description(q{Entry point for performing MIP analysis});

command_usage(q{analyse <pipeline>});

## Define, check and get Cli supplied parameters
_build_usage();

sub run {
    my ($arg_href) = @_;

    say {*STDERR} q{Please choose an subcommand to start the analysis};
    return;
}

sub _build_usage {

## Function : Get and/or set input parameters
## Returns  :
## Arguments:

    my ($arg_href) = @_;

    option(
        q{analysis_constant_path} => (
            cmd_aliases   => [qw{ acp }],
            documentation => q{Set the analysis constant path},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{analysis_type} => (
            cmd_aliases   => [qw{ at }],
            cmd_tags      => [q{sample_id=analysis_type}],
            documentation => q{Type of analysis},
            is            => q{rw},
            isa           => HashRef,
        )
    );

    option(
        q{cluster_constant_path} => (
            cmd_aliases   => [qw{ ccp }],
            documentation => q{Set the cluster constant path},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{config_file_analysis} => (
            cmd_aliases => [qw{ cfa }],
            cmd_tags    => [q{YAML}],
            documentation =>
              q{Write YAML configuration file the analysis parameters},
            is  => q{rw},
            isa => Str,
        )
    );

    option(
        q{dry_run_all} => (
            cmd_aliases => [qw{ dra }],
            documentation =>
              q{Sets all programs to dry run mode i.e. no sbatch submission},
            is  => q{rw},
            isa => Bool,
        )
    );

    option(
        q{email} => (
            cmd_aliases   => [qw{ em }],
            documentation => q{E-mail},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{email_types} => (
            cmd_aliases   => [qw{ emt }],
            cmd_tags      => [q{Default: FAIL}],
            documentation => q{E-mail type},
            is            => q{rw},
            isa           => ArrayRef [ enum( [qw{ FAIL BEGIN END }] ), ],
        )
    );

    option(
        q{expected_coverage} => (
            cmd_aliases   => [qw{ ec }],
            cmd_tags      => [q{sample_id=expected_coverage}],
            documentation => q{Expected mean target coverage for analysis},
            is            => q{rw},
            isa           => HashRef,
        )
    );

    parameter(
        q{family_id} => (
            documentation => q{Group id of samples to be compared},
            is            => q{rw},
            isa           => Str,
            required      => 1,
        )
    );

    option(
        q{gatk_path} => (
            cmd_aliases   => [qw{ gtp }],
            documentation => q{Path to GATK},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{gatk_logging_level} => (
            cmd_aliases   => [qw{ gll }],
            cmd_tags      => [q{Default: INFO}],
            documentation => q{Set the GATK log level},
            is            => q{rw},
            isa           => enum( [qw{ DEBUG INFO ERROR FATAL }] ),
        )
    );

    option(
        q{gatk_bundle_download_version} => (
            cmd_aliases   => [qw{ gbdv }],
            cmd_tags      => [q{Default: 2.8}],
            documentation => q{GATK FTP bundle download version},
            is            => q{rw},
            isa           => Num,
        )
    );

    option(
        q{gatk_downsample_to_coverage} => (
            cmd_aliases   => [qw{ gdco }],
            cmd_tags      => [q{Default: 1000}],
            documentation => q{Coverage to downsample to at any given locus},
            is            => q{rw},
            isa           => Int,
        )
    );

    option(
        q{gatk_disable_auto_index_and_file_lock} => (
            cmd_aliases => [qw{ gdai }],
            cmd_flag    => q{gatk_dis_auto_ind_fl},
            documentation =>
              q{Disable auto index creation and locking when reading rods},
            is  => q{rw},
            isa => Bool,
        )
    );

    option(
        q{human_genome_reference} => (
            cmd_aliases   => [qw{ hgr }],
            cmd_tags      => [q{Default: GRCh37_homo_sapiens_-d5-.fasta}],
            documentation => q{Human genome reference},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{infile_dirs} => (
            cmd_aliases   => [qw{ ifd }],
            cmd_tags      => [q{infile_dirs=sample_id}],
            documentation => q{Infile directory(s)},
            is            => q{rw},
            isa           => HashRef,
        )
    );

    option(
        q{java_use_large_pages} => (
            cmd_aliases   => [qw{ jul }],
            documentation => q{Use large page memory},
            is            => q{rw},
            isa           => Bool,
        )
    );

    option(
        q{node_ram_memory} => (
            cmd_aliases   => [qw{ nrm }],
            cmd_tags      => [q{Default: 24}],
            documentation => q{RAM memory size of the node(s) in GigaBytes},
            is            => q{rw},
            isa           => Int,
        )
    );

    option(
        q{max_cores_per_node} => (
            cmd_aliases   => [qw{ mcpn }],
            cmd_tags      => [q{Default: 16}],
            documentation => q{Maximum number of processor cores per node},
            is            => q{rw},
            isa           => Int,
        )
    );

    option(
        q{module_core_number} => (
            cmd_aliases   => [qw{ mcn }],
            cmd_tags      => [q{program_name=X(cores)}],
            documentation => q{Set the number of cores for each module},
            is            => q{rw},
            isa           => HashRef,
        )
    );

    option(
        q{module_source_environment_command} => (
            cmd_aliases => [qw{ mse }],
            cmd_flag    => q{mod_src_env},
            cmd_tags    => [q{program_name=command}],
            documentation =>
              q{Set environment variables specific for each module},
            is  => q{rw},
            isa => HashRef,
        )
    );

    option(
        q{module_time} => (
            cmd_aliases   => [qw{ mot }],
            cmd_tags      => [q{program_name=time(hours)}],
            documentation => q{Set the time allocation for each module},
            is            => q{rw},
            isa           => HashRef,
        )
    );

    option(
        q{outaligner_dir} => (
            cmd_aliases => [qw{ ald }],
            documentation =>
q{Sets which aligner out directory was used for alignment in previous analysis},
            is  => q{rw},
            isa => enum( [qw{ bwa star }] ),
        )
    );

    option(
        q{outdata_dir} => (
            cmd_aliases   => [qw{ odd }],
            documentation => q{Data output directory},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{outscript_dir} => (
            cmd_aliases   => [qw{ osd }],
            documentation => q{Script files (.sh) output directory},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{pedigree_file} => (
            cmd_aliases   => [qw{ ped }],
            cmd_tags      => [q{YAML}],
            documentation => q{Meta data on samples},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{platform} => (
            cmd_aliases   => [qw{ pla }],
            cmd_tags      => [q{Default: ILLUMINA}],
            documentation => q{Platform/technology used to produce the reads},
            is            => q{rw},
            isa           => enum( [qw{ ILLUMINA }] ),
        )
    );

    option(
        q{picardtools_path} => (
            cmd_aliases   => [qw{ ptp }],
            documentation => q{Path to Picardtools},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{print_program_mode} => (
            cmd_aliases   => [qw{ ppm }],
            documentation => q{Print all programs that are supported},
            is            => q{rw},
            isa           => enum( [ 0, 1, 2 ] ),
        )
    );

    option(
        q{project_id} => (
            cmd_aliases   => [qw{ pro }],
            documentation => q{Project id},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{print_programs} => (
            cmd_aliases   => [qw{ pp }],
            documentation => q{Print all programs that are supported},
            is            => q{rw},
            isa           => Bool,
        )
    );

    option(
        q{slurm_quality_of_service} => (
            cmd_aliases   => [qw{ qos }],
            cmd_flag      => q{slurm_quly_sri},
            documentation => q{SLURM quality of service},
            is            => q{rw},
            isa           => enum( [qw{ low normal high }] ),
        )
    );

    option(
        q{reference_dir} => (
            cmd_aliases   => [qw{ rd }],
            documentation => q{Reference(s) directory},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{reduce_io} => (
            cmd_aliases   => [qw{ rio }],
            documentation => q{Run consecutive models at node},
            is            => q{rw},
            isa           => Bool,
        )
    );

    option(
        q{replace_iupac} => (
            cmd_aliases => [qw{ riu }],
            documentation =>
              q{Replace IUPAC code in alternative alleles with N},
            is  => q{rw},
            isa => Bool,
        )
    );

    option(
        q{sample_ids} => (
            cmd_aliases => [qw{ spi }],
            documentation =>
              q{Sets all programs to dry run mode i.e. no sbatch submission},
            is  => q{rw},
            isa => q{ArrayRef[Str]},
        )
    );

    option(
        q{sample_info_file} => (
            cmd_aliases   => [qw{ sif }],
            cmd_tags      => [q{YAML}],
            documentation => q{File for sample info used in the analysis},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{start_with_program} => (
            cmd_aliases   => [qw{ swp }],
            documentation => q{Start analysis with program},
            is            => q{rw},
            isa           => Str,
        )
    );

    option(
        q{supported_capture_kit} => (
            cmd_aliases => [qw{ sck }],
            cmd_tags    => [q{acronym=file.bed}],
            documentation =>
              q{Set the capture kit acronym shortcut in pedigree file},
            is  => q{rw},
            isa => HashRef,
        )
    );

    option(
        q{source_main_environment_commands} => (
            cmd_aliases => [qw{ sen }],
            cmd_flag    => q{src_main_env},
            documentation =>
              q{Source main environment command in sbatch scripts},
            is  => q{rw},
            isa => ArrayRef,
        )
    );

    option(
        q{psplit_fastq_file} => (
            cmd_aliases => [qw{ psfq }],
            cmd_tags    => [q{Analysis recipe switch}],
            documentation =>
              q{Split fastq files in batches of X reads and exits},
            is  => q{rw},
            isa => enum( [ 0, 1, 2 ] ),
        )
    );

    option(
        q{split_fastq_file_read_batch} => (
            cmd_aliases   => [qw{ sfqrdb }],
            cmd_flag      => q{spt_fsq_rd_bt},
            cmd_tags      => [q{Default: 25,000,000}],
            documentation => q{Number of sequence reads to place in each batch},
            is            => q{rw},
            isa           => Int,
        )
    );

    option(
        q{pgzip_fastq} => (
            cmd_aliases   => [qw{ pgz }],
            cmd_tags      => [q{Analysis recipe switch}],
            documentation => q{Gzip fastq files},
            is            => q{rw},
            isa           => enum( [ 0, 1, 2 ] ),
        )
    );

    option(
        q{pfastqc} => (
            cmd_aliases   => [qw{ pfqc }],
            cmd_tags      => [q{Analysis recipe switch}],
            documentation => q{Sequence quality analysis using FastQC},
            is            => q{rw},
            isa           => enum( [ 0, 1, 2 ] ),
        )
    );

    return;
}

1;
