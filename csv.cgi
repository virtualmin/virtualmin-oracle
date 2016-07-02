#!/usr/local/bin/perl
# Export the CSV
use strict;
use warnings;
our (%access, %text, %in);

require './virtualmin-oracle-lib.pl';
&ReadParse();
&error_setup($text{'csv_err'});
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});

# Validate inputs
if ($in{'dest'}) {
	$in{'file'} =~ /^([a-z]:)?\/\S/ || &error($text{'csv_efile'});
	$access{'buser'} || &error($text{'cvs_ebuser'});
	}
if (!$in{'where_def'}) {
	$in{'where'} =~ /\S/ || &error($text{'csv_ewhere'});
	}

# Execute the SQL
my @cols = split(/\0/, $in{'cols'});
@cols || &error($text{'csv_ecols'});
my $cmd = "select ".join(",", @cols)." from ".&quotestr($in{'table'});
if (!$in{'where_def'}) {
	$cmd .= " where ".$in{'where'};
	}
my $rv = &execute_sql($in{'db'}, $cmd);

# Open the destination
my $fh;
if (!$in{'dest'}) {
	print "Content-type: text/plain\n\n";
	$fh = *STDOUT;
	}
elsif ($access{'csv'}) {
	# Open target file directly
	no strict "subs";
	&open_tempfile(OUT, ">$in{'file'}");
	$fh = OUT;
	use strict "subs";
	}

# Send the data
if ($in{'headers'}) {
	unshift(@{$rv->{'data'}}, $rv->{'titles'});
	}
foreach my $r (@{$rv->{'data'}}) {
	if ($in{'format'} == 0) {
		print $fh join(",", map { "\"".&quote_csv($_, "\"\n")."\"" } @$r);
		}
	elsif ($in{'format'} == 1) {
		print $fh join(",", map { &quote_csv($_, ",\n") } @$r);
		}
	elsif ($in{'format'} == 2) {
		print $fh join("\t", map { &quote_csv($_, "\t\n") } @$r);
		}
	print $fh "\n";
	}

# All done .. tell the user
if ($in{'dest'}) {
	no strict "subs";
	&close_tempfile(OUT); # XXX Shouldn't this be $fh?
	use strict "subs";
	my $desc = &text('table_header', "<tt>$in{'table'}</tt>", "<tt>$in{'db'}</tt>");
	&ui_print_header($desc, $text{'csv_title'}, "", "csv");

	my @st = stat($in{'file'});
	print &text('csv_done', "<tt>$in{'file'}</tt>",
				&nice_size($st[7])),"<p>\n";

	&ui_print_footer("edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
		"", $text{'index_return'});
	}

sub quote_csv
{
my ($str, $q) = @_;
$str =~ s/\r//g;
foreach my $c (split(//, $q)) {
	my $qc = $c eq "\"" ? "\\\"" :
		$c eq "\n" ? "\\n" :
		$c eq "," ? "\\," :
		$c eq "\t" ? "\\t" : $c;
	$str =~ s/\Q$c\E/$qc/g;
	}
return $str;
}
