#!/usr/local/bin/perl
# save_field.cgi
# Create, modify or delete a field
use strict;
use warnings;
our (%text, %in);

require './virtualmin-oracle-lib.pl';
&ReadParse();
&can_edit_db($in{'db'}) || &error($text{'dbase_ecannot'});
&error_setup($text{'field_err'});

my $size;
if ($in{'delete'}) {
	# delete this field
	&execute_sql($in{'db'},
		    "alter table $in{'table'} drop column ".&quotestr($in{'old'}));
	&webmin_log("delete", "field", $in{'old'}, \%in);
	}
elsif ($in{'new'}) {
	# add a new field
	$in{'field'} =~ /^\S+$/ || &error(&text('field_efield', $in{'field'}));
	$in{'null'} && $in{'key'} && &error($text{'field_ekey'});
	$in{'size'} = $size = &validate_size();
	my $sql = sprintf "alter table %s add %s %s%s %s",
		&quotestr($in{'table'}), &quotestr($in{'field'}), $in{'type'},
		$size, $in{'null'} ? '' : 'not null';
	&execute_sql($in{'db'}, $sql);
	&webmin_log("create", "field", $in{'field'}, \%in);
	}
else {
	# modify an existing field
	$in{'field'} =~ /^\S+$/ || &error(&text('field_efield', $in{'field'}));
	$in{'null'} && $in{'key'} && &error($text{'field_ekey'});
	$in{'size'} = $size = &validate_size();
	my $sql = sprintf "alter table %s modify %s %s%s %s",
			&quotestr($in{'table'}), &quotestr($in{'old'}),
			$in{'type'}, $size, $in{'null'} ? 'null' : 'not null';
	&execute_sql($in{'db'}, $sql);
	if ($in{'old'} ne $in{'field'} ||
	    $in{'type'} ne $in{'newtype'}) {
		# Rename or retype field as well
		if ($in{'type'} ne $in{'newtype'}) {
			# Type has changed .. fix size
			if ($in{'newtype'} eq 'enum' ||
			    $in{'newtype'} eq 'set') {
				# Convert old size to enum values
				if ($in{'type'} ne 'enum' &&
				    $in{'type'} ne 'set') {
					$size = $size =~ /^\((.*)\)/ ?
					    '('.join(",", map { "'$_'" }
						 split(/\n/, $1)).')' : "('')";
					}
				}
			elsif ($in{'newtype'} eq 'float' ||
			       $in{'newtype'} eq 'double' ||
			       $in{'newtype'} eq 'decimal') {
				# Use old sizes or size and opts
				$size = $size =~ /^\((\d+),(\d+)\)/ ? $size :
				  $size =~ /^\((\d+)\)(.*)/ ? "($1,$1)$2" : "";
				}
			elsif ($in{'newtype'} eq 'date' ||
			       $in{'newtype'} eq 'datetime' ||
			       $in{'newtype'} eq 'time' ||
			       $in{'newtype'} =~ /(blob|text)$/) {
				# New type has no size or opts
				$size = "";
				}
			else {
				# Use old size and opts
				$size = $size =~ /^\((\d+)/ ?
					"($1) $in{'opts'}" :
					$in{'newtype'} =~ /char$/ ?
					    "(255) $in{'opts'}" : $in{'opts'};
				}
			}
		$sql = sprintf "alter table %s change %s %s %s%s %s",
				&quotestr($in{'table'}), &quotestr($in{'old'}),
				&quotestr($in{'field'}), $in{'newtype'}, $size,
				$in{'null'} ? '' : 'not null';
		&execute_sql($in{'db'}, $sql);
		}
	&webmin_log("modify", "field", $in{'field'}, \%in);
	}

my (@pri, @npri);
if ($in{'key'} != $in{'oldkey'}) {
	# Adding or removing a primary key to the table
	foreach my $d (&table_structure($in{'db'}, $in{'table'})) {
		push(@pri, $d->{'field'}) if ($d->{'key'} eq 'PRI');
		}
	if ($in{'key'}) {
		@npri = ( @pri, $in{'field'} );
		}
	else {
		@npri = grep { $_ ne $in{'field'} } @pri;
		}
	&execute_sql($in{'db'},
		    "alter table ".&quotestr($in{'table'})." drop primary key")
		if (@pri);
	&execute_sql($in{'db'},
		    "alter table ".&quotestr($in{'table'})." add primary key (".
		    join(",", map { &quotestr($_) } @npri).")") if (@npri);
	}
&redirect("edit_table.cgi?db=$in{'db'}&table=".&urlize($in{'table'}));

sub validate_size
{
if ($in{'type'} eq 'number') {
	$in{'size1'} =~ /^\d+$/ || &error(&text('field_esize', $in{'size1'}));
	$in{'size2'} =~ /^\d+$/ || &error(&text('field_esize', $in{'size2'}));
	return "($in{'size1'},$in{'size2'})";
	}
elsif ($in{'type'} eq 'date' || $in{'type'} eq 'datetime' ||
       $in{'type'} eq 'time' || $in{'type'} =~ /(long|raw|blob)$/) {
	return "";
	}
elsif ($in{'size_def'}) {
	return "";
	}
else {
	$in{'size'} =~ /^\d+$/ || &error(&text('field_esize', $in{'size'}));
	return "($in{'size'}) $in{'opts'}";
	}
}
