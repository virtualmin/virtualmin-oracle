#!/usr/local/bin/perl
# Drop multiple tables, after asking for confirmation

require './virtualmin-oracle-lib.pl';
&ReadParse();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
@tables = split(/\0/, $in{'d'});
@tables || &error($text{'tdrops_enone'});

if ($in{'confirm'}) {
	# Drop the table
	&error_setup($text{'tdrops_err'});
	foreach $t (@tables) {
		&execute_sql($in{'db'}, "drop table ".&quotestr($t));
		}
	&webmin_log("delete", "tables", scalar(@tables), \%in);
	&redirect("edit_dbase.cgi?db=$in{'db'}");
	}
else {
	# Ask the user if he is sure..
	&ui_print_header(undef, $text{'tdrops_title'}, "");
	foreach $t (@tables) {
		$d = &execute_sql($in{'db'},
			"select count(*) from ".&quotestr($t));
		$rows += $d->{'data'}->[0]->[0];
		}

	print "<center><b>", &text('tdrops_rusure', scalar(@tables),
				   "<tt>$in{'db'}</tt>", $rows),"</b><p>\n";
	print "<form action=drop_tables.cgi>\n";
	print "<input type=hidden name=db value='$in{'db'}'>\n";
	print "<input type=submit name=confirm value='$text{'tdrops_ok'}'>\n";
	foreach $t (@tables) {
		print &ui_hidden("d", $t),"\n";
		}
	print "</form></center>\n";
	&ui_print_footer("edit_table.cgi?db=$in{'db'}&table=$in{'table'}",
		$text{'table_return'},
		"edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
		"", $text{'index_return'});
	}

