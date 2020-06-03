package MIP::Check::Reference;

use 5.026;
use Carp;
use charnames qw{ :full :short };
use English qw{ -no_match_vars };
use File::Spec::Functions qw{ catfile };
use open qw{ :encoding(UTF-8) :std };
use Params::Check qw{ check allow last_error };
use strict;
use utf8;
use warnings;
use warnings qw{ FATAL utf8 };

## CPANM
use List::MoreUtils qw { uniq };
use Readonly;

## MIPs lib/
use MIP::Constants qw{ $DOT $EQUALS $LOG_NAME $NEWLINE $SPACE $TAB };

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.18;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{
      check_if_processed_by_vt
      check_references_for_vt };
}

sub check_if_processed_by_vt {

## Function : Check if vt has processed references using regexp
## Returns  : @process_references
## Arguments: $bcftools_binary_path => Path to bcftools binary
##          : $log                  => Log object
##          : $reference_file_path  => The reference file path

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $bcftools_binary_path;
    my $log;
    my $reference_file_path;

    my $tmpl = {
        bcftools_binary_path => {
            defined     => 1,
            required    => 1,
            store       => \$bcftools_binary_path,
            strict_type => 1,
        },
        log => {
            defined  => 1,
            required => 1,
            store    => \$log,
        },
        reference_file_path => {
            defined     => 1,
            required    => 1,
            store       => \$reference_file_path,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Environment::Child_process qw{ child_process };
    use MIP::Program::Gnu::Bash qw{ gnu_export gnu_unset };

    my %vt_regexp;

    $vt_regexp{vt_decompose}{vcf_key} = q{OLD_MULTIALLELIC};
    $vt_regexp{vt_normalize}{vcf_key} = q{OLD_VARIANT};

    my @to_process_references;
    ## Downloaded and vt later (for downloadable references otherwise
    ## file existens error is thrown downstream)
    if ( not -e $reference_file_path ) {

        ## Do nothing since there is not ref file to check
        return;
    }

  VT_PARAMETER_NAME:
    foreach my $vt_parameter_name ( keys %vt_regexp ) {
        ## MIP flags

        ### Assemble perl regexp for detecting VT keys in vcf
        ## Execute perl
        my $regexp = q?perl -nae '?;

        ## Find vcf_key
        $regexp .= q?if($_=~/ID\=? . $vt_regexp{$vt_parameter_name}{vcf_key} . q?/) { ?;

        ## Write to stdout
        $regexp .= q?print $_} ?;

        ## If header is finished quit
        $regexp .= q?if($_=~/#CHROM/) {last}'?;

        ## Export MIP_BIND to bind reference path to htslib sif in proxy bin
        my $export_cmd = join $SPACE,
          gnu_export( { bash_variable => q{MIP_BIND} . $EQUALS . $reference_file_path } );

        ## Unset MIP_BIND after system parsing
        my $unset_cmd = join $SPACE, gnu_unset( { bash_variable => q{MIP_BIND}, } );

        ## Detect if vt program has processed reference
        my $check_vt_cmd =
qq{$export_cmd; $bcftools_binary_path view $reference_file_path | $regexp; $unset_cmd};

        my %process_return = child_process(
            {
                commands_ref => [$check_vt_cmd],
                process_type => q{ipc_cmd_run},
            }
        );

        ## No trace of vt processing found
        if ( not $process_return{stdouts_ref}[0] ) {

            ## Add reference for downstream processing
            push @to_process_references, $reference_file_path;
            $log->warn( $TAB
                  . q{Cannot detect that }
                  . $vt_parameter_name
                  . q{ has processed reference: }
                  . $reference_file_path
                  . $NEWLINE );
        }
        else {
            ## Found vt processing trace

            $log->info( $TAB
                  . q{Reference check: }
                  . $reference_file_path
                  . q{ vt: }
                  . $vt_parameter_name
                  . q{ - PASS}
                  . $NEWLINE );
        }
    }
    return uniq(@to_process_references);
}

sub check_references_for_vt {

## Function : Check if vt has processed references
## Returns  : @to_process_references
## Arguments: $active_parameter_href => Active parameters for this analysis hash {REF}
##          : $log                   => Log object
##          : $parameter_href        => Parameter hash {REF}
##          : $vt_references_ref     => The references to check with vt {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $active_parameter_href;
    my $log;
    my $parameter_href;
    my $vt_references_ref;

    my $tmpl = {
        active_parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$active_parameter_href,
            strict_type => 1,
        },
        log            => { store => \$log, },
        parameter_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$parameter_href,
            strict_type => 1,
        },
        vt_references_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$vt_references_ref,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Checked references
    my @checked_references;

    ## Store references to process later
    my @to_process_references;

    ## Avoid checking the same reference multiple times
    my %seen;

    ## Use MIPs own bcftools
    my $bcftools_binary_path = $active_parameter_href->{binary_path}{bcftools};

    ## TOML parameters
    my %toml = (
        sv_vcfanno_config => 1,
        vcfanno_config    => 1,
    );

  PARAMETER_NAME:
    foreach my $parameter_name ( @{$vt_references_ref} ) {

      ASSOCIATED_RECIPE:
        foreach my $associated_recipe (
            @{ $parameter_href->{$parameter_name}{associated_recipe} } )
        {

            ## Alias
            my $active_associated_recipe = $active_parameter_href->{$associated_recipe};

            next ASSOCIATED_RECIPE if ( not $active_associated_recipe );

            ## If SCALAR data type
            if ( $parameter_href->{$parameter_name}{data_type} eq q{SCALAR} ) {

                my $annotation_file = $active_parameter_href->{$parameter_name};

                ## Special case for toml configs (annotation file path recorded inside file parameter)
                if ( defined $toml{$parameter_name} ) {

                    _parse_vcfanno_toml_path(
                        {
                            bcftools_binary_path      => $bcftools_binary_path,
                            log                       => $log,
                            seen_href                 => \%seen,
                            toml_file_path            => $annotation_file,
                            to_process_references_ref => \@to_process_references,
                        }
                    );
                }
                if ( not exists $seen{$annotation_file} ) {

                    ## Check if vt has processed references using regexp
                    @checked_references = check_if_processed_by_vt(
                        {
                            bcftools_binary_path => $bcftools_binary_path,
                            log                  => $log,
                            reference_file_path  => $annotation_file,
                        }
                    );
                    push @to_process_references, @checked_references;
                }
                $seen{$annotation_file} = undef;
            }
            elsif ( $parameter_href->{$parameter_name}{data_type} eq q{ARRAY} ) {
                ## ARRAY reference

              ANNOTION_FILE:
                foreach
                  my $annotation_file ( @{ $active_parameter_href->{$parameter_name} } )
                {

                    if ( not exists $seen{$annotation_file} ) {

                        ## Check if vt has processed references using regexp
                        @checked_references = check_if_processed_by_vt(
                            {
                                bcftools_binary_path => $bcftools_binary_path,
                                log                  => $log,
                                reference_file_path  => $annotation_file,
                            }
                        );
                    }
                    push @to_process_references, @checked_references;
                    $seen{$annotation_file} = undef;
                }
            }
            elsif ( $parameter_href->{$parameter_name}{data_type} eq q{HASH} ) {
                ## Hash reference

              ANNOTATION_FILE:
                for my $annotation_file (
                    keys %{ $active_parameter_href->{$parameter_name} } )
                {

                    if ( not exists $seen{$annotation_file} ) {

                        ## Check if vt has processed references using regexp
                        @checked_references = check_if_processed_by_vt(
                            {
                                bcftools_binary_path => $bcftools_binary_path,
                                log                  => $log,
                                reference_file_path  => $annotation_file,
                            }
                        );
                    }
                    push @to_process_references, @checked_references;
                    $seen{$annotation_file} = undef;
                }
            }
        }
    }
    return uniq(@to_process_references);
}

sub _parse_vcfanno_toml_path {

## Function : Parse TOML config for path to check with vt
## Returns  :
## Arguments: $bcftools_binary_path      => Path to bcftools binary
##          : $log                       => Log object
##          : $seen_href                 => Avoid checking the same reference multiple times
##          : $toml_file_path            => Toml config file path
##          : $to_process_references_ref => Store references to process later

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $bcftools_binary_path;
    my $log;
    my $seen_href;
    my $toml_file_path;
    my $to_process_references_ref;

    my $tmpl = {
        bcftools_binary_path => {
            defined     => 1,
            required    => 1,
            store       => \$bcftools_binary_path,
            strict_type => 1,
        },
        log       => { store => \$log, },
        seen_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$seen_href,
            strict_type => 1,
        },
        to_process_references_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$to_process_references_ref,
            strict_type => 1,
        },
        toml_file_path => {
            default     => 1,
            store       => \$toml_file_path,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    use MIP::Io::Read qw{ read_from_file };

    my %vcfanno_config = read_from_file(
        {
            format => q{toml},
            path   => $toml_file_path,
        }
    );

    ## Add config parameter to avoid vt check of toml config path
    $seen_href->{$toml_file_path} = undef;

  ANNOTATION:
    foreach my $annotation_href ( @{ $vcfanno_config{annotation} } ) {

        ## Annotation file path to check
        my $annotation_file_path = $annotation_href->{file};

        ## Only check vcf files which should have the fields annotation
        next ANNOTATION if ( not exists $annotation_href->{fields} );

        ## Skip files not set for normalization in the toml
        next ANNOTATION if ( $annotation_href->{skip_split_and_normalize} );

        if ( not exists $seen_href->{$annotation_file_path} ) {

            ## Check if vt has processed references using regexp
            my @checked_references = check_if_processed_by_vt(
                {
                    bcftools_binary_path => $bcftools_binary_path,
                    log                  => $log,
                    reference_file_path  => $annotation_file_path,
                }
            );
            push @{$to_process_references_ref}, @checked_references;
        }
        $seen_href->{$annotation_file_path} = undef;
    }
    return;
}

1;
