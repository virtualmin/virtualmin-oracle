#!/usr/local/bin/perl
# exec.cgi
# Execute some SQL command and display output

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
	$cmd = $in{'cmd'} ? $in{'cmd'} : $in{'old'};
	$d = &execute_sql($in{'db'}, $cmd);

	&ui_print_header(undef, $text{'exec_title'}, "");
	print &text('exec_out', "<tt>$cmd</tt>"),"<p>\n";
	@data = @{$d->{'data'}};
	if (@data) {
		print "<table border> <tr $tb>\n";
		foreach $t (@{$d->{'titles'}}) {
			print "<td><b>$t</b></td>\n";
			}
		print "</tr>\n";
		foreach $r (@data) {
			print "<tr $cb>\n";
			foreach $c (@$r) {
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

	open(OLD, "$module_config_directory/commands.$in{'db'}");
	while(<OLD>) {
		s/\r|\n//g;
		$already++ if ($_ eq $in{'cmd'});
		}
	close(OLD);
	if (!$already && $in{'cmd'} =~ /\S/) {
		&open_lock_tempfile(OLD, ">>$module_config_directory/commands.$in{'db'}");
		&print_tempfile(OLD, "$in{'cmd'}\n");
		&close_tempfile(OLD);
		chmod(0700, "$module_config_directory/commands.$in{'db'}");
		}
	&webmin_log("exec", undef, $in{'db'}, \%in);

	&ui_print_footer("exec_form.cgi?db=$in{'db'}", $text{'exec_return'},
		"edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
		"", $text{'index_return'});
	}

