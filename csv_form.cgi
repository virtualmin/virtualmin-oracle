#!/usr/local/bin/perl
# Show a form for exporting CSV data
use strict;
use warnings;
our (%access, %text, %in);

require './virtualmin-oracle-lib.pl';
&ReadParse();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});

my $desc = &text('table_header', "<tt>$in{'table'}</tt>", "<tt>$in{'db'}</tt>");
&ui_print_header($desc, $text{'csv_title'}, "");

print &ui_form_start("csv.cgi/$in{'table'}.csv", "post");
print &ui_hidden("db", $in{'db'}),"\n";
print &ui_hidden("table", $in{'table'}),"\n";
print &ui_table_start($text{'csv_header'}, undef, 2);

print &ui_table_row($text{'csv_format'},
		    &ui_radio("format", 0, [ [ 0, $text{'csv_format0'} ],
					     [ 1, $text{'csv_format1'} ],
					     [ 2, $text{'csv_format2'} ] ]));

print &ui_table_row($text{'csv_headers'},
		    &ui_yesno_radio("headers", 0));

if ($access{'csv'}) {
	print &ui_table_row($text{'csv_dest'},
		    &ui_radio("dest", 0, [ [ 0, $text{'csv_browser'}."<br>" ],
					   [ 1, $text{'csv_file'} ] ])."\n".
		    &ui_textbox("file", undef, 40));
	}

# Rows to select
print &ui_table_row($text{'csv_where'},
		    &ui_opt_textbox("where", undef, 30, $text{'csv_all'}));

# Columns to select
my @str = &table_structure($in{'db'}, $in{'table'});
my @cols = map { $_->{'field'} } @str;
print &ui_table_row($text{'csv_cols'},
	    &ui_select("cols", \@cols,
		       [ map { [ $_->{'field'}, "$_->{'field'} - $_->{'type'}" ] } @str ], 5, 1));

print &ui_table_end();
print &ui_form_end([ [ "ok", $text{'csv_ok'} ] ]);

&ui_print_footer("edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
	"", $text{'index_return'});
