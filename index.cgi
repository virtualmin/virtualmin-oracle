#!/usr/local/bin/perl
# Show icons for each Oracle DB

require './virtualmin-oracle-lib.pl';
&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);

# Check that Oracle is installed
$err = &check_config();
if ($err) {
	&ui_print_endpage(&text('index_econfig', $err,
				"../config.cgi?$module_name"));
	}

if ($config{'host'}) {
	# Running on remote, so we have to ask for the database name
	print &ui_form_start("edit_dbase.cgi");
	print "<b>$text{'index_name'}</b>\n";
	print &ui_textbox("db", &get_default_db(), 12),"\n";
	print &ui_submit($text{'index_edit'});
	print &ui_form_end();
	}
else {
	# Show databases as icons
	@alldbs = &list_oracle_database_names();
	@dbs = grep { &can_edit_db($_) } @alldbs;
	if (@dbs) {
		@links = map { "edit_dbase.cgi?db=".&urlize($_) } @dbs;
		@icons = map { "images/dbase.gif" } @dbs;
		@titles = @dbs;
		&icons_table(\@links, \@titles, \@icons);
		}
	elsif (!@alldbs) {
		print "<b>$text{'index_none'}</b><p>\n";
		}
	else {
		print "<b>$text{'index_cannot'}</b><p>\n";
		}
	}

&ui_print_footer("/", $text{'index'});

