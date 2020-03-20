package MIP::Analysis;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Basename qw{ dirname };
use File::Spec::Functions qw{ catdir catfile };
use FindBin qw{ $Bin };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ check allow last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## Third party module(s)
use autodie;
use List::MoreUtils qw{ all any };
use Log::Log4perl;
use Readonly;

## MIPs lib/
use MIP::Constants qw{ $EMPTY_STR $LOG_NAME $SINGLE_QUOTE };

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.17;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{
      check_analysis_type_compatibility
      get_overall_analysis_type
      get_vcf_parser_analysis_suffix
    };
}

sub get_overall_analysis_type {

## Function : Detect if all samples has the same analysis type and return consensus or mixed
## Returns  : q{consensus} | q{mixed} - analysis_type
## Arguments: $analysis_type_href => Analysis_type hash {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $analysis_type_href;

    my $tmpl = {
        analysis_type_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$analysis_type_href,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger($LOG_NAME);

    my @analysis_types = qw{ dragen_rd_dna vrn wes wgs wts };

  ANALYSIS:
    foreach my $analysis_type (@analysis_types) {

        ## If consensus is reached
        if ( all { $_ eq $analysis_type } values %{$analysis_type_href} ) {

            return $analysis_type;
        }
    }

    ## Check that the user supplied analysis type is supported
    foreach my $user_analysis_type ( values %{$analysis_type_href} ) {

        if ( not any { $_ eq $user_analysis_type } @analysis_types ) {

            $log->fatal(qq{' $user_analysis_type ' is not a supported analysis_type});
            $log->fatal( q{Supported analysis types are }
                  . $SINGLE_QUOTE
                  . join( q{', '}, @analysis_types )
                  . $SINGLE_QUOTE );
            $log->fatal(q{Aborting run});
            exit 1;
        }
    }

    # No consensus, then it must be mixed
    return q{mixed};
}

sub get_vcf_parser_analysis_suffix {

## Function : Get the vcf parser analysis suffix
## Returns  : @analysis_suffixes
## Arguments: $vcfparser_outfile_count => Number of user supplied vcf parser outfiles

    my ($arg_href) = @_;

## Flatten argument(s)
    my $vcfparser_outfile_count;

    my $tmpl = {
        vcfparser_outfile_count => {
            defined     => 1,
            required    => 1,
            store       => \$vcfparser_outfile_count,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    Readonly my $VCFPARSER_OUTFILE_COUNT => $vcfparser_outfile_count - 1;

    my @analysis_suffixes;

    ## Determined by vcfparser output
    # Set research (="") and selected file suffix
    for my $vcfparser_outfile_counter ( 0 .. $VCFPARSER_OUTFILE_COUNT ) {

        if ( $vcfparser_outfile_counter == 1 ) {

            ## Select file variants
            push @analysis_suffixes, q{selected};
            next;
        }
        push @analysis_suffixes, $EMPTY_STR;
    }
    return @analysis_suffixes;
}

sub check_analysis_type_compatibility {

## Function : Check if consensus analysis type is compatible with the pipeline
## Returns  :
## Arguments: $analysis_type => Analysis type
##          : $pipeline      => Pipeline

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $analysis_type;
    my $pipeline;

    my $tmpl = {
        analysis_type => {
            defined     => 1,
            required    => 1,
            store       => \$analysis_type,
            strict_type => 1,
        },
        pipeline => {
            allow       => [qw{ dragen_rd_dna rd_dna rd_dna_vcf_rerun rd_rna}],
            defined     => 1,
            required    => 1,
            store       => \$pipeline,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Retrieve logger object
    my $log = Log::Log4perl->get_logger($LOG_NAME);

    my @analysis_types = qw{ dragen_rd_dna vrn wes wgs wts };

    my %analysis_pipeline_map = (
        dragen_rd_dna => q{dragen_rd_dna},
        mixed         => q{rd_dna},
        vrn           => q{rd_dna_vcf_rerun},
        wes           => q{rd_dna},
        wgs           => q{rd_dna},
        wts           => q{rd_rna},
    );

    if ( $analysis_pipeline_map{$analysis_type} ne $pipeline ) {

        $log->fatal(
qq{Analysis type: $analysis_type is not compatiple with MIP pipeline: $pipeline}
        );
        $log->fatal(
qq{Start MIP pipeline: $analysis_pipeline_map{$analysis_type} for this analysis type}
        );
        $log->fatal(q{Aborting run});
        exit 1;
    }
    return 1;
}

1;
