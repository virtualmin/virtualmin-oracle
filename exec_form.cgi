#!/usr/local/bin/perl
# exec_form.cgi
# Display a form for executing SQL in some database
use strict;
use warnings;
our (%text, %in);
our $module_config_directory;

require './virtualmin-oracle-lib.pl';
&ReadParse();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
&ui_print_header("<tt>$in{'db'}</tt>", $text{'exec_title'}, "", "exec_form");

# Form for executing an SQL command
my @old;
open(my $OLD, "<", "$module_config_directory/commands.$in{'db'}");
while(<$OLD>) {
	s/\r|\n//g;
	push(@old, $_);
	}
close($OLD);

print "<p>",&text('exec_header', "<tt>$in{'db'}</tt>"),"<p>\n";
print "<form action=exec.cgi method=post enctype=multipart/form-data>\n";
print "<input type=hidden name=db value='$in{'db'}'>\n";
print "<textarea name=cmd rows=10 cols=70></textarea><br>\n";
if (@old) {
	print "$text{'exec_old'} <select name=old>\n";
	foreach my $o (@old) {
		printf "<option value=\"%s\">%s\n", &html_escape($o),
		    &html_escape(length($o) > 80 ? substr($o, 0, 80).".." : $o);
		}
	print "</select>\n";
	print "<input type=button name=movecmd ",
	      "value='$text{'exec_edit'}' onClick='cmd.value = old.options[old.selectedIndex].value'>\n";
	print "<input type=submit name=clear value='$text{'exec_clear'}'><br>\n";
	}
print "<input type=submit value='$text{'exec_exec'}'></form>\n";

&ui_print_footer("edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
	"", $text{'index_return'});
