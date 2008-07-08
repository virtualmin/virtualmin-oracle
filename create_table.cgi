#!/usr/local/bin/perl
# create_table.cgi
# Create a new table

require './virtualmin-oracle-lib.pl';
&ReadParse();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
&error_setup($text{'table_err'});
$in{'name'} =~ /^\S+$/ || &error($text{'table_ename'});
@sql = &parse_table_form(\@fields, $in{'name'});
foreach $sql (@sql) {
	&execute_sql($in{'db'}, $sql);
	}
&redirect("edit_dbase.cgi?db=$in{'db'}");


