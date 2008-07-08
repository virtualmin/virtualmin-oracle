#!/usr/local/bin/perl
# Show icons for each table

require './virtualmin-oracle-lib.pl';
&ReadParse();
&ui_print_header("<tt>$in{'db'}</tt>", $text{'dbase_title'}, "");
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});

&set_default_db($in{'db'});
@tables = &list_tables($in{'db'});
if (@tables) {
	@links = map { "edit_table.cgi?db=".&urlize($in{'db'})."&table=".&urlize($_) } @tables;
	@icons = map { "images/table.gif" } @tables;
	@titles = @tables;
	&icons_table(\@links, \@titles, \@icons);
	}
else {
	print "<b>$text{'dbase_none'}</b><p>\n";
	}

# Show creation button
print "<table width=100%><tr>\n";

print &ui_form_start("table_form.cgi");
print "<td>\n";
print &ui_hidden("db", $in{'db'});
print &ui_submit($text{'dbase_create'}),"\n";
print $text{'dbase_fields'}," ",&ui_textbox("fields", 4, 5);
print "</td>\n";
print &ui_form_end();

print &ui_form_start("exec_form.cgi");
print "<td align=right>\n";
print &ui_hidden("db", $in{'db'});
print &ui_submit($text{'dbase_exec'}),"\n";
print "</td>\n";
print &ui_form_end();

print "</tr></table>\n";

&ui_print_footer("", $text{'index_return'});

