#!/usr/local/bin/perl
# exec.cgi
# Execute some SQL command and display output
use strict;
use warnings;
our (%text, %in);
our $module_config_directory;
our ($tb, $cb);

require './virtualmin-oracle-lib.pl';
&ReadParseMime();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
&error_setup($text{'exec_err'});

if ($in{'clear'}) {
	# Delete the history file
	unlink("$module_config_directory/commands.$in{'db'}");
	&redirect("exec_form.cgi?db=$in{'db'}");
	}
else {
	$in{'cmd'} = join(" ", split(/[\r\n]+/, $in{'cmd'}));
	my $cmd = $in{'cmd'} ? $in{'cmd'} : $in{'old'};
	my $d = &execute_sql($in{'db'}, $cmd);

	&ui_print_header(undef, $text{'exec_title'}, "");
	print &text('exec_out', "<tt>$cmd</tt>"),"<p>\n";
	my @data = @{$d->{'data'}};
	if (@data) {
		print "<table border> <tr $tb>\n";
		foreach my $t (@{$d->{'titles'}}) {
			print "<td><b>$t</b></td>\n";
			}
		print "</tr>\n";
		foreach my $r (@data) {
			print "<tr $cb>\n";
			foreach my $c (@$r) {
				print "<td>",$c =~ /\S/ ? &html_escape($c)
							: "<br>","</td>\n";
				}
			print "</tr>\n";
			}
		print "</table><p>\n";
		}
	else {
		print "<b>$text{'exec_none'}</b> <p>\n";
		}

	my $already;
	open(my $OLD, "<", "$module_config_directory/commands.$in{'db'}");
	while(<$OLD>) {
		s/\r|\n//g;
		$already++ if ($_ eq $in{'cmd'});
		}
	close($OLD);
	if (!$already && $in{'cmd'} =~ /\S/) {
		no strict "subs";
		&open_lock_tempfile(OLD, ">>$module_config_directory/commands.$in{'db'}");
		&print_tempfile(OLD, "$in{'cmd'}\n");
		&close_tempfile(OLD);
		use strict "subs";
		chmod(0700, "$module_config_directory/commands.$in{'db'}");
		}
	&webmin_log("exec", undef, $in{'db'}, \%in);

	&ui_print_footer("exec_form.cgi?db=$in{'db'}", $text{'exec_return'},
		"edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
		"", $text{'index_return'});
	}
