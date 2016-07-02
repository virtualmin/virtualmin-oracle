#!/usr/local/bin/perl
# view_table.cgi
# Display all data in some table
use strict;
use warnings;
our (%text, %in, %config);
our ($tb, $cb); # XXX

require './virtualmin-oracle-lib.pl';
if ($config{'charset'}) {
	no warnings "once";
	$main::force_charset = $config{'charset'};
	use warnings "once";
	}
if ($ENV{'CONTENT_TYPE'} !~ /boundary=/) {
	&ReadParse();
	}
else {
	&ReadParseMime();
	}
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
my @str = &table_structure($in{'db'}, $in{'table'});
my $keyed;
my ($search, $searchargs, $searchhids);
my @adv;
foreach my $s (@str) {
	$keyed++ if ($s->{'key'} eq 'PRI');
	}
if ($in{'field'}) {
	# A simple search
	$search = "where ".&quotestr($in{'field'})." ".
		   &make_like($in{'match'}, $in{'for'});
	$searchargs = "&field=".&urlize($in{'field'}).
		      "&for=".&urlize($in{'for'}).
		      "&match=".&urlize($in{'match'});
	$searchhids = &ui_hidden("field", $in{'field'})."\n".
		      &ui_hidden("for", $in{'for'})."\n".
		      &ui_hidden("match", $in{'match'})."\n";
	}
elsif ($in{'advanced'}) {
	# An advanced search
	for(my $i=0; defined($in{"field_$i"}); $i++) {
		if ($in{"field_$i"}) {
			push(@adv, &quotestr($in{"field_$i"})." ".
				   &make_like($in{"match_$i"}, $in{"for_$i"}));
			$searchargs .= "&field_$i=".&urlize($in{"field_$i"}).
				       "&for_$i=".&urlize($in{"for_$i"}).
				       "&match_$i=".&urlize($in{"match_$i"});
			$searchhids .= &ui_hidden("field_$i", $in{"field_$i"})."\n".
				      &ui_hidden("for_$i", $in{"for_$i"})."\n".
				      &ui_hidden("match_$i", $in{"match_$i"})."\n";
			}
		}
	if (@adv) {
		$search = "where (".join($in{'and'} ? " and " : " or ",
					@adv).")";
		$searchhids .= &ui_hidden("and", $in{'and'})."\n".
			       &ui_hidden("advanced", 1)."\n";
		$searchargs .= "&and=".$in{'and'}.
			       "&advanced=1";
		}
	}

# Build where expression
# XXX This is a big hairy function. Hard to think about.
my $whereclause;
my @set;
my @d;
if ($search) {
	$whereclause = "where ( $search ) and rownum >= ".($in{'start'}+1)." and rownum < ".($in{'start'}+$config{'perpage'}+1);
	}
else {
	$whereclause = "where rownum >= ".($in{'start'}+1)." and rownum < ".($in{'start'}+$config{'perpage'}+1);
	}

if ($in{'delete'}) {
	# Deleting selected rows
	my $d = &execute_sql($in{'db'}, "select * from ".&quotestr($in{'table'}).
			 " ".$whereclause);
	my @t = @{$d->{'titles'}};
	my $count = 0;
	foreach my $r (split(/\0/, $in{'row'})) {
		my @where;
		my @r = @{$d->{'data'}->[$r]};
		for(my $i=0; $i<@t; $i++) {
			if ($str[$i]->{'key'} eq 'PRI') {
				if ($r[$i] eq 'NULL') {
					push(@where,
					    &quotestr($t[$i])." is null");
					}
				else {
					$r[$i] =~ s/'/''/g;
					push(@where,
					    &quotestr($t[$i])." = '$r[$i]'");
					}
				}
			}
		&execute_sql($in{'db'},
				    "delete from ".&quotestr($in{'table'}).
				    " where ".join(" and ", @where));
		$count++;
		}
	&webmin_log("delete", "data", $count, \%in);
	&redirect("view_table.cgi?db=$in{'db'}&".
		  "table=".&urlize($in{'table'})."&start=$in{'start'}".
		  $searchargs);
	}
elsif ($in{'save'}) {
	# Update edited rows
	my $d = &execute_sql($in{'db'}, "select * from ".&quotestr($in{'table'}).
			  " ".$whereclause);
	my @t = @{$d->{'titles'}};
	my $count = 0;
	for(my $j=0; $j<$config{'perpage'}; $j++) {
		next if (!defined($in{"${j}_$t[0]"}));
		my (@where, @set);
		my @r = @{$d->{'data'}->[$j]};
		my @params;
		for(my $i=0; $i<@t; $i++) {
			$r[$i] =~ s/'/''/g;
			if ($str[$i]->{'key'} eq 'PRI') {
				if ($r[$i] eq 'NULL') {
					push(@where,
					     &quotestr($t[$i])." is null");
					}
				else {
					push(@where,
					     &quotestr($t[$i])." = '$r[$i]'");
					}
				}
			my $ij = $in{"${j}_$t[$i]"};
			my $ijdef = $in{"${j}_$t[$i]_def"};
			next if ($ijdef || !defined($ij));
			if (!$config{'blob_mode'} || !&is_blob($str[$i])) {
				$ij =~ s/\r//g;
				}
			push(@set, &quotestr($t[$i])." = ?");
			push(@params, $ij eq '' ? undef : $ij);
			}
		&execute_sql($in{'db'},
				    "update ".&quotestr($in{'table'})." set ".
				    join(" , ", @set)." where ".
				    join(" and ", @where), @params);
		$count++;
		}
	&webmin_log("modify", "data", $count, \%in);
	&redirect("view_table.cgi?db=$in{'db'}&".
		  "table=".&urlize($in{'table'})."&start=$in{'start'}".
		  $searchargs);
	}
elsif ($in{'savenew'}) {
	# Adding a new row
	for(my $j=0; $j<@str; $j++) {
		if (!$config{'blob_mode'} || !&is_blob($str[$j])) {
			$in{$j} =~ s/\r//g;
			}
		push(@set, $in{$j} eq '' ? undef : $in{$j});
		}
	&execute_sql($in{'db'}, "insert into ".&quotestr($in{'table'}).
		    " values (".join(" , ", map { "?" } @set).")", @set);
	&redirect("view_table.cgi?db=$in{'db'}&".
		  "table=".&urlize($in{'table'})."&start=$in{'start'}".
		  $searchargs);
	&webmin_log("create", "data", undef, \%in);
	}
elsif ($in{'cancel'} || $in{'new'}) {
	undef($in{'row'});
	}

my $desc = &text('table_header', "<tt>$in{'table'}</tt>", "<tt>$in{'db'}</tt>");
&ui_print_header($desc, $text{'view_title'}, "");

my $d = &execute_sql($in{'db'},
	"select count(*) from ".&quotestr($in{'table'})." $search");
my $total = int($d->{'data'}->[0]->[0]);
if ($in{'jump'} > 0) {
	$in{'start'} = int($in{'jump'} / $config{'perpage'}) *
		       $config{'perpage'};
	if ($in{'start'} >= $total) {
		$in{'start'} = $total - $config{'perpage'};
		$in{'start'} = int(($in{'start'} / $config{'perpage'}) + 1) *
			       $config{'perpage'};
		}
	}
else {
	$in{'start'} = int($in{'start'});
	}
if ($in{'new'} && $total > $config{'perpage'}) {
	# go to the last screen for adding a row
	$in{'start'} = $total - $config{'perpage'};
	$in{'start'} = int(($in{'start'} / $config{'perpage'}) + 1) *
		       $config{'perpage'};
	}
if ($in{'start'} || $total > $config{'perpage'}) {
	print "<center>\n";
	if ($in{'start'}) {
		printf "<a href='view_table.cgi?db=%s&table=%s&start=%s%s'>".
		       "<img src=/images/left.gif border=0 align=middle></a>\n",
			$in{'db'}, $in{'table'},
			$in{'start'} - $config{'perpage'},
			$searchargs;
		}
	print "<font size=+1>",&text('view_pos', $in{'start'}+1,
	      $in{'start'}+$config{'perpage'} > $total ? $total :
	      $in{'start'}+$config{'perpage'}, $total),"</font>\n";
	if ($in{'start'}+$config{'perpage'} < $total) {
		printf "<a href='view_table.cgi?db=%s&table=%s&start=%s%s'>".
		       "<img src=/images/right.gif border=0 align=middle></a> ",
			$in{'db'}, $in{'table'},
			$in{'start'} + $config{'perpage'},
			$searchargs;
		}
	print "</center>\n";
	}

if ($in{'field'}) {
	# Show details of simple search
	print "<table width=100% cellspacing=0 cellpadding=0><tr>\n";
	print "<td><b>",&text('view_searchhead', "<tt>$in{'for'}</tt>",
			   "<tt>$in{'field'}</tt>"),"</b></td>\n";
	print "<td align=right><a href='view_table.cgi?db=$in{'db'}&",
	      "table=$in{'table'}'>$text{'view_searchreset'}</a></td>\n";
	print "</tr></table>\n";
	}
elsif ($in{'advanced'}) {
	# Show details of advanced search
	print "<table width=100% cellspacing=0 cellpadding=0><tr>\n";
	print "<td><b>",&text('view_searchhead2', scalar(@adv)),"</b></td>\n";
	print "<td align=right><a href='view_table.cgi?db=$in{'db'}&",
	      "table=$in{'table'}'>$text{'view_searchreset'}</a></td>\n";
	print "</tr></table>\n";
	}

if ($config{'blob_mode'}) {
	print "<form action=view_table.cgi method=post enctype=multipart/form-data>\n";
	}
else {
	print "<form action=view_table.cgi method=post>\n";
	}
print "<input type=hidden name=db value='$in{'db'}'>\n";
print "<input type=hidden name=table value='$in{'table'}'>\n";
print "<input type=hidden name=start value='$in{'start'}'>\n";
print $searchhids;
my $check = !defined($in{'row'}) && !$in{'new'} && $keyed;
if ($total || $in{'new'}) {
	$d = &execute_sql($in{'db'},
		"select * from ".&quotestr($in{'table'})." ".$whereclause);
	my @data = @{$d->{'data'}};
	print "<table border width=100%>\n";
	print "<tr $tb>\n";
	print "<td>&nbsp;</td>\n" if ($check);
	my $has_blob;
	foreach my $t (@str) {
		print "<td><b>$t->{'field'}</b></td>\n";
		$has_blob++ if (&is_blob($t));
		}
	print "</tr>\n";

	my %row;
	my $nm;
	map { $row{$_}++ } split(/\0/, $in{'row'});
	my $w = int(100 / scalar(@str));
	$w = 10 if ($w < 10);
	for(my $i=0; $i<@data; $i++) {
		@d = map { $_ eq "NULL" ? undef : $_ } @{$data[$i]};
		print "<tr $cb>\n";
		if ($row{$i} && ($config{'add_mode'} || $has_blob)) {
			# Show multi-line row editor
			printf "<td colspan=%d>\n", scalar(@d);
			print "<table border>\n";
			print "<tr $tb> <td><b>$text{'view_field'}</b></td> ",
			      "<td><b>$text{'view_data'}</b></td> </tr>\n";
			for(my $j=0; $j<@str; $j++) {
				my $nm = "${i}_$str[$j]->{'field'}";
				print "<tr $cb> <td><b>$str[$j]->{'field'}</b></td>\n";
				$d[$j] = &html_escape($d[$j]);
				if ($config{'blob_mode'} &&
				    &is_blob($str[$j])) {
					# Show as keep/upload inputs
					print "<td><input type=radio name=${nm}_def value=1 checked> $text{'view_keep'}\n";
					print "<input type=radio name=${nm}_def value=0> $text{'view_set'}\n";
					print "<input type=file name=$nm></td>\n";
					}
				elsif ($str[$j]->{'type'} =~ /^enum\((.*)\)$/) {
					# Show as enum list
					print "<td>",&ui_select($nm, $d[$j],
					    [ [ "", "&nbsp;" ],
					      map { [ $_ ] } &split_enum($1) ],
					    1, 0, 1),"</td>\n";
					}
				elsif ($str[$j]->{'type'} =~ /\((\d+)\)/) {
					# Show as known-size text
					my $nw = $1 > 70 ? 70 : $1;
					print "<td><input name=$nm size=$nw value=\"$d[$j]\"></td>\n";
					}
				elsif (&is_blob($str[$j])) {
					# Show as multiline text
					print "<td><textarea name=$nm rows=5 cols=70>$d[$j]",
					      "</textarea></td>\n";
					}
				else {
					# Show as fixed-size text
					print "<td><input name=$nm size=30 value=\"$d[$j]\"></td>\n";
					}
				print "</tr>\n";
				}
			print "</table></td>\n";
			}
		elsif ($row{$i}) {
			# Show simple row-editor
			for(my $j=0; $j<@d; $j++) {
				$d[$j] = &html_escape($d[$j]);
				my $l = $d[$j] =~ tr/\n/\n/;
				$nm = "${i}_$d->{'titles'}->[$j]";
				if ($config{'blob_mode'} &&
				    &is_blob($str[$j])) {
					# Cannot edit this blob
					print "<td width=$w%%><br></td>\n";
					}
				elsif ($str[$j]->{'type'} =~ /^enum\((.*)\)$/) {
					# Show as enum list
					print "<td>",&ui_select($nm, $d[$j],
					    [ [ "", "&nbsp;" ],
					      map { [ $_ ] } &split_enum($1) ],
					    1, 0, 1),"</td>\n";
					}
				elsif ($l) {
					# Show as multiline text
					$l++;
					print "<td width=$w%%><textarea name=$nm cols=$w rows=$l>$d[$j]</textarea></td>\n";
					}
				else {
					# Show as known size text
					print "<td width=$w%%><input name=$nm size=$w value=\"$d[$j]\"></td>\n";
					}
				}
			}
		else {
			# Show row contents
			print "<td><input type=checkbox name=row ",
			      "value=$i></td>\n" if ($check);
			my $j = 0;
			foreach my $c (@d) {
				if ($config{'blob_mode'} &&
				    &is_blob($str[$j]) && $c ne '') {
					print "<td width=$w%><a href='download.cgi?db=$in{'db'}&table=$in{'table'}&start=$in{'start'}".$searchargs."&row=$i&col=$j'>$text{'view_download'}</a></td>\n";
					}
				else {
					printf "<td width=$w%%>%s</td>\n",
					 $c =~ /\S/ ? &html_escape($c) : "<br>";
					}
				$j++;
				}
			}
		print "</tr>\n";
		}
	if ($in{'new'} && ($config{'add_mode'} || $has_blob)) {
		# Show new fields in longer format
		print "</table> <br> <table border>\n";
		print "<tr $tb> <td><b>$text{'view_field'}</b></td> ",
		      "<td><b>$text{'view_data'}</b></td> </tr>\n";
		for(my $j=0; $j<@str; $j++) {
			print "<tr $cb> <td><b>$str[$j]->{'field'}</b></td>\n";
			if ($config{'blob_mode'} && &is_blob($str[$j])) {
				print "<td><input name=$j type=file></td>\n";
				}
			elsif ($str[$j]->{'type'} =~ /\((\d+)\)/) {
				my $nw = $1 > 70 ? 70 : $1;
				print "<td><input name=$j size=$nw></td>\n";
				}
			elsif ($str[$j]->{'type'} =~ /^enum\((.*)\)$/) {
				# Show as enum list
				print "<td>",&ui_select($j, $d[$j],
				    [ [ "", "&nbsp;" ],
				      map { [ $_ ] } &split_enum($1) ],
				    1, 0, 1),"</td>\n";
				}
			elsif (&is_blob($str[$j])) {
				print "<td><textarea name=$j rows=5 cols=70>",
				      "</textarea></td>\n";
				}
			else {
				print "<td><input name=$j size=30></td>\n";
				}
			print "</tr>\n";
			}
		}
	elsif ($in{'new'}) {
		# Show new fields in a row below table
		print "<tr $cb>\n";
		for(my $j=0; $j<@str; $j++) {
			if ($config{'blob_mode'} &&
			    &is_blob($str[$j])) {
				# Show as file upload
				print "<td><input name=$j type=file></td>\n";
				}
			elsif ($str[$j]->{'type'} =~ /^enum\((.*)\)$/) {
				# Show as enum list
				print "<td>",&ui_select($j, $d[$j],
				    [ [ "", "&nbsp;" ],
				      map { [ $_ ] } &split_enum($1) ],
				    1, 0, 1),"</td>\n";
				}
			else {
				# Show as text field
				print "<td width=$w%><input name=$j ",
				      "size=$w></td>\n";
				}
			}
		print "</tr>\n";
		}
	print "</table>\n";
	if ($check) {
		print &select_all_link("row", 0, $text{'view_all'}),"&nbsp;\n";
		print &select_invert_link("row", 0, $text{'view_invert'}),"<br>\n";
		}
	}
else {
	print "<b>$text{'view_none'}</b> <p>\n";
	}

print "<table width=100%><tr>\n";
if (!$keyed) {
	print "<tr> <td><b>$text{'view_nokey'}</b></td> </tr>\n";
	}
elsif (!$check) {
	if ($in{'new'}) {
		print "<td><input type=submit name=savenew ",
		      "value='$text{'save'}'></td>\n";
		}
	else {
		print "<td><input type=submit name=save ",
		      "value='$text{'save'}'></td>\n";
		}
	print "<td align=right><input type=submit name=cancel ",
	      "value='$text{'cancel'}'></td>\n";
	}
else {
	print "<td><input type=submit name=edit ",
	      "value='$text{'view_edit'}'></td>\n";
	print "<td align=middle><input type=submit name=new ",
	      "value='$text{'view_new'}'></td>\n";
	print "<td align=right><input type=submit name=delete ",
	      "value='$text{'view_delete'}'></td>\n";
	}
print "</tr></table></form>\n";

if (!$in{'field'} && $total > $config{'perpage'}) {
	print "<hr>\n";
	print "<table width=100%><tr>\n";
	print "<form action=view_table.cgi>\n";
	print "<input type=hidden name=search value=1>\n";
	print &ui_hidden("db", $in{'db'});
	print &ui_hidden("table", $in{'table'});
	my $sel = &ui_select("field", undef,
			[ map { [ $_->{'field'}, $_->{'field'} ] } @str ]);
	my $match = &ui_select("match", 0,
			[ map { [ $_, $text{'view_match'.$_} ] } (0.. 3) ]);
	print "<td>",&text('view_search2', "<input name=for size=20>", $sel,
			   $match);
	print "&nbsp;&nbsp;",
	      "<input type=submit value='$text{'view_searchok'}'></td>\n";
	print "</form>\n";

	print "<form action=view_table.cgi>\n";
	print &ui_hidden("db", $in{'db'});
	print &ui_hidden("table", $in{'table'});
	print "<td align=right><input type=submit value='$text{'view_jump'}'> ";
	print "<input name=jump size=6></td></form>\n";

	print "</tr><tr>\n";

	print "<form action=search_form.cgi>\n";
	print &ui_hidden("db", $in{'db'});
	print &ui_hidden("table", $in{'table'});
	print "<td><input type=submit value='$text{'view_adv'}'></td>\n";
	print "</form>\n";

	print "</tr> </table>\n";
	}

&ui_print_footer("edit_dbase.cgi?db=$in{'db'}", $text{'dbase_return'},
		 "", $text{'index_return'});

# make_like(mode, for)
sub make_like
{
my ($match, $for) = @_;
return $match == 0 ? "like \"%$for%\"" :
       $match == 1 ? "like \"$for\"" :
       $match == 2 ? "not like \"%$for%\"" :
       $match == 3 ? "not like \"$for\"" : " = \"\"";
}
