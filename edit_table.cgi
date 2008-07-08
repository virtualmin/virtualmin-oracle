#!/usr/local/bin/perl
# edit_table.cgi
# Display the structure of some table

require './virtualmin-oracle-lib.pl';
&ReadParse();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
$desc = &text('table_header', "<tt>$in{'table'}</tt>", "<tt>$in{'db'}</tt>");
&ui_print_header($desc, $text{'table_title'}, "");

@desc = &table_structure($in{'db'}, $in{'table'});
print "<form action=edit_field.cgi>\n";
print "<input type=hidden name=db value='$in{'db'}'>\n";
print "<input type=hidden name=table value='$in{'table'}'>\n";
print "<table border width=100%>\n";
print "<tr $tb> <td><b>$text{'table_field'}</b></td> ",
      "<td><b>$text{'table_type'}</b></td> ",
      "<td><b>$text{'table_null'}</b></td> ",
      "<td><b>$text{'table_key'}</b></td> </tr>\n";
$i = 0;
foreach $r (@desc) {
	print "<tr $cb>\n";
	print "<td><a href='edit_field.cgi?db=$in{'db'}&table=".
	      &urlize($in{'table'})."&".
	      "idx=$i'>",&html_escape($r->{'field'}),"</a></td>\n";
	print "<td>",&html_escape($r->{'type'}),"</td>\n";
	printf "<td>%s</td>\n",
		$r->{'null'} eq 'YES' ? $text{'yes'} : $text{'no'};
	printf "<td>%s</td>\n",
		$r->{'key'} eq 'PRI' ? $text{'table_pri'} :
		$r->{'key'} eq 'MUL' ? $text{'table_mul'} :
				       $text{'table_none'};
	print "</tr>\n";
	$i++;
	}
print "</table>\n";
print "<table width=100%><tr>\n";

# Add field button
print "<td width=25% nowrap><input type=submit value='$text{'table_add'}'>\n";
print "<select name=type>\n";
foreach $t (@type_list) {
	print "<option>$t\n";
	}
print "</select></td></form>\n";

# View and edit data button
print "<form action=view_table.cgi method=post enctype=multipart/form-data>\n";
print "<input type=hidden name=db value='$in{'db'}'>\n";
print "<input type=hidden name=table value='$in{'table'}'>\n";
print "<td align=center width=25%>\n";
print "<input type=submit value='$text{'table_data'}'></td>\n";
print "</form>\n";

# CSV export button
print "<form action=csv_form.cgi>\n";
print "<input type=hidden name=db value='$in{'db'}'>\n";
print "<input type=hidden name=table value='$in{'table'}'>\n";
print "<td align=center width=25%>\n";
print "<input type=submit value='$text{'table_csv'}'></td>\n";
print "</form>\n";

# Drop table button
print "<form action=drop_table.cgi>\n";
print "<input type=hidden name=db value='$in{'db'}'>\n";
print "<input type=hidden name=table value='$in{'table'}'>\n";
print "<td align=right width=25%>\n";
print "<input type=submit value='$text{'table_drop'}'></td>\n";
print "</form>\n";

print "</tr></table>\n";

&ui_print_footer("edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
	"", $text{'index_return'});

