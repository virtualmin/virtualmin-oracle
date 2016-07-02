#!/usr/local/bin/perl
# edit_field.cgi
# Display a form for editing an existing field or creating a new one
use strict;
use warnings;
our (%text, %in);
our @type_list;
our ($tb, $cb); # XXX Ugh.

require './virtualmin-oracle-lib.pl';
&ReadParse();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
my $desc = &text('field_in', "<tt>$in{'table'}</tt>", "<tt>$in{'db'}</tt>");
my ($f, $type);
my @desc;
if ($in{'type'}) {
	# Creating a new field
	&ui_print_header($desc, $text{'field_title1'}, "", "create_field");
	$type = $in{'type'};
	}
else {
	# Editing an existing field
	&ui_print_header($desc, $text{'field_title2'}, "", "edit_field");
	@desc = &table_structure($in{'db'}, $in{'table'});
	$f = $desc[$in{'idx'}];
	$type = $f->{'type'};
	}

print "<form action=save_field.cgi>\n";
print "<input type=hidden name=db value='$in{'db'}'>\n";
print "<input type=hidden name=table value='$in{'table'}'>\n";
print "<input type=hidden name=new value='$in{'type'}'>\n";
print "<table border>\n";
print "<tr $tb> <td><b>$text{'field_header'}</b></td> </tr>\n";
print "<tr $cb> <td><table>\n";

print "<tr> <td><b>$text{'field_name'}</b></td>\n";
print "<td><input name=field size=20 value='$f->{'field'}'></td> </tr>\n";
print "<input type=hidden name=old value='$f->{'field'}'>\n" if (!$in{'type'});

my $size;
if ($type =~ /^(\S+)\((.*)\)(.*)/) {
	$type = $1;
	$size = $2;
	}
print "<input type=hidden name=type value='$type'>\n";
print "<tr> <td><b>$text{'field_type'}</b></td>\n";
if ($in{'type'}) {
	# New field .. just show chosen type
	print "<td>$type</td> </tr>\n";
	}
else {
	# Existing field .. allow type change
	print "<td><select name=newtype>\n";
	foreach my $t (@type_list) {
		printf "<option %s>%s\n",
			$t eq $type ? "selected" : "", $t;
		}
	print "</select> $text{'field_typewarn'}</td> </tr>\n";
	}

if ($type eq 'number') {
	# Two values
	print "<tr> <td><b>$text{'field_dual'}</b></td>\n";
	printf "<td><input name=size1 size=5 value='%s'>\n",
		$size =~ /^(\d+)/ ? $1 : '';
	printf "<input name=size2 size=5 value='%s'></td> </tr>\n",
		$size =~ /(\d+)$/ ? $1 : '';
	}
elsif ($type eq 'date' || $type eq 'datetime' || $type eq 'time' ||
       $type =~ /(long|raw|blob)$/) {
	# No width!
	}
elsif ($type ne 'varchar' && $type ne 'char' && $in{'type'}) {
	# Size is optional for new fields of most types
	print "<tr> <td><b>$text{'field_size'}</b></td>\n";
	print "<td><input type=radio name=size_def value=1 checked> ",
	      "$text{'default'}\n";
	print "<input type=radio name=size_def value=0>\n";
	print "<input name=size size=10 value='$size'></td> </tr>\n";
	}
else {
	# One single value
	print "<tr> <td><b>$text{'field_size'}</b></td>\n";
	print "<td><input name=size size=10 value='$size'></td> </tr>\n";
	}

print "<tr> <td><b>$text{'field_null'}</b></td>\n";
printf "<td><input name=null type=radio value=1 %s> $text{'yes'}\n",
	$in{'type'} || $f->{'null'} eq 'YES' ? 'checked' : '';
printf "<input name=null type=radio value=0 %s> $text{'no'}</td> </tr>\n",
	$in{'type'} || $f->{'null'} eq 'YES' ? '' : 'checked';

print "<tr> <td><b>$text{'field_key'}</b></td>\n";
printf "<td><input type=radio name=key value=1 %s> %s\n",
	$f->{'key'} eq 'PRI' ? 'checked' : '', $text{'yes'};
printf "<input type=radio name=key value=0 %s> %s</td> </tr>\n",
	$f->{'key'} eq 'PRI' ? '' : 'checked', $text{'no'};
printf "<input type=hidden name=oldkey value='%d'>\n",
	$f->{'key'} eq 'PRI' ? 1 : 0;

print "</table></td></tr></table>\n";
if ($in{'type'}) {
	print "<input type=submit value='$text{'create'}'>\n";
	}
else {
	print "<input type=submit value='$text{'save'}'>&nbsp;\n";
	print "<input type=submit name=delete value='$text{'delete'}'>\n"
		if (@desc > 1);
	}
print "</form>\n";

&ui_print_footer("edit_table.cgi?db=$in{'db'}&table=".&urlize($in{'table'}),
		 $text{'table_return'},
		 "edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
		 "", $text{'index_return'});
