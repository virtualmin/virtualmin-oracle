#!/usr/local/bin/perl
# table_form.cgi
# Display a form for creating a table
use strict;
use warnings;
our (%text, %in);
our ($tb, $cb);

require './virtualmin-oracle-lib.pl';
&ReadParse();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
&ui_print_header("<tt>$in{'db'}</tt>", $text{'table_title2'}, "");

print "<form action=create_table.cgi method=post>\n";
print "<input type=hidden name=db value='$in{'db'}'>\n";
print "<table border width=100%>\n";
print "<tr $tb> <td><b>$text{'table_header2'}</b></td> </tr>\n";
print "<tr $cb> <td><table width=100%>\n";

print "<tr> <td width=25%><b>$text{'table_name'}</b></td>\n";
print "<td><input name=name size=30></td> </tr>\n";

print "<tr> <td colspan=2>";
&show_table_form($in{"fields"} || 4);
print "</td> </tr>\n";

print "<tr> <td colspan=2 align=right><input type=submit ",
      "value='$text{'create'}'></td> </tr>\n";

print "</table></td></tr></table></form>\n";

&ui_print_footer("edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
	"", $text{'index_return'});
