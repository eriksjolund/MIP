package MIP::File::Format::Vcf;

use 5.026;
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

## MIPs lib/
use MIP::Constants qw{ $SPACE $TAB };

BEGIN {
    require Exporter;
    use base qw{ Exporter };

    # Set the version for version checking
    our $VERSION = 1.01;

    # Functions and variables which can be optionally exported
    our @EXPORT_OK = qw{ check_vcf_variant_line parse_vcf_header  };
}

## Constants
Readonly my $INFO_COL_NR => 7;

sub check_vcf_variant_line {

## Function : Check variant line elements
## Returns  :
## Arguments: $input_line_number         => Input line number
##          : $log                       => Log object
##          : $variant_line              => Variant line
##          : $variant_line_elements_ref => Array for variant line elements {REF}

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $input_line_number;
    my $log;
    my $variant_line;
    my $variant_line_elements_ref;

    my $tmpl = {
        input_line_number => {
            defined     => 1,
            required    => 1,
            store       => \$input_line_number,
            strict_type => 1,
        },
        log => {
            defined  => 1,
            required => 1,
            store    => \$log,
        },
        variant_line => {
            defined     => 1,
            required    => 1,
            store       => \$variant_line,
            strict_type => 1,
        },
        variant_line_elements_ref => {
            default     => [],
            defined     => 1,
            required    => 1,
            store       => \$variant_line_elements_ref,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Check that we have some data in INFO field
    return 1 if ( defined $variant_line_elements_ref->[$INFO_COL_NR] );

    $log->fatal(qq{No INFO field at line number: $input_line_number});
    $log->fatal(qq{Displaying malformed line: $variant_line});
    exit 1;
}

sub parse_vcf_header {

## Function : Adds header meta data to hash
## Returns  :
## Arguments: $meta_data_href   => Hash for header data {REF}
##          : $meta_data_string => Meta data string from vcf header

    my ($arg_href) = @_;

    ## Flatten argument(s)
    my $meta_data_href;
    my $meta_data_string;

    my $tmpl = {
        meta_data_href => {
            default     => {},
            defined     => 1,
            required    => 1,
            store       => \$meta_data_href,
            strict_type => 1,
        },
        meta_data_string => {
            defined     => 1,
            required    => 1,
            store       => \$meta_data_string,
            strict_type => 1,
        },
    };

    check( $tmpl, $arg_href, 1 ) or croak q{Could not parse arguments!};

    ## Define how to parse meta-data header
    my %vcf_header_regexp = (
        fileformat   => q{\A [#]{2}(fileformat)=(\S+)},
        field_format => q{\A [#]{2}([^=]*)=<ID=([^,]*)},
    );

  SCHEMA:
    while ( my ( $key, $regexp ) = each %vcf_header_regexp ) {

        my ( $vcf_schema, $vcf_id ) = $meta_data_string =~ /$regexp/sxm;

        ## Alias method subs
        my $set_by_schema_and_id_cref = sub {
            $meta_data_href->{$vcf_schema}{$vcf_id} = $meta_data_string;
        };
        my $add_by_schema_cref = sub {
            push @{ $meta_data_href->{$vcf_schema}{$vcf_schema} }, $meta_data_string;
        };

        ## Create dispatch table
        my %add_to_meta_data = (
            ALT        => $set_by_schema_and_id_cref,
            contig     => $add_by_schema_cref,
            fileformat => $set_by_schema_and_id_cref,
            FILTER     => $set_by_schema_and_id_cref,
            FORMAT     => $set_by_schema_and_id_cref,
            INFO       => $set_by_schema_and_id_cref,
        );

        if ( $vcf_schema and exists $add_to_meta_data{$vcf_schema} ) {

            ## Add header line to hash
            $add_to_meta_data{$vcf_schema}->();
            return;
        }
    }

    ## All other meta-data headers - Add to array without using regexp
    push @{ $meta_data_href->{other}{other} }, $meta_data_string;
    return 1;
}

1;
